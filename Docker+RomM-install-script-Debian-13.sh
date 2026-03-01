#!/bin/bash

# INSTALL THE SCRIPT WITH THIS COMMAND: 
# ->     apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/Docker+RomM-install-script-Debian-13.sh && chmod +x install.sh && ./install.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   RomM Installation Script (corrected)${NC}"
echo -e "${GREEN}=========================================${NC}"

# Root check
if [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}Please run as root (sudo).${NC}"
   exit 1
fi

# System update & dependencies
echo -e "\n${GREEN}➡️  Updating package list and installing required tools...${NC}"
apt-get update -y
apt-get install -y curl wget git openssl

# Install Docker (if not present)
if ! command -v docker &> /dev/null; then
    echo -e "\n${GREEN}➡️  Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
else
    echo -e "\n${GREEN}✅ Docker is already installed.${NC}"
fi

# Docker Compose plugin
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "\n${GREEN}➡️  Installing Docker Compose plugin...${NC}"
    apt-get install -y docker-compose-plugin
else
    echo -e "\n${GREEN}✅ Docker Compose is already available.${NC}"
fi

# Create directory structure
echo -e "\n${GREEN}➡️  Creating directories for RomM...${NC}"
ROMM_BASE="/opt/romm"
mkdir -p ${ROMM_BASE}/{config,assets,library}
# Create empty config.yml to suppress warning
touch ${ROMM_BASE}/config/config.yml
echo -e "${GREEN}✅ Directories under ${ROMM_BASE} have been created.${NC}"

# Generate random passwords
echo -e "\n${GREEN}➡️  Generating secure passwords and keys...${NC}"
MYSQL_ROOT_PASS=$(openssl rand -base64 24)
MYSQL_USER_PASS=$(openssl rand -base64 24)
ROMM_SECRET_KEY=$(openssl rand -hex 32)

# Create docker-compose.yml (with corrected port)
echo -e "\n${GREEN}➡️  Creating docker-compose.yml...${NC}"
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
      # Optional: Add your API keys here later
    volumes:
      - ./library:/romm/library:rw
      - ./assets:/romm/assets:rw
      - ./config:/romm/config:rw
    ports:
      - "80:8080"      # <── CORRECTED
    networks:
      - romm_net

networks:
  romm_net:
EOF

echo -e "${GREEN}✅ docker-compose.yml has been created.${NC}"

# API keys (optional)
echo -e "\n${YELLOW}Do you want to add API keys for metadata providers now? (recommended)${NC}"
read -p "Add API keys now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\n${GREEN}➡️  Please enter your API keys (leave empty to skip):${NC}"
    read -p "IGDB_CLIENT_ID: " igdb_id
    read -p "IGDB_CLIENT_SECRET: " igdb_secret
    # You can add more prompts here
    if [[ -n "$igdb_id" && -n "$igdb_secret" ]]; then
        sed -i "/ROMM_AUTH_SECRET_KEY/a \      IGDB_CLIENT_ID: ${igdb_id}\n      IGDB_CLIENT_SECRET: ${igdb_secret}" ${ROMM_BASE}/docker-compose.yml
    fi
fi

# Start container
echo -e "\n${GREEN}➡️  Starting RomM container...${NC}"
cd ${ROMM_BASE}
docker compose up -d

# Wait briefly
sleep 5

# Check status
if docker ps | grep -q romm; then
    echo -e "${GREEN}✅ RomM is running successfully!${NC}"
else
    echo -e "${RED}❌ Error: Container could not be started. Please check logs with: docker logs romm${NC}"
    exit 1
fi

# Get IP
CONTAINER_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$CONTAINER_IP" ]]; then
    CONTAINER_IP="<YOUR_CONTAINER_IP>"
fi

# Finish
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}   Installation complete!              ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "You can now access RomM at:"
echo -e "${YELLOW}   http://${CONTAINER_IP}${NC}   (Port 80 is default, so just use the IP)"
echo -e "\nImportant paths:"
echo -e "  - ROM library: ${ROMM_BASE}/library/"
echo -e "  - Assets: ${ROMM_BASE}/assets/"
echo -e "  - Config: ${ROMM_BASE}/config/"
echo -e "\n${YELLOW}Please place your ROMs in the library/ directory (e.g. /library/roms/gb/...).${NC}"
echo -e "Then start the scan in the web interface."
echo -e "\n${GREEN}Enjoy RomM! 🎮${NC}"
