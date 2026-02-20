#!/usr/bin/env bash



# install the script with this command->    apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/Docker+Nextcloud-install-script-Debian-13.sh && chmod +x install.sh && sudo ./install.sh




set -euo pipefail

echo "Nextcloud Install (Debian 13 + stable)"

# Basis-Pakete
apt update
apt install -y curl sudo ca-certificates gnupg lsb-release openssl

# ---------------------------------------------
# Einmalige Passwortabfrage mit Wiederholung bei leerer Eingabe
# ---------------------------------------------
echo
echo "Bitte geben Sie die benötigten Passwörter ein."
echo "Bei der Eingabe wird nichts angezeigt (Sicherheit)."

# Funktion: Wiederhole Eingabe bis sie nicht leer ist (für Passwörter)
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

# Funktion für sichtbare Eingaben (z.B. Benutzername)
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

# MariaDB root Passwort
MYSQL_ROOT_PASS=$(read_nonempty "MariaDB root Passwort: ")

# Nextcloud DB Passwort
MYSQL_USER_PASS=$(read_nonempty "Nextcloud DB Passwort: ")

# DB Benutzername (optional mit Default)
read -r -p "Nextcloud DB Benutzername [nextcloud]: " MYSQL_USER
MYSQL_USER="${MYSQL_USER:-nextcloud}"

# Optional: Nextcloud Admin anlegen
echo
read -r -p "Soll ein Nextcloud Admin gleich angelegt werden? (j/N): " CREATE_ADMIN
if [[ "$CREATE_ADMIN" =~ ^[jJyY] ]]; then
    NEXTCLOUD_ADMIN_USER=$(read_nonempty_prompt "Nextcloud Admin Benutzername: ")
    NEXTCLOUD_ADMIN_PASSWORD=$(read_nonempty "Nextcloud Admin Passwort: ")
fi

echo
echo "Alle Angaben wurden erfasst. Die Installation beginnt..."

# ---------------------------------------------
# Docker-Repository einrichten
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
# Nextcloud mit docker-compose aufsetzen
# ---------------------------------------------
mkdir -p /opt/nextcloud-docker
cd /opt/nextcloud-docker

# .env-Datei für Passwörter
cat <<EOF > .env
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS
MYSQL_PASSWORD=$MYSQL_USER_PASS
MYSQL_USER=$MYSQL_USER
MYSQL_DATABASE=nextcloud
NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-}
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-}
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
      NEXTCLOUD_ADMIN_USER: \${NEXTCLOUD_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: \${NEXTCLOUD_ADMIN_PASSWORD}

volumes:
  db:
  nextcloud:
EOF

docker compose up -d

# ---------------------------------------------
# Update-Skript erstellen
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
