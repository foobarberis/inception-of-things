#!/bin/bash
set -e

if ! command -v docker &>/dev/null; then
    "Execute docker.sh first, then disconnect and reconnect in SHH"
    exit
fi
sudo apt-get install -y -qq kubectl

curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

k3d cluster create iot-p3

export KUBECONFIG="$HOME/.kube/config"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available \
    --timeout=300s deployment/argocd-server -n argocd

kubectl apply -f "$(dirname "$0")/../confs/argocd.yaml"

echo "Finished setup"

echo "Port-forward appli :"
echo "  kubectl port-forward svc/wil-playground 8888:8888 -n dev &"
echo "  curl http://localhost:8888/"
echo ""
echo "Mot de passe Argo CD :"
kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath='{.data.password}' | base64 -d
echo "UI Argo CD :"
echo "  kubectl port-forward svc/argocd-server 8080:443 -n argocd &"
echo "  https://localhost:8080  (login: admin)"
