#!/usr/bin/env bash
set -euo pipefail

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-mbernard}"
VM_HOST="${VM_HOST:-localhost}"

if ! command -v ssh >/dev/null 2>&1; then
    echo "Required command not found: ssh" >&2
    exit 1
fi

if [[ ! -r "$SSH_KEY_PATH" ]]; then
    echo "Cannot read SSH key: $SSH_KEY_PATH" >&2
    exit 1
fi

exec ssh \
    -i "$SSH_KEY_PATH" \
    -p "$SSH_PORT" \
    -o IdentitiesOnly=yes \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    "$VM_USER@$VM_HOST" "$@"
