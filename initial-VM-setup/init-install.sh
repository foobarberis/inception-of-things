#!/bin/bash

apt-get update

useradd -m -s /bin/bash -G sudo mbernard || true

mkdir -p /home/mbernard/.ssh
cat /home/vagrant/.ssh/authorized_keys > /home/mbernard/.ssh/authorized_keys
chown -R mbernard:mbernard /home/mbernard/.ssh
chmod 700 /home/mbernard/.ssh
chmod 600 /home/mbernard/.ssh/authorized_keys

chown -R mbernard:mbernard /vagrant

apt update
apt install git
apt install -y gnupg curl software-properties-common
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

apt update
apt install -y vagrant

# Install VirtualBox
wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --dearmor -o /usr/share/keyrings/oracle-virtualbox-2016.gpg
echo "deb [signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

apt update
apt install virtualbox-7.1 -y
echo "Provisionning is finished."
