#!/bin/bash

apt-get update

echo "Waiting for token..."
while [ ! -f /vagrant/node-token ]; do
  sleep 2
done

echo "Installing k3s on worker."
K3S_URL=https://192.168.56.110:6443 TOKEN=$(cat /vagrant/node-token) curl -sfL https://get.k3s.io | sh -
echo "Provisionning is finished."
