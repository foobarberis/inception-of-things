#!/usr/bin/env bash
set -euo pipefail

# Pin the reusable Debian base image; never modify it after download.
# The writable disk and generated cloud-init state live outside the repository.
IMAGE_RELEASE="20260810-2566"
IMAGE_NAME="debian-13-generic-amd64-${IMAGE_RELEASE}.qcow2"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/${IMAGE_RELEASE}/${IMAGE_NAME}"
VM_MEMORY_MB=8192
VM_CPUS=4

# Resolve paths from this file so the launch directory cannot affect the VM.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GOINFRE_DIR="$HOME/goinfre"
VM_DIR="$GOINFRE_DIR/iot-vm"
BASE_IMAGE="$GOINFRE_DIR/$IMAGE_NAME"
VM_DISK="$VM_DIR/disk.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
SSH_PUBLIC_KEY="${SSH_KEY:-}"

# Fail before creating state when a host-side prerequisite is missing.
require_command() {
    local command="$1"

    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
}

for command in curl qemu-img qemu-system-x86_64 ssh xorriso; do
    require_command "$command"
done

# Nested Vagrant/libvirt needs host KVM acceleration.
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    echo "KVM is not available to the current user." >&2
    exit 1
fi

# Keep the large immutable image in goinfre, where it can be reused by resets.
mkdir -p "$GOINFRE_DIR"
if [[ ! -w "$GOINFRE_DIR" ]]; then
    echo "Cannot write to $GOINFRE_DIR." >&2
    exit 1
fi

# A new VM needs the caller's existing public key. Existing VM state already
# contains its rendered cloud-init seed and can be started without SSH_KEY.
if [[ ! -e "$VM_DIR" ]]; then
    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        echo "SSH_KEY must contain a public SSH key when creating VM state." >&2
        echo 'Example: SSH_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")" ./tools/launch-vm.sh' >&2
        exit 1
    fi
    if [[ "$SSH_PUBLIC_KEY" == *$'\n'* || "$SSH_PUBLIC_KEY" == *$'\r'* ]]; then
        echo "SSH_KEY must be a single-line public SSH key." >&2
        exit 1
    fi
fi

# Download atomically so an interrupted transfer never becomes the cached image.
if [[ ! -s "$BASE_IMAGE" ]]; then
    echo "Downloading Debian 13 base image..."
    curl -fL --show-error "$IMAGE_URL" -o "$BASE_IMAGE.part"
    mv -- "$BASE_IMAGE.part" "$BASE_IMAGE"
fi

# A missing state directory means a fresh disk and cloud-init seed.
if [[ ! -e "$VM_DIR" ]]; then
    umask 077
    mkdir -m 700 "$VM_DIR"

    # Render the caller's public key without interpreting shell or sed syntax in it.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"__SSH_PUBLIC_KEY__"* ]]; then
            printf '%s%s%s\n' "${line%%__SSH_PUBLIC_KEY__*}" "$SSH_PUBLIC_KEY" \
                "${line#*__SSH_PUBLIC_KEY__}"
        else
            printf '%s\n' "$line"
        fi
    done < "$SCRIPT_DIR/cloud-init/user-data.template" > "$VM_DIR/user-data"
    cp "$SCRIPT_DIR/cloud-init/meta-data.template" "$VM_DIR/meta-data"

    # Package the rendered cloud-init files as the NoCloud seed ISO.
    (
        cd "$VM_DIR"
        xorriso -as genisoimage -output seed.iso -volid cidata -joliet -rock \
            user-data meta-data >/dev/null 2>&1
    )

    # Make a 20 GB copy-on-write disk; the cached image remains untouched.
    qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$VM_DISK"
    qemu-img resize -q "$VM_DISK" 20G
    echo "Created VM state: $VM_DIR"
elif [[ ! -d "$VM_DIR" || ! -f "$VM_DISK" || ! -f "$SEED_ISO" || \
        ! -f "$VM_DIR/user-data" || ! -f "$VM_DIR/meta-data" ]]; then
    # Do not silently mix partial state with a new seed or key.
    echo "VM state is incomplete. Remove $VM_DIR and run this script again." >&2
    exit 1
fi

# Keep the console attached to QEMU. Clone or copy the repository into the VM after boot.
exec qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -m "$VM_MEMORY_MB" \
    -smp "$VM_CPUS" \
    -drive "file=$VM_DISK,if=virtio,format=qcow2" \
    -cdrom "$SEED_ISO" \
    -netdev user,id=net0,net=192.168.57.0/24,hostfwd=tcp::2222-:22,hostfwd=tcp::8888-:8888,hostfwd=tcp::8086-:8086,hostfwd=tcp::8080-:8080,hostfwd=tcp::8443-:443 \
    -device virtio-net-pci,netdev=net0 \
    -nographic
