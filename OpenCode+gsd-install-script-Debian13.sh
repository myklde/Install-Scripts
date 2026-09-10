#!/bin/bash

# ============================================================
# OpenCode + GSD Installer / Updater
# Debian 13
#
# Erstinstallation:
#   apt update && apt install -y curl && curl -fsSL https://raw.githubusercontent.com/myklde/Install-Scripts/main/OpenCode-install-script-Debian-13.sh | bash
#
# Update:
#   ./install.sh update
#
# Prüfung:
#   ./install.sh verify
#
# ============================================================

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

INSTALL_USER="opencode-gsd"
NODE_MAJOR_REQUIRED=22

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Helper
# ============================================================

info() {
    echo -e "${CYAN}$1${NC}"
}

success() {
    echo -e "${GREEN}$1${NC}"
}

warning() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}"
}

# ============================================================
# Root check
# ============================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Dieses Script muss als root ausgeführt werden."
        echo
        echo "Beispiel:"
        echo "  sudo ./install.sh install"
        exit 1
    fi
}

# ============================================================
# Debian 13 check
# ============================================================

check_os() {

    if [ ! -f /etc/os-release ]; then
        error "/etc/os-release nicht gefunden."
        exit 1
    fi

    source /etc/os-release

    if [ "$ID" != "debian" ]; then
        error "Dieses Script ist ausschließlich für Debian 13."
        echo "Erkannt: $PRETTY_NAME"
        exit 1
    fi

    if [ "${VERSION_ID%%.*}" != "13" ]; then
        error "Dieses Script ist ausschließlich für Debian 13."
        echo "Erkannt: $PRETTY_NAME"
        exit 1
    fi

    success "OS: $PRETTY_NAME"
}

# ============================================================
# User
# ============================================================

setup_user() {

    info "[1/7] Prüfe Benutzer..."

    if id "$INSTALL_USER" >/dev/null 2>&1; then
        success "Benutzer '$INSTALL_USER' existiert bereits."
    else
        echo "Erstelle Benutzer '$INSTALL_USER'..."

        adduser \
            --disabled-password \
            --gecos "" \
            "$INSTALL_USER"

        success "Benutzer '$INSTALL_USER' erstellt."
    fi

    USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"

    if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
        error "Home-Verzeichnis von $INSTALL_USER konnte nicht ermittelt werden."
        exit 1
    fi

    echo "Benutzer: $INSTALL_USER"
    echo "Home:     $USER_HOME"

    # Projektverzeichnis
    mkdir -p "$USER_HOME/projects"

    chown -R "$INSTALL_USER:$INSTALL_USER" "$USER_HOME/projects"
}

# ============================================================
# Dependencies
# ============================================================

install_dependencies() {

    info "[2/7] Installiere System-Abhängigkeiten..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    apt-get install -y \
        curl \
        ca-certificates \
        tar \
        unzip \
        git \
        git-lfs \
        build-essential \
        openssh-client

    git lfs install --system >/dev/null 2>&1 || true

    success "Abhängigkeiten installiert."
}

# ============================================================
# Node.js 22
# ============================================================

install_node() {

    info "[3/7] Prüfe Node.js..."

    if command -v node >/dev/null 2>&1; then

        NODE_VERSION="$(node --version)"
        NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"

        echo "Gefunden: $NODE_VERSION"

        if [ "$NODE_MAJOR" -ge "$NODE_MAJOR_REQUIRED" ]; then
            success "Node.js $NODE_VERSION ist kompatibel."
            return
        fi

        warning "Vorhandene Node.js-Version ist zu alt."
        echo "Benötigt: Node.js >= $NODE_MAJOR_REQUIRED"
    else
        warning "Node.js nicht installiert."
    fi

    echo "Installiere Node.js 22 LTS..."

    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

    apt-get install -y nodejs

    NODE_VERSION="$(node --version)"
    NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"

    if [ "$NODE_MAJOR" -lt "$NODE_MAJOR_REQUIRED" ]; then
        error "Node.js >= $NODE_MAJOR_REQUIRED konnte nicht installiert werden."
        echo "Installiert: $NODE_VERSION"
        exit 1
    fi

    success "Node.js $NODE_VERSION installiert."
    echo "npm: $(npm --version)"
}

# ============================================================
# OpenCode
# ============================================================

