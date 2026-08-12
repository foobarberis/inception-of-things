apt-get update

echo "Installing k3s on server."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=192.168.56.110 --flannel-iface=ens3 --write-kubeconfig-mode 644" sh -

cat /var/lib/rancher/k3s/server/node-token > /vagrant/node-token
chmod 644 /vagrant/node-token

echo "Provisionning is finished."
