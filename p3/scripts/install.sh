#!/bin/bash
set -e

if ! command -v docker &>/dev/null; then
    "Execute docker.sh first, then disconnect and reconnect in SHH"
    exit
fi

sudo apt-get install -y -qq kubectl

if ! command -v k3d &>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if ! k3d cluster list | grep -q "iot-p3"; then
    k3d cluster create iot-p3 \
    -p "8888:8888@loadbalancer" \
    -p "8086:80@loadbalancer" \
    --wait
fi

export KUBECONFIG="$HOME/.kube/config"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --server-side -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available \
    --timeout=300s deployment/argocd-server -n argocd

kubectl patch configmap argocd-cmd-params-cm -n argocd \
    --type merge -p '{"data": {"server.insecure": "true"}}'

kubectl patch svc argocd-server -n argocd \
  --type merge \
  -p '{"spec":{"type":"ClusterIP"}}'

kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd

kubectl apply -f "$(dirname "$0")/../confs/argocd.yaml"

echo "Finished setup"
echo "App    : curl http://localhost:8888/"
echo "ArgoCD : http://localhost:8086  (login: admin)"
echo "To get the password, do :"
echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
