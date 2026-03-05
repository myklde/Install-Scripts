#!/bin/bash
set -e  # Skript bei Fehlern abbrechen

# =============================================================================
# AutoGPT Installationsskript für einen minimalen Proxmox LXC Container
# – vollständig überarbeitet, basierend auf der erfolgreichen Installation –
# =============================================================================
# Dieses Skript installiert Docker, Docker Compose und die AutoGPT-Plattform
# aus dem offiziellen GitHub-Repository. Es verwendet die richtige Kombination
# der Compose-Dateien (docker-compose.yml + docker-compose.platform.yml)
# und startet die Platform auf Port 3000.
#
# WICHTIG – Voraussetzungen auf Proxmox-Host:
#   1. Der LXC-Container MUSS als privilegierter Container angelegt sein.
#   2. In der Containerkonfiguration muss 'features: nesting=1' gesetzt sein.
#      (Datei: /etc/pve/lxc/<CTID>.conf, Zeile einfügen: features: nesting=1)
#   3. Der Container benötigt eine ausreichende Festplatten- und RAM-Größe
#      (mind. 20 GB Platte, 4 GB RAM empfohlen).
#
# Das Skript MUSS als root im Container ausgeführt werden.
# =============================================================================

# ------------------------------
# Prüfen, ob das Skript als root läuft
# ------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "Dieses Skript muss als root ausgeführt werden. Verwende 'sudo' oder wechsle zu root." >&2
   exit 1
fi

echo "=== AutoGPT-Installation gestartet: $(date) ==="

# ------------------------------
# System aktualisieren und Basispakete installieren
# ------------------------------
echo "=== Aktualisiere Paketlisten und installiere Grundpakete (curl, git, sudo, etc.) ==="
apt update
apt upgrade -y
apt install -y curl git sudo gnupg lsb-release ca-certificates

# ------------------------------
# Docker und Docker Compose installieren (offizielle Methode)
# ------------------------------
echo "=== Installiere Docker Engine und Docker Compose Plugin ==="
# Docker's offizielles Repository hinzufügen
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Für Debian/Ubuntu: Quelle basierend auf Distribution
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker-Dienst starten und Autostart aktivieren
systemctl enable docker
systemctl start docker

# ------------------------------
# Prüfen, ob Docker funktioniert (hello-world)
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
# Benutzer zur Docker-Gruppe hinzufügen (optional)
# ------------------------------
if id -u ubuntu &>/dev/null; then
    usermod -aG docker ubuntu
    echo "Benutzer 'ubuntu' wurde zur Docker-Gruppe hinzugefügt."
elif id -u debian &>/dev/null; then
    usermod -aG docker debian
    echo "Benutzer 'debian' wurde zur Docker-Gruppe hinzugefügt."
fi

# ------------------------------
# AutoGPT Repository klonen
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
# Bestimmten Release-Tag auschecken (optional)
# Hier: der neueste stabile Beta-Release v0.6.50
# ------------------------------
RELEASE_TAG="autogpt-platform-beta-v0.6.50"
echo "=== Wechsle zu Release-Tag: $RELEASE_TAG ==="
git fetch --tags
git checkout tags/$RELEASE_TAG -b $RELEASE_TAG 2>/dev/null || git checkout $RELEASE_TAG

# ------------------------------
# In das Plattform-Verzeichnis wechseln
# ------------------------------
cd /opt/AutoGPT/autogpt_platform

# ------------------------------
# .env-Datei anlegen (falls gewünscht, aber nicht zwingend erforderlich)
# ------------------------------
if [ ! -f .env ]; then
    echo "=== Erstelle leere .env-Datei (kann später mit API-Keys befüllt werden) ==="
    touch .env
fi

# ------------------------------
# AutoGPT Platform mit Docker Compose starten (KOMBINATION DER DATEIEN!)
# ------------------------------
echo "=== Starte AutoGPT Platform mit 'docker-compose.yml' und 'docker-compose.platform.yml' im Hintergrund ==="
docker compose -f docker-compose.yml -f docker-compose.platform.yml up -d

# ------------------------------
# Warten, bis die Dienste verfügbar sind
# ------------------------------
echo "=== Warte 60 Sekunden, bis alle Container gestartet sind... ==="
sleep 60

# ------------------------------
# Zeige Status und Zugangsdaten
# ------------------------------
echo "=== Docker-Container Status ==="
docker compose -f docker-compose.yml -f docker-compose.platform.yml ps

# IP-Adresse des Containers ermitteln
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
# Optional: Logs anzeigen, falls Fehler auftreten
# ------------------------------
if ! docker compose -f docker-compose.yml -f docker-compose.platform.yml ps | grep -q "Up"; then
    echo "WARNUNG: Nicht alle Container sind 'Up'. Hier die letzten Logs:"
    docker compose -f docker-compose.yml -f docker-compose.platform.yml logs --tail=50
fi

echo "=== Installation abgeschlossen: $(date) ==="
