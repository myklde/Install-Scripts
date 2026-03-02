#!/bin/bash





# INSTALL THE SCRIPT WITH THIS COMMAND: 
# ->     apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/Docker+MySpeed-install-script-Debian-13.sh && chmod +x install.sh && ./install.sh





#!/bin/bash
set -e

# ===== Colors =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== Configuration =====
CONTAINER_NAME="myspeed"
IMAGE="germannewsmaker/myspeed"
HOST_PORT=5216
CONTAINER_PORT=5216
VOLUME_NAME="myspeed-data"
# =========================

echo -e "${GREEN}=== MySpeed Docker-Installation gestartet ===${NC}"

# 1. System update
echo -e "${YELLOW}=== System aktualisieren ===${NC}"
apt update && apt upgrade -y

# 2. Install Docker (if not present)
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}=== Docker wird installiert... ===${NC}"
    apt install -y docker.io
    systemctl start docker
    systemctl enable docker
    echo -e "${GREEN}Docker erfolgreich installiert.${NC}"
else
    echo -e "${GREEN}Docker ist bereits installiert.${NC}"
fi

# 3. Start Docker if necessary
if ! systemctl is-active --quiet docker; then
    echo -e "${YELLOW}Docker wird gestartet...${NC}"
    systemctl start docker
fi

# 4. Remove old container (if exists)
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}Alter Container '${CONTAINER_NAME}' wird entfernt...${NC}"
    docker rm -f ${CONTAINER_NAME} > /dev/null
fi

# 5. Start new container
echo -e "${YELLOW}=== MySpeed Container wird gestartet... ===${NC}"
docker run -d \
    --name ${CONTAINER_NAME} \
    --restart unless-stopped \
    -p ${HOST_PORT}:${CONTAINER_PORT} \
    -v ${VOLUME_NAME}:/myspeed/data \
    ${IMAGE}

# 6. Short wait for initialization
echo -e "${YELLOW}Warte 5 Sekunden...${NC}"
sleep 5

# 7. Success message (without admin data)
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MySpeed wurde erfolgreich gestartet!${NC}"
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "Port:         ${HOST_PORT}"
echo -e "Du kannst MySpeed jetzt im Browser aufrufen:"
echo -e "  ${YELLOW}http://<IP-DES-CONTAINERS>:${HOST_PORT}${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Hinweis:${NC} Alle Daten werden im Docker-Volume '${VOLUME_NAME}' gespeichert."
echo -e "Container verwalten mit: docker stop/start ${CONTAINER_NAME}"
echo -e "Logs ansehen: docker logs ${CONTAINER_NAME}"
