echo ">>> Waiting for the cluster to be ready..."
until kubectl cluster-info &> /dev/null; do
  sleep 2
done
echo ">>> Cluster Ready! Deploying..."

vagrant ssh mbernardS -- -t << 'EOF'
kubectl apply -f /home/vagrant/inception-of-things/p2/scripts/vagrant/confs/app1.yaml
kubectl apply -f /home/vagrant/inception-of-things/p2/scripts/vagrant/confs/app2.yaml
kubectl apply -f /home/vagrant/inception-of-things/p2/scripts/vagrant/confs/app3.yaml
kubectl apply -f /home/vagrant/inception-of-things/p2/scripts/vagrant/confs/ingress.yaml

# ConfigMaps
kubectl create configmap app1-template --from-file=index.html.template=/home/vagrant/inception-of-things/p2/confs/app1/index.html --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap app2-template --from-file=index.html.template=/home/vagrant/inception-of-things/p2/confs/app2/index.html --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap app3-template --from-file=index.html.template=/home/vagrant/inception-of-things/p2/confs/app3/index.html --dry-run=client -o yaml | kubectl apply -f -

kubectl get pods
kubectl get ingress
curl -H "Host: app1.com" http://192.168.56.110
curl -H "Host: app2.com" http://192.168.56.110
curl http://192.168.56.110
EOF
