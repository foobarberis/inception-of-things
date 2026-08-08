mkdir -p ~/vm-iot && cd ~/vm-iot
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 -O debian-13-base.qcow2

# overlay to protect the original image
qemu-img create -f qcow2 -F qcow2 -b debian-13-base.qcow2 debian-mbernard-server.qcow2 20G

mkdir -p seed
ssh-keygen -t ed25519 -f ~/.ssh/mbernard_iot -N "" -q

cat > seed/user-data <<EOF
#cloud-config
hostname: debian-mbernard-server
users:
  - name: mbernard
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat ~/.ssh/mbernard_iot.pub)

write_files:
  - path: /etc/network/interfaces.d/eth1
    content: |
      auto eth1
      iface eth1 inet static
        address 192.168.57.10
        netmask 255.255.255.0

runcmd:
  - systemctl restart networking || ifup eth1
  - mkdir -p /vagrant
  - mount -t 9p -o trans=virtio,version=9p2000.L shared /vagrant || echo "Mounting 9p failed"
  - chown -R mbernard:mbernard /vagrant
EOF

cat > seed/meta-data <<EOF
instance-id: debian-mbernard-server
local-hostname: debian-mbernard-server
EOF

genisoimage -output seed.iso -volid cidata -joliet -rock seed/user-data seed/meta-data

# Launching

qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -m 4096 \
  -smp 4 \
  -drive file=debian-mbernard-server.qcow2,if=virtio \
  -cdrom seed.iso \
  -netdev user,id=net0,net=192.168.57.0/24,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::8443-:443 \
  -device virtio-net-pci,netdev=net0 \
  -virtfs local,path=.,mount_tag=shared,security_model=mapped \
  -pidfile /tmp/qemu-mbernard.pid \
  -monitor telnet:127.0.0.1:4444,server,nowait \
  -nographic
