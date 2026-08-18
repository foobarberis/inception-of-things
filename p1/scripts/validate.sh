#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PART_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
SERVER="mbernardS"
WORKER="mbernardSW"
TIMEOUT_SECONDS="${P1_VALIDATE_TIMEOUT_SECONDS:-300}"

fail() {
    echo "Part 1 validation failed: $*" >&2
    exit 1
}

if ! [[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    fail "P1_VALIDATE_TIMEOUT_SECONDS must be a positive integer."
fi

cd "$PART_DIR"

check_machine_state() {
    local machine="$1"
    local status

    status="$(vagrant status "$machine")" || fail "cannot obtain $machine status"
    printf '%s\n' "$status"
    grep -Fq "running (libvirt)" <<<"$status" || fail "$machine is not running with libvirt"
}

check_guest() {
    local machine="$1"
    local hostname="$2"
    local address="$3"
    local service="$4"

    echo "Checking $machine..."
    if ! vagrant ssh "$machine" -- "
        test \"\$(hostname)\" = '$hostname'
        ip -o -4 addr show to '$address' | grep -q .
        systemctl is-active --quiet '$service'
    "; then
        fail "$machine does not have the expected hostname, IP address, or service state"
    fi

    vagrant ssh "$machine" -- "
        printf 'hostname=%s\\n' \"\$(hostname)\"
        ip -o -4 addr show to '$address'
        printf 'service=%s\\n' \"\$(systemctl is-active '$service')\"
    "
}

cluster_is_ready() {
    local nodes
    local node_count

    if ! nodes="$(vagrant ssh "$SERVER" -- "kubectl get nodes -o wide --no-headers" 2>/dev/null)"; then
        return 1
    fi

    node_count="$(awk 'NF { count++ } END { print count + 0 }' <<<"$nodes")"
    [[ "$node_count" -eq 2 ]] || return 1
    grep -Eq '^[^[:space:]]+[[:space:]]+Ready[[:space:]].*192\.168\.56\.110([[:space:]]|$)' <<<"$nodes" || return 1
    grep -Eq '^[^[:space:]]+[[:space:]]+Ready[[:space:]].*192\.168\.56\.111([[:space:]]|$)' <<<"$nodes" || return 1
}

wait_for_cluster() {
    local deadline=$((SECONDS + TIMEOUT_SECONDS))

    echo "Waiting up to ${TIMEOUT_SECONDS}s for both K3s nodes to be Ready..."
    until cluster_is_ready; do
        if (( SECONDS >= deadline )); then
            vagrant ssh "$SERVER" -- "kubectl get nodes -o wide || true" || true
            fail "K3s did not reach the expected two-node Ready state"
        fi
        sleep 5
    done
}

echo "Checking Vagrant machine state..."
check_machine_state "$SERVER"
check_machine_state "$WORKER"

# These SSH commands also verify passwordless Vagrant access to both guests.
check_guest "$SERVER" "$SERVER" "192.168.56.110" "k3s"
check_guest "$WORKER" "$WORKER" "192.168.56.111" "k3s-agent"

wait_for_cluster

echo
vagrant ssh "$SERVER" -- "kubectl get nodes -o wide"
echo
vagrant ssh "$SERVER" -- "kubectl get pods -A"
echo
printf 'Part 1 validation passed.\n'
