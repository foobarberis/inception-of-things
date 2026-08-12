#!/bin/bash
set -euo pipefail
apt-get update

useradd -m -s /bin/bash -G sudo mbernard || true

mkdir -p /home/mbernard/.ssh
cat /home/vagrant/.ssh/authorized_keys > /home/mbernard/.ssh/authorized_keys
chown -R mbernard:mbernard /home/mbernard/.ssh
chmod 700 /home/mbernard/.ssh
chmod 600 /home/mbernard/.ssh/authorized_keys
chown -R mbernard:mbernard /vagrant

apt-get update
apt-get install -y git lsb-release curl gnupgj
apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
    bridge-utils virtinst ebtables dnsmasq-base
apt-get install -y build-essential libvirt-dev ruby-dev libxslt-dev \
    libxml2-dev zlib1g-dev pkg-config
# apt-get install -y gnupg build-essential dkms "linux-headers-$(uname -r))"
# apt-get install -y gnupg software-properties-common linux-headers-amd64
# apt-get install -y gnupg build-essential dkms linux-headers-amd64
#
usermod -aG libvirt,kvm vagrant
usermod -aG libvirt,kvm mbernard

# curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
# Install VirtualBox
# wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --dearmor -o /usr/share/keyrings/oracle-virtualbox-2016.gpg
# echo "deb [signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

apt-get update
apt-get install -y vagrant
# apt-get install -y virtualbox-7.1

echo "Provisionning is finished."
