apt-get update

NODE_INTERFACE=$(ip -o -4 addr show to 192.168.56.110 | awk '{print $2}')
    echo "Cluster interface : $NODE_INTERFACE"

echo "Installing k3s on server."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=192.168.56.110 --flannel-iface=${NODE_INTERFACE} --write-kubeconfig-mode 644" sh -

echo "Waiting for k3s to start and generate node-token..."
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 2
done

cat /var/lib/rancher/k3s/server/node-token > /vagrant/node-token
chmod 644 /vagrant/node-token

echo "Provisionning is finished."
