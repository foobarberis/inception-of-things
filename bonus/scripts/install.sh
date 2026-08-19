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

set -euo pipefail

CLUSTER_NAME="iot-bonus"
GITLAB_NAMESPACE="gitlab"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
GITLAB_DOMAIN="gitlab.local"
GITLAB_CHART_VERSION="8.1.0"
REPO_NAME="mbernard-iot"
CONFS_DIR="$(cd "$(dirname "$0")/../confs" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

install_deps() {
  info "Vérification des dépendances..."

  if ! command -v docker &>/dev/null; then
    info "Installation de Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    newgrp docker <<'EOF'
EOF
  fi

  if ! command -v k3d &>/dev/null; then
    info "Installation de K3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi

  if ! command -v kubectl &>/dev/null; then
    info "Installation de kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
  fi

  if ! command -v helm &>/dev/null; then
    info "Installation de Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  if ! command -v argocd &>/dev/null; then
    info "Installation de argocd CLI..."
    sudo curl -sSL -o /usr/local/bin/argocd \
      https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo chmod +x /usr/local/bin/argocd
  fi

  command -v git  &>/dev/null || sudo apt-get install -y git
  command -v curl &>/dev/null || sudo apt-get install -y curl
  command -v jq   &>/dev/null || sudo apt-get install -y jq

  info "Dépendances OK."
}

create_cluster() {
  if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
    warn "Cluster '${CLUSTER_NAME}' déjà existant — on le supprime pour repartir propre."
    k3d cluster delete "${CLUSTER_NAME}"
  fi

  info "Création du cluster K3d '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    --agents 2 \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=metrics-server@server:0" \
    --port "8888:8888@loadbalancer" \
    --port "80:80@loadbalancer" \
    --wait

  kubectl config use-context "k3d-${CLUSTER_NAME}"
  info "Cluster prêt."
}

create_namespaces() {
  info "Création des namespaces..."
  for ns in "${GITLAB_NAMESPACE}" "${ARGOCD_NAMESPACE}" "${DEV_NAMESPACE}"; do
    kubectl get namespace "${ns}" &>/dev/null \
      || kubectl create namespace "${ns}"
  done
}

install_traefik() {
  info "Installation de Traefik..."
  helm repo add traefik https://traefik.github.io/charts
  helm repo update

  helm upgrade --install traefik traefik/traefik \
    --namespace kube-system \
    --set service.type=LoadBalancer \
    --set ports.web.exposedPort=80 \
    --wait --timeout 120s
}

install_argocd() {
  info "Installation d'Argo CD..."
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update

  helm upgrade --install argocd argo/argo-cd \
    --namespace "${ARGOCD_NAMESPACE}" \
    --set server.service.type=LoadBalancer \
    --set configs.params."server\.insecure"=true \
    --wait --timeout 180s

  info "Argo CD installé."
}

install_gitlab() {
  info "Ajout du repo Helm GitLab..."
  helm repo add gitlab https://charts.gitlab.io/
  helm repo update

  info "Installation de GitLab CE (version ${GITLAB_CHART_VERSION})..."
  info "Cette étape peut prendre 5 à 15 minutes selon les ressources disponibles."

  helm upgrade --install gitlab gitlab/gitlab \
    --version "${GITLAB_CHART_VERSION}" \
    --namespace "${GITLAB_NAMESPACE}" \
    -f "${CONFS_DIR}/gitlab-values.yaml" \
    --timeout 900s \
    --wait

  info "GitLab installé. Attente de la disponibilité du webservice..."
  kubectl rollout status deployment/gitlab-webservice-default \
    -n "${GITLAB_NAMESPACE}" --timeout=600s
}

patch_coredns() {
  info "Récupération de l'IP du service GitLab webservice..."

  local GITLAB_IP=""
  local retries=30
  while [[ -z "${GITLAB_IP}" && retries -gt 0 ]]; do
    GITLAB_IP=$(kubectl get svc gitlab-webservice-default \
      -n "${GITLAB_NAMESPACE}" \
      -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
    [[ -z "${GITLAB_IP}" ]] && sleep 5 && ((retries--))
  done

  [[ -z "${GITLAB_IP}" ]] && error "Impossible de récupérer l'IP du service GitLab."
  info "IP GitLab webservice : ${GITLAB_IP}"

  info "Patch de CoreDNS pour résoudre ${GITLAB_DOMAIN} → ${GITLAB_IP}..."
  kubectl get cm coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml

  if ! kubectl get cm coredns -n kube-system -o yaml | grep -q "${GITLAB_DOMAIN}"; then
    kubectl patch cm coredns -n kube-system --type=json \
      -p="[{
        \"op\": \"replace\",
        \"path\": \"/data/Corefile\",
        \"value\": \"$(kubectl get cm coredns -n kube-system -o jsonpath='{.data.Corefile}' \
          | sed "s|ready|ready\n    hosts {\n      ${GITLAB_IP} ${GITLAB_DOMAIN}\n      fallthrough\n    }|" \
          | sed ':a;N;$!ba;s/\n/\\n/g' \
          | sed 's/\t/\\t/g'
        )\"
      }]"

    kubectl rollout restart deployment/coredns -n kube-system
    kubectl rollout status deployment/coredns -n kube-system --timeout=60s
  else
    warn "CoreDNS déjà patché pour ${GITLAB_DOMAIN}."
  fi

  if ! grep -q "${GITLAB_DOMAIN}" /etc/hosts; then
    echo "127.0.0.1  ${GITLAB_DOMAIN}" | sudo tee -a /etc/hosts
    info "/etc/hosts mis à jour."
  fi
}

