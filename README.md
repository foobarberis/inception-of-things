# Inception of Things

A 42 system administration project introducing Kubernetes through K3s, K3d, Vagrant, and Argo CD.

The project covers virtual machine provisioning, application deployment and routing, and GitOps-based continuous delivery.

## Requirements

To use qemu for the VM, we need to install :

- Packets : `sudo apt install libvirt-daemon-system libvirt-dev qemu-system-kvm vagrant-libvirt`
- the plugin `vagrant-qemu` :

`vagrant plugin install vagrant-libvirt`

We need to be in the libvirt group:
`sudo usermod -aG libvirt $(whoami)`
To use qemu, we must tell vagrant to use libvirt, else it will use virtualbox.
Either manually :
`export VAGRANT_DEFAULT_PROVIDER=libvirt`
Or written directly on the Vagrantfile :
`ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'`

Only then we can do `vagrant up`.

## Initial VM

`launch-VM.sh` permits to create the initial VM, it :

- Downloads the iso if not downloaded
- Set it to 20G and RAM = 8192G
- Creates `seed.iso`:
`xorriso -as genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data`

## Vagrant

### Useful commands

- `vagrant up` : build and launch the VM
- `vagrant provision` : launchs the VM forcing to provision again
- `vagrant halt` : stop gracefully the VM
- `vagrant destroy -f` : destroy the VM
Note about `vagrant destroy -f` : we must also erase the node-token file.
Else, building it will block eternally.

## Part 1

- Image used : cloud-image/debian-13
Link : [Hashicorp cloud-image/debian-13: https://portal.cloud.hashicorp.com/vagrant/discover/cloud-image/debian-13]

## Part 2

- Commands to show ingress :

```sh
kubectl get ingress -o wide
kubectl describe ingress
```

How to test websites from the host :

- `ssh -4 -L 8888:192.168.56.110:80 -p 2222 <you-login>@localhost`
- `python ./initial-VM-setup/launch_proxy_from_host_for_p2.py`

## Testing commands

- `kubectl get nodes -o wide` : see the nodes in the server VM
- `ip addr show <interface_name>` : show the interface wanted
- `kubectl get all -n kube-system` : shows everything (nodes, podes, etc.)
- `curl -H "Host: app1.com" http://192.168.56.110` -> test app1
- `curl -H "Host: app2.com" http://192.168.56.110` -> test app2
- `curl http://192.168.56.110` -> test app3
