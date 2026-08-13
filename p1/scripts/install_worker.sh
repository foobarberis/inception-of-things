#!/bin/bash

apt-get update

echo "Waiting for token..."
while [ ! -f /vagrant/node-token ]; do
  sleep 2
done
echo "DEBUG worker reads: $(wc -c < /vagrant/node-token) bytes, sha256=$(sha256sum /vagrant/node-token)"

NODE_INTERFACE=$(ip -o -4 addr show to 192.168.56.111 | awk '{print $2}')
    echo "Cluster interface : $NODE_INTERFACE"

echo "Installing k3s on worker."
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN=$(cat /vagrant/node-token) INSTALL_K3S_EXEC="--node-ip=192.168.56.111 --flannel-iface=${NODE_INTERFACE}" sh -
echo "Provisionning is finished."
