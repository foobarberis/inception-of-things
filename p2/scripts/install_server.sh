apt-get update
set -e

CONFS="/vagrant/confs"

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

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Waiting for the API server to be ready..."
until kubectl get nodes &>/dev/null; do
  sleep 2
done

echo "Waiting for Traefik (Ingress controller) to be ready..."
until kubectl -n kube-system rollout status deployment/traefik --timeout=10s &>/dev/null; do
  sleep 2
done
echo "Deploying application..."

kubectl apply -f ${CONFS}/app1/app1.yaml
kubectl apply -f ${CONFS}/app2/app2.yaml
kubectl apply -f ${CONFS}/app3/app3.yaml
kubectl apply -f ${CONFS}/ingress.yaml

# ConfigMaps
kubectl create configmap app1-template --from-file=index.html.template=${CONFS}/app1/index.html --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap app2-template --from-file=index.html.template=${CONFS}/app2/index.html --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap app3-template --from-file=index.html.template=${CONFS}/app3/index.html --dry-run=client -o yaml | kubectl apply -f -

kubectl get pods
kubectl get ingress
echo "Provisionning is finished."
