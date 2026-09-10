#!/usr/bin/env bash

apt update && apt upgrade -y
apt install sudo
apt install curl

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Debian 13 - OpenCode + GSD Installer
# ============================================================

TARGET_USER="${SUDO_USER:-${USER}}"

# Wenn das Script als root gestartet wird, muss ein Zielbenutzer
# angegeben werden:
if [[ "$EUID" -eq 0 ]]; then
    if [[ -z "${INSTALL_USER:-}" ]]; then
        echo -e "${YELLOW}Das Script läuft als root.${NC}"
        echo
        read -rp "Welcher Benutzer soll OpenCode + GSD bekommen? [mika]: " INSTALL_USER
        INSTALL_USER="${INSTALL_USER:-mika}"
    fi

    TARGET_USER="$INSTALL_USER"
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo -e "${RED}Benutzer '$TARGET_USER' existiert nicht.${NC}"
    echo "Erstelle den Benutzer zuerst mit:"
    echo "  adduser $TARGET_USER"
    exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo -e "${RED}Home-Verzeichnis von $TARGET_USER konnte nicht ermittelt werden.${NC}"
    exit 1
fi

echo
echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN} OpenCode + GSD Installer${NC}"
echo -e "${CYAN} Debian 13${NC}"
echo -e "${CYAN}==============================================${NC}"
echo
echo "Installationsbenutzer: $TARGET_USER"
echo "Home:                  $TARGET_HOME"
echo

# ============================================================
# Root prüfen
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${YELLOW}Für die Systempakete werden Root-Rechte benötigt.${NC}"

    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E INSTALL_USER="$TARGET_USER" "$0" "$@"
    else
        echo -e "${RED}sudo ist nicht installiert.${NC}"
        echo "Bitte als root ausführen:"
        echo "  INSTALL_USER=$TARGET_USER $0"
        exit 1
    fi
fi

# ============================================================
# OS prüfen
# ============================================================

if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}/etc/os-release nicht gefunden.${NC}"
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "debian" ]]; then
    echo -e "${RED}Dieses Script ist für Debian gedacht.${NC}"
    echo "Erkannt: $PRETTY_NAME"
    exit 1
fi

if [[ "${VERSION_ID%%.*}" != "13" ]]; then
    echo -e "${YELLOW}Warnung: Erwartet wurde Debian 13.${NC}"
    echo "Erkannt: $PRETTY_NAME"
    echo
    read -rp "Trotzdem fortfahren? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}OS: $PRETTY_NAME${NC}"

# ============================================================
# System aktualisieren
# ============================================================

echo
echo -e "${YELLOW}[1/6] Aktualisiere System...${NC}"

export DEBIAN_FRONTEND=noninteractive

apt update
apt full-upgrade -y

# ============================================================
# Abhängigkeiten
# ============================================================

echo
echo -e "${YELLOW}[2/6] Installiere Abhängigkeiten...${NC}"

apt install -y \
    curl \
    ca-certificates \
    git \
    git-lfs \
    unzip \
    tar \
    build-essential \
    openssh-client

git lfs install --system || true

# ============================================================
# Node.js 22 LTS
# ============================================================

echo
echo -e "${YELLOW}[3/6] Installiere Node.js 22 LTS...${NC}"

# Vorhandene NodeSource-Konfiguration entfernen ist absichtlich
# nicht nötig. Das Script kann erneut ausgeführt werden.

curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

apt install -y nodejs

echo
echo "Node.js:"
node --version

echo "npm:"
npm --version

# Node >= 22 prüfen
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"

if [[ "$NODE_MAJOR" -lt 22 ]]; then
    echo -e "${RED}Node.js >= 22 wird benötigt.${NC}"
    echo "Installierte Version: $(node --version)"
    exit 1
fi

# ============================================================
# OpenCode
# ============================================================

echo
echo -e "${YELLOW}[4/6] Installiere OpenCode...${NC}"

USER_BIN="$TARGET_HOME/.local/bin"

install -d -o "$TARGET_USER" -g "$TARGET_USER" "$USER_BIN"

echo "Installationspfad:"
echo "  $USER_BIN"

sudo -u "$TARGET_USER" \
    HOME="$TARGET_HOME" \
    XDG_BIN_DIR="$USER_BIN" \
    bash -c 'curl -fsSL https://opencode.ai/install | bash'

# ============================================================
# PATH
# ============================================================

echo
echo -e "${YELLOW}[5/6] Konfiguriere PATH...${NC}"

BASHRC="$TARGET_HOME/.bashrc"

PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

if ! grep -qF '$HOME/.local/bin' "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<'EOF'

# OpenCode
export PATH="$HOME/.local/bin:$PATH"
EOF
fi

chown "$TARGET_USER:$TARGET_USER" "$BASHRC"

# ============================================================
# OpenCode prüfen
# ============================================================

echo
echo -e "${CYAN}Prüfe OpenCode...${NC}"

if sudo -u "$TARGET_USER" \
    HOME="$TARGET_HOME" \
    PATH="$USER_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$USER_BIN/opencode" --version; then

    echo -e "${GREEN}OpenCode funktioniert.${NC}"
else
    echo -e "${RED}OpenCode konnte nicht gestartet werden.${NC}"
    exit 1
fi

# ============================================================
# GSD
# ============================================================

echo
echo -e "${YELLOW}[6/6] Installiere GSD für OpenCode...${NC}"

sudo -u "$TARGET_USER" \
    HOME="$TARGET_HOME" \
    PATH="$USER_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    bash -c 'npx get-shit-done-cc@latest --opencode --global'

# ============================================================
# Rechte korrigieren
# ============================================================

chown -R "$TARGET_USER:$TARGET_USER" \
    "$TARGET_HOME/.config" \
    "$TARGET_HOME/.local" \
    2>/dev/null || true

# ============================================================
# Abschluss
# ============================================================

echo
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN} Installation abgeschlossen!${NC}"
echo -e "${GREEN}==============================================${NC}"
echo

echo "Benutzer:"
echo "  $TARGET_USER"

echo
echo "OpenCode:"
echo "  opencode"

echo
echo "GSD:"
echo "  /gsd-help"

echo
echo "Konfiguration:"
echo "  $TARGET_HOME/.config/opencode/"

echo
echo -e "${YELLOW}Wichtig:${NC}"
echo "Öffne eine neue SSH-Sitzung oder führe aus:"
echo
echo "  source ~/.bashrc"
echo
echo "Danach:"
echo
echo "  opencode"
echo
echo "und in OpenCode:"
echo
echo "  /gsd-help"
echo
