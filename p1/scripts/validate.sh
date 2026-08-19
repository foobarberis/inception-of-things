#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR/.."

printf '\n==> Vagrant VM status\n'
vagrant status

printf '\n==> Server: hostname, dedicated IP, and K3s controller service\n'
vagrant ssh mbernardS -c \
  'hostname; ip -o -4 addr show to 192.168.56.110; systemctl is-active k3s'

printf '\n==> Worker: hostname, dedicated IP, and K3s agent service\n'
vagrant ssh mbernardSW -c \
  'hostname; ip -o -4 addr show to 192.168.56.111; systemctl is-active k3s-agent'

printf '\n==> K3s cluster nodes: server and worker must be Ready\n'
vagrant ssh mbernardS -c 'kubectl get nodes -o wide'

printf '\n==> K3s system workload status\n'
vagrant ssh mbernardS -c 'kubectl get pods -A'
