#!/bin/bash

# set -euo pipefail
#
# CLUSTER_NAME="iot-bonus"
# GITLAB_NAMESPACE="gitlab"
# ARGOCD_NAMESPACE="argocd"
# DEV_NAMESPACE="dev"
# GITLAB_CHART_VERSION="8.1.0"
#
# REPO_NAME="mbernard-iot"
# CONFS_DIR="$(cd "$(dirname "$0")/../confs" && pwd)"



set -e

k3d cluster delete --all

GITLAB_NAMESPACE="gitlab"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
GITLAB_DOMAIN="gitlab.local"
REPO_NAME="mbernard-iot"
CONFS_DIR="$(dirname "$0")/../confs"

# ---------- Dépendances (identique à p3, + Helm) ----------

if ! command -v docker &>/dev/null; then
    echo "Execute docker.sh first, then disconnect and reconnect in SSH"
    exit 1
fi

sudo apt-get install -y -qq kubectl
command -v jq &>/dev/null || sudo apt-get install -y -qq jq

if ! command -v k3d &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if ! command -v helm &>/dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v argocd &>/dev/null; then
    curl -sSL -o /tmp/argocd \
        https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /tmp/argocd
    sudo mv /tmp/argocd /usr/local/bin/argocd
fi

# ---------- Cluster (identique à p3) ----------

if ! k3d cluster list | grep -q "iot-bonus"; then
    k3d cluster create iot-bonus \
        -p "8888:8888@loadbalancer" \
        -p "8086:443@loadbalancer" \
        --wait
fi

export KUBECONFIG="$HOME/.kube/config"
kubectl config use-context k3d-iot-bonus

# ---------- Namespaces ----------

kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$DEV_NAMESPACE"    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$GITLAB_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ---------- Argo CD (identique à p3 — manifest officiel) ----------

kubectl apply -n "$ARGOCD_NAMESPACE" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true

kubectl wait --for=condition=available \
    --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE"

kubectl patch configmap argocd-cmd-params-cm -n "$ARGOCD_NAMESPACE" \
    --type merge -p '{"data": {"server.insecure": "true"}}'

kubectl patch svc argocd-server -n "$ARGOCD_NAMESPACE" \
    --type merge -p '{"spec":{"type":"ClusterIP"}}'

kubectl rollout restart deployment argocd-server -n "$ARGOCD_NAMESPACE"
kubectl rollout status  deployment argocd-server -n "$ARGOCD_NAMESPACE"

# ---------- GitLab via Helm ----------

helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || helm repo update
helm repo update

