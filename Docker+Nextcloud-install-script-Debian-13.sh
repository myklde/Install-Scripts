#!/usr/bin/env bash
set -euo pipefail

echo "Nextcloud Install (Debian 13 + stable)"

# Interaktiv nur wenn Terminal vorhanden
if [ -t 0 ]; then
  read -r -p "MariaDB root Passwort: " MYSQL_ROOT_PASS
  read -r -p "Nextcloud DB User: "     MYSQL_USER
  read -r -s -p "Nextcloud DB Passwort: " MYSQL_USER_PASS
  echo
else
  MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-$(openssl rand -base64 18)}"
  MYSQL_USER="${MYSQL_USER:-nextcloud}"
  MYSQL_USER_PASS="${MYSQL_USER_PASS:-$(openssl rand -base64 15)}"
  echo "Kein TTY → Defaults / Zufallspasswörter werden verwendet"
  echo "DB User: $MYSQL_USER"
  echo "DB Pass: $MYSQL_USER_PASS  (ändern Sie es danach!)"
fi

[ -z "$MYSQL_ROOT_PASS" ] && { echo "Root-Passwort fehlt"; exit 1; }
[ -z "$MYSQL_USER_PASS" ] && { echo "User-Passwort fehlt"; exit 1; }

apt update && apt upgrade -y
apt install -y curl nano ca-certificates gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

if [ -n "${SUDO_USER:-}" ]; then
  usermod -aG docker "$SUDO_USER"
fi

mkdir -p /opt/nextcloud-docker
cd /opt/nextcloud-docker

cat <<EOF > docker-compose.yml
services:
  db:
    image: mariadb:11
    container_name: nextcloud-db
    restart: always
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASS
      MYSQL_PASSWORD: $MYSQL_USER_PASS
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: $MYSQL_USER
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
      MYSQL_PASSWORD: $MYSQL_USER_PASS
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: $MYSQL_USER
      MYSQL_HOST: db

volumes:
  db:
  nextcloud:
EOF

docker compose up -d

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

echo "Fertig → http://$(hostname -I | awk '{print $1}'):8080"
echo "Update: cd /opt/nextcloud-docker && ./update-nextcloud.sh"
[ -t 0 ] || echo "Passwörter: Root-DB: $MYSQL_ROOT_PASS | User: $MYSQL_USER | Pass: $MYSQL_USER_PASS"
