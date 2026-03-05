#!/bin/bash

apt update && apt upgrade -y
apt install sudo
apt install curl

# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker (if systemd is running in the container, otherwise start dockerd manually)
sudo systemctl start docker   # if systemd is available
# Alternative: sudo service docker start
# Or: sudo dockerd > /dev/null 2>&1 &   # if systemd is not running

# Test if Docker works
sudo docker run hello-world

sudo usermod -aG docker $USER
# Log out and back in afterwards (or run newgrp docker)
newgrp docker
