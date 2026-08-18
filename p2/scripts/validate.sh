#!/bin/bash

vagrant status
vagrant ssh mbernardS -c 'hostname; ip -o -4 addr show to 192.168.56.110'
vagrant ssh mbernardS -c 'kubectl get nodes -o wide'
vagrant ssh mbernardS -c 'kubectl get all'
vagrant ssh mbernardS -c 'kubectl get deployment app1 app2 app3; kubectl get pods -o wide'
vagrant ssh mbernardS -c 'kubectl get ingress -o wide; kubectl describe ingress apps-ingress'

curl -fsS -H 'Host: app1.com' http://192.168.56.110/ | grep -F 'Hello from app1.'
curl -fsS -H 'Host: app2.com' http://192.168.56.110/ | grep -F 'Hello from app2.'
curl -fsS http://192.168.56.110/ | grep -F 'Hello from app3.'
