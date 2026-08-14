#!/bin/bash
set -e

# Add Docker's official GPG key:
sudo apt update -qq
sudo apt install -qq ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update -qq
sudo apt install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"

curl -fsSL https://get.docker.com | sh

KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

k3d cluster create iot-p3

export KUBECONFIG="$HOME/.kube/config"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -

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
