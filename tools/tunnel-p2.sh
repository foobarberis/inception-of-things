#!/usr/bin/env bash
set -euo pipefail

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-mbernard}"
VM_HOST="${VM_HOST:-localhost}"
P2_IP="192.168.56.110"
P2_PORT=80
LOCAL_PORT=18088

if ! command -v ssh >/dev/null 2>&1; then
    echo "Required command not found: ssh" >&2
    exit 1
fi

if [[ ! -r "$SSH_KEY_PATH" ]]; then
    echo "Cannot read SSH key: $SSH_KEY_PATH" >&2
    exit 1
fi

printf 'Forwarding http://127.0.0.1:%s to %s:%s through the outer VM.\n' \
    "$LOCAL_PORT" "$P2_IP" "$P2_PORT"
printf 'Press Ctrl-C to stop the tunnel.\n'

exec ssh -4 -N \
    -o ExitOnForwardFailure=yes \
    -L "127.0.0.1:$LOCAL_PORT:$P2_IP:$P2_PORT" \
    -i "$SSH_KEY_PATH" \
    -p "$SSH_PORT" \
    -o IdentitiesOnly=yes \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    "$VM_USER@$VM_HOST"