# On épingle à la dernière version 8.x : Redis/PostgreSQL/MinIO bundlés,
# pas besoin d'object storage externe (supprimé en 9.x+)
GITLAB_CHART_VERSION=$(helm search repo gitlab/gitlab --versions --output json \
    | python3 -c "
import sys, json
charts = json.load(sys.stdin)
v8 = [c for c in charts if c['version'].startswith('8.')]
print(v8[0]['version'])
")
echo "Chart GitLab épinglé : ${GITLAB_CHART_VERSION}"
echo "AppVersion : $(helm show chart gitlab/gitlab --version ${GITLAB_CHART_VERSION} | grep appVersion | awk '{print $2}')" 

helm upgrade --install gitlab gitlab/gitlab \
    --version "${GITLAB_CHART_VERSION}" \
    --namespace "${GITLAB_NAMESPACE}" \
    -f "${CONFS_DIR}/gitlab-values.yaml" \
    --timeout 900s \
    --wait

kubectl rollout status deployment/gitlab-webservice-default \
    -n "${GITLAB_NAMESPACE}" --timeout=600s

# ---------- DNS : gitlab.local → ClusterIP dans CoreDNS ----------

GITLAB_IP=""
for i in $(seq 1 30); do
    GITLAB_IP=$(kubectl get svc gitlab-webservice-default \
        -n "${GITLAB_NAMESPACE}" \
        -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
    [ -n "${GITLAB_IP}" ] && break
    sleep 5
done
[ -z "${GITLAB_IP}" ] && echo "Impossible de récupérer l'IP GitLab" && exit 1

# Écrire un ConfigMap CoreDNS propre sans sed multi-ligne fragile
kubectl get cm coredns -n kube-system -o jsonpath='{.data.Corefile}' > /tmp/Corefile.orig

# Injecter le bloc hosts juste avant la dernière accolade fermante du bloc ".:53"
python3 - "${GITLAB_IP}" "${GITLAB_DOMAIN}" << 'EOF'
import sys, re
ip, domain = sys.argv[1], sys.argv[2]
content = open('/tmp/Corefile.orig').read()
hosts_block = f"\n    hosts {{\n      {ip} {domain}\n      fallthrough\n    }}"
# Insère avant le "}" fermant le bloc .:53
patched = re.sub(r'(\s+ready\b)', r'\1' + hosts_block, content, count=1)
open('/tmp/Corefile.patched', 'w').write(patched)
EOF

kubectl create configmap coredns \
    -n kube-system \
    --from-file=Corefile=/tmp/Corefile.patched \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status  deployment/coredns -n kube-system --timeout=60s

# /etc/hosts de la VM hôte
grep -q "${GITLAB_DOMAIN}" /etc/hosts \
    || echo "127.0.0.1  ${GITLAB_DOMAIN}" | sudo tee -a /etc/hosts

# ---------- GitLab : mot de passe root ----------

GITLAB_ROOT_PASSWORD=""
for i in $(seq 1 20); do
    GITLAB_ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
        -n "${GITLAB_NAMESPACE}" \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    [ -n "${GITLAB_ROOT_PASSWORD}" ] && break
    sleep 5
done
[ -z "${GITLAB_ROOT_PASSWORD}" ] && echo "Secret GitLab introuvable" && exit 1

# ---------- GitLab : créer le projet et pousser les manifests ----------

GITLAB_URL="http://${GITLAB_DOMAIN}"

echo "Attente de l'API GitLab..."
for i in $(seq 1 30); do
    curl -sf "${GITLAB_URL}/api/v4/version" -u "root:${GITLAB_ROOT_PASSWORD}" \
        &>/dev/null && break
    sleep 10
done

PROJECT_EXISTS=$(curl -sf \
    "${GITLAB_URL}/api/v4/projects?search=${REPO_NAME}" \
    -u "root:${GITLAB_ROOT_PASSWORD}" | jq length)

if [ "${PROJECT_EXISTS}" -eq 0 ]; then
    curl -sf -X POST "${GITLAB_URL}/api/v4/projects" \
        -u "root:${GITLAB_ROOT_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${REPO_NAME}\", \"visibility\": \"public\", \
             \"initialize_with_readme\": false}" > /dev/null
    echo "Projet ${REPO_NAME} créé dans GitLab."
fi

TMP_REPO=$(mktemp -d)
git -C "${TMP_REPO}" init
git -C "${TMP_REPO}" config user.email "root@gitlab.local"
git -C "${TMP_REPO}" config user.name "root"
cp "${CONFS_DIR}/deployment.yaml" "${TMP_REPO}/"
git -C "${TMP_REPO}" add deployment.yaml
git -C "${TMP_REPO}" commit -m "Initial deploy — wil42/playground:v1"
git -C "${TMP_REPO}" remote add origin \
    "http://root:${GITLAB_ROOT_PASSWORD}@${GITLAB_DOMAIN}/root/${REPO_NAME}.git"
git -C "${TMP_REPO}" push -u origin master
rm -rf "${TMP_REPO}"

# ---------- Argo CD : pointer sur GitLab local (remplace GitHub) ----------

# Port-forward temporaire pour argocd CLI
kubectl port-forward svc/argocd-server -n "${ARGOCD_NAMESPACE}" 8080:80 &
PF_PID=$!
sleep 3

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d)

argocd login localhost:8080 \
    --username admin \
    --password "${ARGOCD_PASSWORD}" \
    --insecure

argocd repo add "http://${GITLAB_DOMAIN}/root/${REPO_NAME}.git" \
    --username root \
    --password "${GITLAB_ROOT_PASSWORD}" \
    --insecure-skip-server-verification

kill ${PF_PID} 2>/dev/null || true

# Appliquer le manifest Argo CD (repoURL pointe sur GitLab local)
kubectl apply -f "${CONFS_DIR}/argocd.yaml"

# ---------- Résumé (identique à p3) ----------

echo ""
echo "Finished setup"
echo "App    : curl http://localhost:8888/"
echo "ArgoCD : https://localhost:8086  (login: admin)"
echo "GitLab : http://${GITLAB_DOMAIN}  (login: root)"
echo ""
echo "Mot de passe ArgoCD :"
echo "  kubectl get secret argocd-initial-admin-secret \
-n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Mot de passe GitLab root : ${GITLAB_ROOT_PASSWORD}"
echo ""
echo "Pour changer la version de l'app :"
echo "  Modifier deployment.yaml (v1→v2), commit+push sur le GitLab local"
echo "  Argo CD détecte et redéploie automatiquement."
