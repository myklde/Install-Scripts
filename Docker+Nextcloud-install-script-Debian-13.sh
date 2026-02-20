#!/usr/bin/env bash

# INSTALL THE SCRIPT WITH THIS COMMAND: 
# ->     apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/Docker+Nextcloud-install-script-Debian-13.sh && chmod +x install.sh && ./install.sh

set -euo pipefail

echo "Nextcloud Install (Debian 13 + stable)"

# Basis-Pakete
apt update
apt install -y curl sudo ca-certificates gnupg lsb-release openssl

# ---------------------------------------------
# One-time password query with repetition when input is empty
# ---------------------------------------------
echo
echo "Bitte geben Sie die benötigten Passwörter ein."
echo "Bei der Eingabe wird nichts angezeigt (Sicherheit)."

# Function: Repeat input until it is not empty (for passwords)
read_nonempty() {
    local prompt="$1"
    local input
    while true; do
        read -r -s -p "$prompt" input
        echo
        if [ -n "$input" ]; then
            echo "$input"
            return
        else
            echo "Eingabe darf nicht leer sein. Bitte erneut versuchen."
        fi
    done
}

# Function for visible input (e.g. username)
read_nonempty_prompt() {
    local prompt="$1"
    local input
    while true; do
        read -r -p "$prompt" input
        if [ -n "$input" ]; then
            echo "$input"
            return
        else
            echo "Eingabe darf nicht leer sein. Bitte erneut versuchen."
        fi
    done
}

# MariaDB root Password
MYSQL_ROOT_PASS=$(read_nonempty "MariaDB root Password: ")

# Nextcloud DB Password
MYSQL_USER_PASS=$(read_nonempty "Nextcloud DB Password: ")

# DB Username (optional with default)
read -r -p "Nextcloud DB Username [nextcloud]: " MYSQL_USER
MYSQL_USER="${MYSQL_USER:-nextcloud}"

echo "Alle Angaben wurden erfasst. Die Installation beginnt..."

# ---------------------------------------------
# Set up Docker repository
# ---------------------------------------------
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

[ -n "${SUDO_USER:-}" ] && usermod -aG docker "$SUDO_USER"

# ---------------------------------------------
# Set up Nextcloud with docker-compose
# ---------------------------------------------
mkdir -p /opt/nextcloud-docker
cd /opt/nextcloud-docker

# .env file for passwords - OHNE Admin Variablen
cat <<EOF > .env
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS
MYSQL_PASSWORD=$MYSQL_USER_PASS
MYSQL_USER=$MYSQL_USER
MYSQL_DATABASE=nextcloud
EOF

cat <<EOF > docker-compose.yml
services:
  db:
    image: mariadb:11
    container_name: nextcloud-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    environment:
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
    volumes:
      - db:/var/lib/mysql

  app:
    image: nextcloud:stable
    container_name: nextcloud-app
    restart: always
    ports:
      - 8080:80
    depends_on:
      - db
    volumes:
      - nextcloud:/var/www/html
    environment:
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_HOST: db
      # Admin Variablen wurden entfernt - Erstanmeldung erfolgt über die Web-Oberfläche

volumes:
  db:
  nextcloud:
EOF

docker compose up -d

# ---------------------------------------------
# Create update script
# ---------------------------------------------
cat <<'EOF' > update-nextcloud.sh
#!/usr/bin/env bash
set -euo pipefail
cd /opt/nextcloud-docker
docker compose pull
docker compose up -d
docker exec -u www-data -it nextcloud-app php occ maintenance:mode --on || true
docker exec -u www-data -it nextcloud-app php occ upgrade || true
docker exec -u www-data -it nextcloud-app php occ maintenance:mode --off
echo "Update abgeschlossen"
EOF
chmod +x update-nextcloud.sh

echo
echo "Fertig → http://$(hostname -I | awk '{print $1}'):8080"
echo "Update: cd /opt/nextcloud-docker && ./update-nextcloud.sh"
echo
echo "WICHTIG: Beim ersten Aufruf der Nextcloud-Instanz werden Sie aufgefordert,"
echo "         einen Admin-Benutzer und ein Passwort über die Weboberfläche anzulegen."
