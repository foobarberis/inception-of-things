iso="debian-mother.qcow2"
if [ ! -f $iso ]; then
  wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2 -O debian-mother.qcow2
  qemu-img resize debian-mother.qcow2 20G
  xorriso -as genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data
fi

qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -m 8192 \
  -smp 4 \
  -drive file=debian-mother.qcow2,if=virtio \
  -cdrom seed.iso \
  -netdev user,id=net0,net=192.168.57.0/24,hostfwd=tcp::2222-:22,hostfwd=tcp::8888-:8888,hostfwd=tcp::8080-:8080,hostfwd=tcp::8443-:443 \
  -device virtio-net-pci,netdev=net0 \
  -virtfs local,path=.,mount_tag=shared,security_model=mapped \
  -pidfile /tmp/qemu-mbernard.pid \
  -monitor telnet:127.0.0.1:4444,server,nowait \
  -nographic
