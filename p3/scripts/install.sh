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
    k3d cluster create iot-p3
fi

export KUBECONFIG="$HOME/.kube/config"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true

kubectl wait --for=condition=available \
    --timeout=300s deployment/argocd-server -n argocd

kubectl apply -f "$(dirname "$0")/../confs/argocd.yaml"

echo "Finished setup"

echo "To Port-forward appli to the host, do :"
echo "  Inside the VM : kubectl port-forward svc/wil-playground 8888:8888 -n dev --address 0.0.0.0 &"
echo "  On the host : curl http://localhost:8888/"
echo ""
echo "To get the password, do :"
echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "To Port-forward Argo CD to the host, do :"
echo "  Inside the VM : kubectl port-forward svc/argocd-server 8086:443 -n argocd --address 0.0.0.0 &"
echo "  On the host : https://localhost:8086  (login: admin)"
