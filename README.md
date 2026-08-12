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

To use qemu, we must tell vagrant to use libvirt, else it wwill use virtualbox:
`export VAGRANT_DEFAULT_PROVIDER=qemu`
Only then we can do `vagrant up`.

A warning will show in red :
"default: chown: cannot access '/vagrant': No such file or directory"
We can ignore it

## Initial VM

`launch-VM.sh` permits to create the initial VM, it :

- Downloads the iso if not downloaded
- Set it to 20G and RAM = 8192G
- Creates `seed.iso`:
`xorriso -as genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data`

## Vagrant

### Useful commands

- `vagrant up` : build and launch the VM
- `vagrant halt` : stop gracefully the VM
- `vagrant destroy -f` : destroy the VM

## Part 1

- Image used : cloud-image/debian-13
Link : [Hashicorp cloud-image/debian-13: https://portal.cloud.hashicorp.com/vagrant/discover/cloud-image/debian-13]

## Testing commands

- `kubectl get nodes -o wide` : see the nodes in the server VM
- `ip addr show <interface_name>` : show the interface wanted
- `kubectl get all -n kube-system` : shows everything (nodes, podes, etc.)
- `curl -H "Host: app1.com" http://192.168.56.110` -> test app1
- `curl -H "Host: app2.com" http://192.168.56.110` -> test app2
- `curl http://192.168.56.110` -> test app3