install_opencode() {

    info "[4/7] Installiere / aktualisiere OpenCode..."

    USER_BIN="$USER_HOME/.local/bin"

    mkdir -p "$USER_BIN"

    chown "$INSTALL_USER:$INSTALL_USER" "$USER_BIN"

    echo "OpenCode wird für Benutzer '$INSTALL_USER' installiert."
    echo "Installationspfad: $USER_BIN"
    echo "Starte OpenCode-Installer..."
    echo "Debug-Ausgabe aktiviert (bash -x)."
    echo

    sudo -u "$INSTALL_USER" \
        HOME="$USER_HOME" \
        XDG_BIN_DIR="$USER_BIN" \
        PATH="$USER_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        bash -c '
            curl -fsSL https://opencode.ai/install | bash -x
        '

    echo

    if [ ! -x "$USER_BIN/opencode" ]; then
        error "OpenCode wurde nicht gefunden:"
        echo "$USER_BIN/opencode"
        exit 1
    fi

    chmod +x "$USER_BIN/opencode"

    chown "$INSTALL_USER:$INSTALL_USER" "$USER_BIN/opencode"

    success "OpenCode installiert/aktualisiert."
}

# ============================================================
# PATH
# ============================================================

configure_path() {

    info "[5/7] Konfiguriere PATH..."

    BASHRC="$USER_HOME/.bashrc"

    PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

    if [ ! -f "$BASHRC" ]; then
        touch "$BASHRC"
        chown "$INSTALL_USER:$INSTALL_USER" "$BASHRC"
    fi

    if ! grep -qF "$PATH_LINE" "$BASHRC"; then

        cat >> "$BASHRC" <<'EOF'

# OpenCode
export PATH="$HOME/.local/bin:$PATH"
EOF

        chown "$INSTALL_USER:$INSTALL_USER" "$BASHRC"

        success "PATH in .bashrc eingetragen."
    else
        success "PATH bereits konfiguriert."
    fi
}

# ============================================================
# GSD
# ============================================================

install_gsd() {

    info "[6/7] Installiere / aktualisiere GSD..."

    GSD_CONFIG="$USER_HOME/.config/opencode"

    echo
    echo "Installiere aktuelle GSD-Version für OpenCode..."
    echo "Installationsziel: $GSD_CONFIG"
    echo "Debug-Ausgabe aktiviert."
    echo

    mkdir -p "$GSD_CONFIG"

    chown -R "$INSTALL_USER:$INSTALL_USER" \
        "$USER_HOME/.config" 2>/dev/null || true

    sudo -u "$INSTALL_USER" \
        HOME="$USER_HOME" \
        PATH="$USER_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        bash -c '
            npx --verbose --yes get-shit-done-cc@latest --opencode --global
        '

    echo

    # GSD-Installation überprüfen.
    #
    # Der Installer installiert GSD global nach:
    # ~/.config/opencode/
    #
    # Wir suchen nach typischen GSD-Dateien/Verzeichnissen,
    # statt nur zu prüfen, ob das OpenCode-Verzeichnis existiert.

    GSD_FOUND="false"

    if [ -d "$GSD_CONFIG/get-shit-done" ]; then
        GSD_FOUND="true"
    fi

    if [ -d "$GSD_CONFIG/command" ]; then
        GSD_FOUND="true"
    fi

    if [ -d "$GSD_CONFIG/commands" ]; then
        GSD_FOUND="true"
    fi

    if [ -f "$GSD_CONFIG/commands/gsd-help.md" ]; then
        GSD_FOUND="true"
    fi

    if find "$GSD_CONFIG" \
        -type f \
        \( -name "gsd-help.md" -o -name "help.md" \) \
        -print -quit 2>/dev/null | grep -q .; then
        GSD_FOUND="true"
    fi

    if [ "$GSD_FOUND" != "true" ]; then
        error "GSD wurde offenbar nicht installiert."
        echo
        echo "OpenCode-Konfiguration:"
        echo "  $GSD_CONFIG"
        echo
        echo "Inhalt:"
        find "$GSD_CONFIG" -maxdepth 3 -type f 2>/dev/null | head -100 || true
        echo
        error "GSD-Installation fehlgeschlagen."
        exit 1
    fi

    chown -R "$INSTALL_USER:$INSTALL_USER" \
        "$GSD_CONFIG"

    success "GSD installiert/aktualisiert."
}

# ============================================================
# Verify
# ============================================================

