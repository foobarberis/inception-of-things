#!/bin/bash

apt-get update

echo "Waiting for token..."
while [ ! -f /vagrant/node-token ]; do
  sleep 2
done

echo "Installing k3s on worker."
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.56.110:6443 K3S_TOKEN=$(cat /vagrant/node-token) INSTALL_K3S_EXEC="--node-ip=192.168.56.111 --flannel-iface=eth1" sh -
echo "Provisionning is finished."
