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

## Vagrant

### Useful commands

- `vagrant up` : build and launch the VM
- `vagrant halt` : stop gracefully the VM
- `vagrant destroy -f` : destroy the VM

## Part 1

- Image used : cloud-image/debian-13
Link : [Hashicorp cloud-image/debian-13: https://portal.cloud.hashicorp.com/vagrant/discover/cloud-image/debian-13]
