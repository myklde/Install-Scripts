#!/bin/bash

# RomM Installationsskript für Proxmox LXC Container
# Korrigierte Version: Port 80 -> 8080 (intern)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   RomM Installationsskript (korrigiert)${NC}"
echo -e "${GREEN}=========================================${NC}"

# Root-Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}Bitte als root ausführen (sudo).${NC}"
   exit 1
fi

# Systemaktualisierung & Abhängigkeiten
echo -e "\n${GREEN}➡️  Aktualisiere Paketliste und installiere benötigte Tools...${NC}"
apt-get update -y
apt-get install -y curl wget git openssl

# Docker installieren (falls nicht vorhanden)
if ! command -v docker &> /dev/null; then
    echo -e "\n${GREEN}➡️  Docker wird installiert...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
else
    echo -e "\n${GREEN}✅ Docker ist bereits installiert.${NC}"
fi

# Docker Compose Plugin
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "\n${GREEN}➡️  Installiere Docker Compose Plugin...${NC}"
    apt-get install -y docker-compose-plugin
else
    echo -e "\n${GREEN}✅ Docker Compose ist bereits verfügbar.${NC}"
fi

# Verzeichnisstruktur anlegen
echo -e "\n${GREEN}➡️  Lege Verzeichnisse für RomM an...${NC}"
ROMM_BASE="/opt/romm"
mkdir -p ${ROMM_BASE}/{config,assets,library}
# Leere config.yml anlegen, damit die Warnung verschwindet
touch ${ROMM_BASE}/config/config.yml
echo -e "${GREEN}✅ Verzeichnisse unter ${ROMM_BASE} wurden erstellt.${NC}"

# Zufallspasswörter generieren
echo -e "\n${GREEN}➡️  Generiere sichere Passwörter und Schlüssel...${NC}"
MYSQL_ROOT_PASS=$(openssl rand -base64 24)
MYSQL_USER_PASS=$(openssl rand -base64 24)
ROMM_SECRET_KEY=$(openssl rand -hex 32)

# docker-compose.yml erstellen (mit korrigiertem Port)
echo -e "\n${GREEN}➡️  Erstelle docker-compose.yml...${NC}"
cat > ${ROMM_BASE}/docker-compose.yml <<EOF
services:
  mariadb:
    image: mariadb:11
    container_name: mariadb-romm
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      MARIADB_DATABASE: romm
      MARIADB_USER: romm_user
      MARIADB_PASSWORD: ${MYSQL_USER_PASS}
    volumes:
      - ./database:/var/lib/mysql
    networks:
      - romm_net

  romm:
    image: rommapp/romm:latest
    container_name: romm
    restart: unless-stopped
    depends_on:
      - mariadb
    environment:
      DB_HOST: mariadb
      DB_NAME: romm
      DB_USER: romm_user
      DB_PASSWD: ${MYSQL_USER_PASS}
      ROMM_AUTH_SECRET_KEY: ${ROMM_SECRET_KEY}
      # Optional: Hier später deine API-Keys eintragen
    volumes:
      - ./library:/romm/library:rw
      - ./assets:/romm/assets:rw
      - ./config:/romm/config:rw
    ports:
      - "80:8080"      # <── KORRIGIERT
    networks:
      - romm_net

networks:
  romm_net:
EOF

echo -e "${GREEN}✅ docker-compose.yml wurde erstellt.${NC}"

# API-Keys (optional)
echo -e "\n${YELLOW}Möchtest du jetzt API-Keys für Metadaten-Anbieter eintragen? (empfohlen)${NC}"
read -p "API-Keys jetzt eintragen? (j/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    echo -e "\n${GREEN}➡️  Bitte gib deine API-Keys ein (lasse frei, um zu überspringen):${NC}"
    read -p "IGDB_CLIENT_ID: " igdb_id
    read -p "IGDB_CLIENT_SECRET: " igdb_secret
    # Hier könntest du weitere Abfragen ergänzen
    if [[ -n "$igdb_id" && -n "$igdb_secret" ]]; then
        sed -i "/ROMM_AUTH_SECRET_KEY/a \      IGDB_CLIENT_ID: ${igdb_id}\n      IGDB_CLIENT_SECRET: ${igdb_secret}" ${ROMM_BASE}/docker-compose.yml
    fi
fi

# Container starten
echo -e "\n${GREEN}➡️  Starte RomM Container...${NC}"
cd ${ROMM_BASE}
docker compose up -d

# Kurz warten
sleep 5

# Status prüfen
if docker ps | grep -q romm; then
    echo -e "${GREEN}✅ RomM läuft erfolgreich!${NC}"
else
    echo -e "${RED}❌ Fehler: Container konnte nicht gestartet werden. Bitte logs prüfen mit: docker logs romm${NC}"
    exit 1
fi

# IP ermitteln
CONTAINER_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$CONTAINER_IP" ]]; then
    CONTAINER_IP="<IP_DEINES_CONTAINERS>"
fi

# Abschluss
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}   Installation abgeschlossen!         ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "Du kannst jetzt auf RomM zugreifen unter:"
echo -e "${YELLOW}   http://${CONTAINER_IP}${NC}   (Port 80 ist Standard, also einfach die IP)"
echo -e "\nWichtige Pfade:"
echo -e "  - ROM-Bibliothek: ${ROMM_BASE}/library/"
echo -e "  - Assets: ${ROMM_BASE}/assets/"
echo -e "  - Config: ${ROMM_BASE}/config/"
echo -e "\n${YELLOW}Bitte lege deine ROMs im library/-Verzeichnis ab (z.B. /library/roms/gb/...).${NC}"
echo -e "Danach im Webinterface den Scan starten."
echo -e "\n${GREEN}Viel Spaß mit RomM! 🎮${NC}"
