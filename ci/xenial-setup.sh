#!/bin/sh

set -eux

apt-get -q update
apt-get -q install -y python3-pip

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-docker-ce
#apt-get -q install -y linux-image-extra-$(uname -r) linux-image-extra-virtual

DOCKER_DEB=docker-ce_18.06.0~ce~3-0~ubuntu_amd64.deb
curl -O https://download.docker.com/linux/ubuntu/dists/xenial/pool/stable/amd64/$DOCKER_DEB
# dpkg won't install dependencies
dpkg -i $DOCKER_DEB || apt-get install -f -y
docker info

install -o vagrant -g vagrant -d /home/vagrant/bin

# Workaround Minikube DNS problems
# https://github.com/kubernetes/minikube/issues/2027#issuecomment-338221646
cat << EOF > /etc/resolv.conf
nameserver 8.8.4.4
nameserver 8.8.8.8
EOF
sed -i -re "s/^(127.0.0.1\\s.+)/\\1 `hostname`/" /etc/hosts

add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -q
apt-get install -y -q python3.6 python3.6-gdbm python3.6-dev
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