get_gitlab_password() {
  info "Récupération du mot de passe root GitLab..."
  local retries=20
  local GITLAB_ROOT_PASSWORD=""

  while [[ -z "${GITLAB_ROOT_PASSWORD}" && retries -gt 0 ]]; do
    GITLAB_ROOT_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
      -n "${GITLAB_NAMESPACE}" \
      -o jsonpath='{.data.password}' 2>/dev/null \
      | base64 -d 2>/dev/null || true)
    [[ -z "${GITLAB_ROOT_PASSWORD}" ]] && sleep 5 && ((retries--))
  done

  [[ -z "${GITLAB_ROOT_PASSWORD}" ]] && error "Secret GitLab introuvable."
  echo "${GITLAB_ROOT_PASSWORD}"
}

setup_gitlab_repo() {
  local PASSWORD="$1"
  local GITLAB_URL="http://${GITLAB_DOMAIN}"

  info "Attente que l'API GitLab soit accessible..."
  local retries=30
  until curl -sf "${GITLAB_URL}/api/v4/version" -u "root:${PASSWORD}" &>/dev/null; do
    sleep 10 && ((retries--))
    [[ retries -eq 0 ]] && error "API GitLab inaccessible après timeout."
  done

  local PROJECT_EXISTS
  PROJECT_EXISTS=$(curl -sf "${GITLAB_URL}/api/v4/projects?search=${REPO_NAME}" \
    -u "root:${PASSWORD}" | jq length)

  if [[ "${PROJECT_EXISTS}" -eq 0 ]]; then
    info "Création du projet '${REPO_NAME}' dans GitLab local..."
    curl -sf -X POST "${GITLAB_URL}/api/v4/projects" \
      -u "root:${PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"${REPO_NAME}\", \"visibility\": \"public\", \"initialize_with_readme\": false}" \
      > /dev/null
    info "Projet créé."
  else
    warn "Projet '${REPO_NAME}' déjà existant dans GitLab."
  fi

  info "Push du deployment.yaml vers le GitLab local..."
  local TMP_DIR
  TMP_DIR=$(mktemp -d)
  cd "${TMP_DIR}"

  git init
  git config user.email "root@gitlab.local"
  git config user.name "root"

  cp "${CONFS_DIR}/deployment.yaml" .
  git add deployment.yaml
  git commit -m "Initial deploy — wil42/playground:v1"

  git remote add origin \
    "http://root:${PASSWORD}@${GITLAB_DOMAIN}/root/${REPO_NAME}.git"
  git push -u origin master

  cd - > /dev/null
  rm -rf "${TMP_DIR}"
  info "Manifests poussés."
}

setup_argocd() {
  local PASSWORD="$1"

  info "Récupération du mot de passe Argo CD initial..."
  local ARGOCD_PASSWORD
  ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.data.password}' | base64 -d)

  info "Login Argo CD..."
  kubectl port-forward svc/argocd-server -n "${ARGOCD_NAMESPACE}" 8080:443 &>/dev/null &
  PF_PID=$!
  sleep 3

  argocd login localhost:8080 \
    --username admin \
    --password "${ARGOCD_PASSWORD}" \
    --insecure

  info "Ajout du dépôt GitLab local dans Argo CD..."
  argocd repo add "http://${GITLAB_DOMAIN}/root/${REPO_NAME}.git" \
    --username root \
    --password "${PASSWORD}" \
    --insecure-skip-server-verification

  info "Déploiement de l'Application Argo CD..."
  kubectl apply -f "${CONFS_DIR}/argocd-app.yaml"

  info "Synchronisation manuelle initiale..."
  argocd app sync playground --timeout 120

  kill ${PF_PID} 2>/dev/null || true
  info "Argo CD configuré."
}

verify() {
  info "=== Vérifications ==="
  echo ""
  echo "Namespaces :"
  kubectl get ns | grep -E "gitlab|argocd|dev"
  echo ""
  echo "Pods GitLab :"
  kubectl get pods -n "${GITLAB_NAMESPACE}" --no-headers | awk '{print $1, $3}'
  echo ""
  echo "Pods Argo CD :"
  kubectl get pods -n "${ARGOCD_NAMESPACE}" --no-headers | awk '{print $1, $3}'
  echo ""
  echo "App dans dev :"
  kubectl get pods -n "${DEV_NAMESPACE}"
  echo ""
  info "Test de l'app :"
  curl -sf http://localhost:8888/ || warn "App pas encore accessible (retry dans quelques secondes)"
}

main() {
  info "=== IoT Bonus — Démarrage ==="

  install_deps
  create_cluster
  create_namespaces
  install_traefik
  install_argocd
  install_gitlab
  patch_coredns

  GITLAB_ROOT_PASSWORD=$(get_gitlab_password)
  info "Mot de passe root GitLab : ${GITLAB_ROOT_PASSWORD}"

  setup_gitlab_repo "${GITLAB_ROOT_PASSWORD}"
  setup_argocd "${GITLAB_ROOT_PASSWORD}"
  verify

  echo ""
  echo "  GitLab   : http://${GITLAB_DOMAIN}  (user: root / pw: ${GITLAB_ROOT_PASSWORD})"
  echo "  Argo CD  : http://localhost:8080    (user: admin / pw récupéré via secret)"
  echo "  App dev  : http://localhost:8888"
  echo ""
}

main "$@"
