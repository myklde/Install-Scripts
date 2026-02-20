#!/usr/bin/env bash






# INSTALL THE SCRIPT WITH THIS COMMAND: 
# ->     apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/Docker+Nextcloud-install-script-Debian-13.sh && chmod +x install.sh && ./install.sh






set -euo pipefail

echo "Nextcloud Install (Debian 13 + stable)"

# Base packages
apt update
apt install -y curl sudo ca-certificates gnupg lsb-release openssl

# ---------------------------------------------
# Generate secure random passwords for the database
# ---------------------------------------------
MYSQL_ROOT_PASS=$(openssl rand -base64 24)   # 32 characters, secure
MYSQL_USER_PASS=$(openssl rand -base64 24)
MYSQL_USER="nextcloud"                         # Fixed, meaningful username
MYSQL_DATABASE="nextcloud"

echo "Database credentials have been generated."

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

# .env file with generated passwords (without admin variables)
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
      # Admin account will be created via web interface

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
echo "Update completed"
EOF
chmod +x update-nextcloud.sh

# ---------------------------------------------
# Create credentials file for the user
# ---------------------------------------------
# Determine the home directory of the calling user (even with sudo)
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

CRED_FILE="$USER_HOME/nextcloud-credentials.txt"
cat > "$CRED_FILE" <<EOF
=====================================================
Nextcloud Installation – Credentials
=====================================================

Your Nextcloud instance is available at:
  URL: http://$(hostname -I | awk '{print $1}'):8080

For the initial setup in your browser, you will need the following
database credentials (enter them exactly as shown):

  Database Host:     db
  Database Name:     $MYSQL_DATABASE
  Database User:     $MYSQL_USER
  Database Password: $MYSQL_USER_PASS

MariaDB root password (for emergency use only):
  Root Password:     $MYSQL_ROOT_PASS

The database credentials are also stored in:
  /opt/nextcloud-docker/.env

Important Notes:
- During the first visit in your browser, you must create an administrator
  account for Nextcloud (you can choose any username and password).
- Afterwards, you will be prompted for the database credentials listed above.
- Keep these credentials in a safe place – they will not be shown again.

Update script: cd /opt/nextcloud-docker && ./update-nextcloud.sh
=====================================================
EOF

chmod 600 "$CRED_FILE"

# ---------------------------------------------
# Console output
# ---------------------------------------------
echo
echo "====================================================="
echo "Nextcloud has been successfully installed!"
echo "====================================================="
echo
echo "Access your Nextcloud instance:"
echo "  URL: http://$(hostname -I | awk '{print $1}'):8080"
echo
echo "Database credentials (please note for first access):"
echo "  Host: db"
echo "  Database: $MYSQL_DATABASE"
echo "  User: $MYSQL_USER"
echo "  Password: $MYSQL_USER_PASS"
echo "  MariaDB root password: $MYSQL_ROOT_PASS (emergency use only)"
echo
echo "Credentials have also been saved to:"
echo "  $CRED_FILE"
echo
echo "IMPORTANT: When accessing the web interface for the first time, you must:"
echo "  - Create an administrator account for Nextcloud"
echo "  - Enter the database credentials shown above"
echo
echo "Update script: cd /opt/nextcloud-docker && ./update-nextcloud.sh"
echo "====================================================="
