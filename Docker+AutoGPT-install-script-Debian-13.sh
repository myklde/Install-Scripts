#!/bin/bash
set -e  # Exit script on errors

# =============================================================================
# AutoGPT installation script for a minimal Proxmox LXC container
# – fully revised, based on the successful installation –
# =============================================================================
# This script installs Docker, Docker Compose, and the AutoGPT platform
# from the official GitHub repository. It uses the correct combination
# of Compose files (docker-compose.yml + docker-compose.platform.yml)
# and starts the platform on port 3000.
#
# IMPORTANT – Requirements on the Proxmox host:
#   1. The LXC container MUST be created as a privileged container.
#   2. In the container configuration 'features: nesting=1' must be set.
#      (File: /etc/pve/lxc/<CTID>.conf, add line: features: nesting=1)
#   3. The container requires sufficient disk and RAM resources
#      (at least 20 GB disk, 4 GB RAM recommended).
#
# The script MUST be executed as root inside the container.
# =============================================================================

# ------------------------------
# Check if the script is running as root
# ------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Dieses Skript muss als root ausgeführt werden. Verwende 'sudo' oder wechsle zu root." >&2
   exit 1
fi

echo "=== AutoGPT-Installation gestartet: $(date) ==="

# ------------------------------
# Update system and install base packages
# ------------------------------
echo "=== Aktualisiere Paketlisten und installiere Grundpakete (curl, git, sudo, etc.) ==="
apt update
apt upgrade -y
apt install -y curl git sudo gnupg lsb-release ca-certificates

# ------------------------------
# Install Docker and Docker Compose (official method)
# ------------------------------
echo "=== Installiere Docker Engine und Docker Compose Plugin ==="
# Add Docker's official repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# For Debian/Ubuntu: source based on distribution
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker service and enable autostart
systemctl enable docker
systemctl start docker

# ------------------------------
# Check if Docker works (hello-world)
# ------------------------------
echo "=== Prüfe Docker-Funktionalität mit 'hello-world' ==="
if ! docker run --rm hello-world > /dev/null 2>&1; then
    echo "FEHLER: Docker konnte den hello-world-Container nicht ausführen." >&2
    echo "Stelle sicher, dass der Container privilegiert ist und 'features: nesting=1' gesetzt wurde." >&2
    exit 1
else
    echo "Docker funktioniert einwandfrei."
fi

# ------------------------------
# Add user to Docker group (optional)
# ------------------------------
if id -u ubuntu &>/dev/null; then
    usermod -aG docker ubuntu
    echo "Benutzer 'ubuntu' wurde zur Docker-Gruppe hinzugefügt."
elif id -u debian &>/dev/null; then
    usermod -aG docker debian
    echo "Benutzer 'debian' wurde zur Docker-Gruppe hinzugefügt."
fi

# ------------------------------
# Clone AutoGPT repository
# ------------------------------
echo "=== Klone AutoGPT Repository ==="
cd /opt
if [ -d AutoGPT ]; then
    echo "Verzeichnis /opt/AutoGPT existiert bereits. Aktualisiere..."
    cd AutoGPT
    git pull
else
    git clone https://github.com/Significant-Gravitas/AutoGPT.git
    cd AutoGPT
fi

# ------------------------------
# Checkout specific release tag (optional)
# Here: the latest stable beta release v0.6.50
# ------------------------------
RELEASE_TAG="autogpt-platform-beta-v0.6.50"
echo "=== Wechsle zu Release-Tag: $RELEASE_TAG ==="
git fetch --tags
git checkout tags/$RELEASE_TAG -b $RELEASE_TAG 2>/dev/null || git checkout $RELEASE_TAG

# ------------------------------
# Change into the platform directory
# ------------------------------
cd /opt/AutoGPT/autogpt_platform

# ------------------------------
# Create .env file (optional, but not strictly required)
# ------------------------------
if [ ! -f .env ]; then
    echo "=== Erstelle leere .env-Datei (kann später mit API-Keys befüllt werden) ==="
    touch .env
fi

# ------------------------------
# Start AutoGPT platform with Docker Compose (COMBINATION OF FILES!)
# ------------------------------
echo "=== Starte AutoGPT Platform mit 'docker-compose.yml' und 'docker-compose.platform.yml' im Hintergrund ==="
docker compose -f docker-compose.yml -f docker-compose.platform.yml up -d

# ------------------------------
# Wait until services are available
# ------------------------------
echo "=== Warte 60 Sekunden, bis alle Container gestartet sind... ==="
sleep 60

# ------------------------------
# Show status and access information
# ------------------------------
echo "=== Docker-Container Status ==="
docker compose -f docker-compose.yml -f docker-compose.platform.yml ps

# Determine container IP address
CONTAINER_IP=$(hostname -I | awk '{print $1}')
echo "========================================================="
echo "AutoGPT-Plattform wurde erfolgreich gestartet!"
echo "Du kannst nun auf das Frontend zugreifen unter:"
echo "  http://$CONTAINER_IP:3000"
echo ""
echo "Wichtige nächste Schritte:"
echo "  1. Falls benötigt, trage API-Keys (z.B. OPENAI_API_KEY) in die .env-Datei ein:"
echo "     /opt/AutoGPT/autogpt_platform/.env"
echo "  2. Starte die Container neu, falls du die .env geändert hast:"
echo "     cd /opt/AutoGPT/autogpt_platform && docker compose -f docker-compose.yml -f docker-compose.platform.yml restart"
echo "  3. Weitere Konfiguration entnimmst du bitte der offiziellen Dokumentation:"
echo "     https://github.com/Significant-Gravitas/AutoGPT"
echo "========================================================="

# ------------------------------
# Optional: Show logs if errors occur
# ------------------------------
if ! docker compose -f docker-compose.yml -f docker-compose.platform.yml ps | grep -q "Up"; then
    echo "WARNUNG: Nicht alle Container sind 'Up'. Hier die letzten Logs:"
    docker compose -f docker-compose.yml -f docker-compose.platform.yml logs --tail=50
fi

echo "=== Installation abgeschlossen: $(date) ==="
