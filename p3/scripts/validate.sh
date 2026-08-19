#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$HOME/.kube/config"

kubectl get ns
kubectl wait -n argocd \
  --for=jsonpath='{.status.sync.status}'=Synced \
  application.argoproj.io/wil-playground --timeout=300s
kubectl get applications.argoproj.io -n argocd
kubectl get pods -n dev
curl -sS http://localhost:8888/
