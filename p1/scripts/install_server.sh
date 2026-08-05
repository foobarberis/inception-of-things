#!/bin/bash
apt-get update

echo "Installing k3s on server."
curl -sfL https://get.k3s.io | sh -
cat /var/lib/rancher/k3s/server/node-token > /vagrant/node-token
chmod 644 /vagrant/node-token

echo "Installing Kubectl on server."
curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv kubectl /usr/local/bin/
# Avoids needing to be sudo
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube

echo "Provisionning is finished."
