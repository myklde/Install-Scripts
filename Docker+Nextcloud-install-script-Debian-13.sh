#!/usr/bin/env bash






# INSTALL THE SCRIPT WITH THIS COMMAND: 
# ->     apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/Docker+Nextcloud-install-script-Debian-13.sh && chmod +x install.sh && ./install.sh






set -euo pipefail

echo "Nextcloud Install (Debian 13 + stable)"

# Basis-Pakete
apt update
apt install -y curl sudo ca-certificates gnupg lsb-release openssl

# ---------------------------------------------
# Generiere sichere Zufallspasswörter für die Datenbank
# ---------------------------------------------
MYSQL_ROOT_PASS=$(openssl rand -base64 24)   # 32 Zeichen, sicher
MYSQL_USER_PASS=$(openssl rand -base64 24)
MYSQL_USER="nextcloud"                         # Fester, sinnvoller Benutzername
MYSQL_DATABASE="nextcloud"

echo "Zugangsdaten für die Datenbank wurden generiert."

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

# .env file mit den generierten Passwörtern (ohne Admin-Variablen)
cat <<EOF > .env
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS
MYSQL_PASSWORD=$MYSQL_USER_PASS
MYSQL_USER=$MYSQL_USER
MYSQL_DATABASE=$MYSQL_DATABASE
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
      # Admin-Account wird später über die Weboberfläche angelegt

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

# ---------------------------------------------
# Credentials-Datei für den Benutzer erstellen
# ---------------------------------------------
# Ermittle das Home-Verzeichnis des aufrufenden Benutzers (auch bei sudo)
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

CRED_FILE="$USER_HOME/nextcloud-credentials.txt"
cat > "$CRED_FILE" <<EOF
=====================================================
Nextcloud Installation – Zugangsdaten
=====================================================

Die Nextcloud-Instanz ist unter folgender Adresse erreichbar:
  URL: http://$(hostname -I | awk '{print $1}'):8080

Für die Ersteinrichtung im Browser benötigen Sie folgende
Datenbank-Zugangsdaten (bitte genau so eingeben):

  Datenbank-Host:     db
  Datenbank-Name:     $MYSQL_DATABASE
  Datenbank-Benutzer: $MYSQL_USER
  Datenbank-Passwort: $MYSQL_USER_PASS

Das MariaDB-Root-Passwort (nur für Notfälle):
  Root-Passwort:      $MYSQL_ROOT_PASS

Die Datenbank-Zugangsdaten sind auch in der Datei
/opt/nextcloud-docker/.env gespeichert.

Wichtiger Hinweis:
- Beim ersten Aufruf im Browser müssen Sie einen Administrator-Account
  für Nextcloud anlegen (frei wählbare Zugangsdaten).
- Danach werden Sie nach den oben genannten Datenbank-Zugangsdaten gefragt.
- Bewahren Sie diese Zugangsdaten sicher auf – sie werden nicht noch einmal
  angezeigt.

Update-Skript: cd /opt/nextcloud-docker && ./update-nextcloud.sh
=====================================================
EOF

chmod 600 "$CRED_FILE"

# ---------------------------------------------
# Ausgabe auf der Konsole
# ---------------------------------------------
echo
echo "====================================================="
echo "Nextcloud wurde erfolgreich installiert!"
echo "====================================================="
echo
echo "Zugang zur Nextcloud-Instanz:"
echo "  URL: http://$(hostname -I | awk '{print $1}'):8080"
echo
echo "Datenbank-Zugangsdaten (bitte für den ersten Aufruf notieren):"
echo "  Host: db"
echo "  Datenbank: $MYSQL_DATABASE"
echo "  Benutzer: $MYSQL_USER"
echo "  Passwort: $MYSQL_USER_PASS"
echo "  MariaDB root Passwort: $MYSQL_ROOT_PASS (nur für Notfälle)"
echo
echo "Die Zugangsdaten wurden zusätzlich gespeichert in:"
echo "  $CRED_FILE"
echo
echo "WICHTIG: Beim ersten Aufruf im Browser müssen Sie"
echo "  - einen Administrator-Account für Nextcloud anlegen"
echo "  - die oben genannten Datenbank-Zugangsdaten eingeben"
echo
echo "Update-Skript: cd /opt/nextcloud-docker && ./update-nextcloud.sh"
echo "====================================================="
