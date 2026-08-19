#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$HOME/.kube/config"

printf '\n==> Required Kubernetes namespaces: argocd and dev\n'
kubectl get ns

printf '\n==> Argo CD application synchronization (wait up to 300 seconds)\n'
kubectl wait -n argocd \
  --for=jsonpath='{.status.sync.status}'=Synced \
  application.argoproj.io/wil-playground --timeout=300s

printf '\n==> Argo CD application status\n'
kubectl get applications.argoproj.io -n argocd

printf '\n==> Application pod in the dev namespace\n'
kubectl get pods -n dev

printf '\n==> Application HTTP response on localhost:8888\n'
curl -sS http://localhost:8888/
