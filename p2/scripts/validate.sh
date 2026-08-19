#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR/.."

printf '\n==> Vagrant VM status\n'
vagrant status

printf '\n==> Server: hostname and dedicated IP address\n'
vagrant ssh mbernardS -c 'hostname; ip -o -4 addr show to 192.168.56.110'

printf '\n==> K3s controller node status\n'
vagrant ssh mbernardS -c 'kubectl get nodes -o wide'

printf '\n==> Kubernetes workloads and services\n'
vagrant ssh mbernardS -c 'kubectl get all'

printf '\n==> App deployments, replica counts, and pod placement\n'
vagrant ssh mbernardS -c 'kubectl get deployment app1 app2 app3; kubectl get pods -o wide'

printf '\n==> Traefik Ingress routing rules\n'
vagrant ssh mbernardS -c 'kubectl get ingress -o wide; kubectl describe ingress apps-ingress'

printf '\n==> App 1 response for Host: app1.com\n'
curl -fsS -H 'Host: app1.com' http://192.168.56.110/ | grep -F 'Hello from app1.'

printf '\n==> App 2 response for Host: app2.com\n'
curl -fsS -H 'Host: app2.com' http://192.168.56.110/ | grep -F 'Hello from app2.'

printf '\n==> App 3 catch-all response\n'
curl -fsS http://192.168.56.110/ | grep -F 'Hello from app3.'
