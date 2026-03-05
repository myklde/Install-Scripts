#!/bin/bash

apt update && apt upgrade -y

apt install -y sudo curl ca-certificates

# Dockers offiziellen GPG-Schlüssel hinzufügen
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Docker Repository hinzufügen
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update

# Docker installieren
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker starten
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || dockerd > /dev/null 2>&1 &

# Testcontainer
docker run hello-world

# User zur Docker-Gruppe hinzufügen
usermod -aG docker $USER

# Gruppe neu laden
newgrp docker
