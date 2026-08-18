#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR/.."

vagrant status

vagrant ssh mbernardS -c \
  'hostname; ip -o -4 addr show to 192.168.56.110; systemctl is-active k3s'

vagrant ssh mbernardSW -c \
  'hostname; ip -o -4 addr show to 192.168.56.111; systemctl is-active k3s-agent'

vagrant ssh mbernardS -c 'kubectl get nodes -o wide'
vagrant ssh mbernardS -c 'kubectl get pods -A'