verify_installation() {

    info "[7/7] Überprüfe Installation..."

    USER_BIN="$USER_HOME/.local/bin"

    echo

    # --------------------------------------------------------
    # Node
    # --------------------------------------------------------

    echo "Node.js:"

    if sudo -u "$INSTALL_USER" \
        node --version; then

        success "Node.js OK."
    else
        error "Node.js funktioniert nicht."
    fi

    echo

    # --------------------------------------------------------
    # npm
    # --------------------------------------------------------

    echo "npm:"

    if sudo -u "$INSTALL_USER" \
        npm --version; then

        success "npm OK."
    else
        error "npm funktioniert nicht."
    fi

    echo

    # --------------------------------------------------------
    # OpenCode
    # --------------------------------------------------------

    echo "OpenCode:"

    if [ -x "$USER_BIN/opencode" ]; then

        OPENCODE_VERSION="$(
            sudo -u "$INSTALL_USER" \
            HOME="$USER_HOME" \
            PATH="$USER_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            "$USER_BIN/opencode" --version
        )"

        success "OpenCode: $OPENCODE_VERSION"

    else

        error "OpenCode Binary nicht gefunden:"
        echo "$USER_BIN/opencode"
        exit 1
    fi

    echo

    # --------------------------------------------------------
    # GSD
    # --------------------------------------------------------

    echo "GSD:"

    GSD_CONFIG="$USER_HOME/.config/opencode"

    if [ ! -d "$GSD_CONFIG" ]; then
        error "OpenCode-Konfigurationsverzeichnis nicht gefunden:"
        echo "$GSD_CONFIG"
        exit 1
    fi

    GSD_FOUND="false"

    if [ -d "$GSD_CONFIG/get-shit-done" ]; then
        GSD_FOUND="true"
    fi

    if [ -d "$GSD_CONFIG/command" ]; then
        GSD_FOUND="true"
    fi

    if [ -d "$GSD_CONFIG/commands" ]; then
        GSD_FOUND="true"
    fi

    if find "$GSD_CONFIG" \
        -type f \
        \( -name "gsd-help.md" -o -name "help.md" \) \
        -print -quit 2>/dev/null | grep -q .; then
        GSD_FOUND="true"
    fi

    if [ "$GSD_FOUND" = "true" ]; then
        success "GSD OK."
        echo "GSD-Konfiguration:"
        echo "  $GSD_CONFIG"
    else
        error "GSD konnte nicht verifiziert werden."
        echo "Erwartet unter:"
        echo "  $GSD_CONFIG"
        exit 1
    fi

    echo

    # --------------------------------------------------------
    # Projects
    # --------------------------------------------------------

    echo "Projects:"

    if [ -d "$USER_HOME/projects" ]; then
        success "Projektverzeichnis:"
        echo "$USER_HOME/projects"
    else
        warning "Projektverzeichnis fehlt."
    fi

    echo
    echo "============================================================"
    success "Installation / Update erfolgreich."
    echo "============================================================"
    echo

    echo "Benutzer:"
    echo "  $INSTALL_USER"

    echo
    echo "OpenCode:"
    echo "  su - $INSTALL_USER"
    echo "  opencode"

    echo
    echo "GSD:"
    echo "  /gsd-help"

    echo
    echo "Projekte:"
    echo "  $USER_HOME/projects"

    echo
}

# ============================================================
# INSTALL
# ============================================================

install_all() {

    echo
    info "============================================================"
    info " OpenCode + GSD Installation"
    info " Debian 13"
    info "============================================================"
    echo

    check_root
    check_os
    setup_user
    install_dependencies
    install_node
    install_opencode
    configure_path
    install_gsd
    verify_installation
}

# ============================================================
# UPDATE
# ============================================================

update_all() {

    echo
    info "============================================================"
    info " OpenCode + GSD Update"
    info "============================================================"
    echo

    check_root
    check_os

    if ! id "$INSTALL_USER" >/dev/null 2>&1; then
        error "Benutzer '$INSTALL_USER' existiert nicht."
        echo
        echo "Führe zuerst aus:"
        echo "  ./install.sh install"
        exit 1
    fi

    USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"

    install_dependencies
    install_node
    install_opencode
    install_gsd
    verify_installation
}

# ============================================================
# VERIFY
# ============================================================

verify_only() {

    echo
    info "============================================================"
    info " OpenCode + GSD Verification"
    info "============================================================"
    echo

    check_root
    check_os

    if ! id "$INSTALL_USER" >/dev/null 2>&1; then
        error "Benutzer '$INSTALL_USER' existiert nicht."
        exit 1
    fi

    USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"

    verify_installation
}

# ============================================================
# Help
# ============================================================

show_help() {

    echo
    echo "OpenCode + GSD Installer"
    echo
    echo "Verwendung:"
    echo
    echo "  ./install.sh install"
    echo "      Installiert OpenCode + GSD komplett."
    echo
    echo "  ./install.sh update"
    echo "      Aktualisiert OpenCode + GSD auf die aktuelle Version."
    echo
    echo "  ./install.sh verify"
    echo "      Überprüft die bestehende Installation."
    echo
    echo "Benutzer:"
    echo "  $INSTALL_USER"
    echo
}

# ============================================================
# Main
# ============================================================

case "${1:-install}" in

    install)
        install_all
        ;;

    update)
        update_all
        ;;

    verify)
        verify_only
        ;;

    -h|--help|help)
        show_help
        ;;

    *)
        error "Unbekannter Befehl: $1"
        show_help
        exit 1
        ;;

esac
