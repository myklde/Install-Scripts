

#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ----------------------------------------------------------------------
# Prüfen, ob das Skript mit root-Rechten läuft; falls nicht, mit sudo neu starten
# ----------------------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}This script requires root privileges for installing system packages.${NC}"
        if command -v sudo >/dev/null 2>&1; then
            echo -e "${YELLOW}Restarting with sudo...${NC}"
            exec sudo -E "$0" "$@"
        else
            echo -e "${RED}sudo is not available. Please run this script as root.${NC}"
            exit 1
        fi
    fi
}

# ----------------------------------------------------------------------
# Betriebssystem erkennen
# ----------------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${RED}Cannot detect OS.${NC}"
        exit 1
    fi
}

# ----------------------------------------------------------------------
# Abhängigkeiten installieren
# ----------------------------------------------------------------------
install_dependencies() {
    echo -e "${YELLOW}[1/5] Installing dependencies...${NC}"
    detect_os

    export DEBIAN_FRONTEND=noninteractive

    case "$OS" in
        ubuntu|debian)
            # Universe-Repo für Ubuntu aktivieren (für git-lfs)
            apt update -qq
            apt install -y --no-install-recommends software-properties-common
            if [[ "$OS" == "ubuntu" ]]; then
                add-apt-repository -y universe
            fi
            apt update -qq
            apt install -y --no-install-recommends \
                curl tar unzip git build-essential git-lfs ca-certificates
            ;;
        rhel|centos|fedora)
            yum install -y -q curl tar unzip git gcc gcc-c++ make
            ;;
        arch)
            pacman -Sy --noconfirm curl tar unzip git base-devel
            ;;
        alpine)
            apk add --no-cache curl tar unzip git build-base
            ;;
        *)
            echo -e "${RED}Unsupported distribution: $OS${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}Dependencies installed${NC}\n"
}

# ----------------------------------------------------------------------
# Voraussetzungen prüfen
# ----------------------------------------------------------------------
check_requirements() {
    echo -e "${YELLOW}[2/5] Checking requirements...${NC}"

    local missing=()
    for cmd in curl tar unzip git; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing commands: ${missing[*]}${NC}"
        exit 1
    fi

    echo -e "${GREEN}All requirements satisfied${NC}\n"
}

# ----------------------------------------------------------------------
# OpenCode installieren
# ----------------------------------------------------------------------
install_opencode() {
    echo -e "${YELLOW}[3/5] Installing OpenCode...${NC}"

    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    mkdir -p "$INSTALL_DIR"

    if [ -n "${OPENCODE_BINARY:-}" ]; then
        echo -e "${YELLOW}Installing from local binary: $OPENCODE_BINARY${NC}"
        cp "$OPENCODE_BINARY" "$INSTALL_DIR/opencode"
    else
        TMP_SCRIPT=$(mktemp)
        echo -e "${YELLOW}Downloading OpenCode install script...${NC}"
        if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP_SCRIPT" https://opencode.ai/install; then
            echo -e "${RED}Failed to download install script${NC}"
            rm -f "$TMP_SCRIPT"
            exit 1
        fi
        bash "$TMP_SCRIPT"
        rm -f "$TMP_SCRIPT"
    fi

    chmod +x "$INSTALL_DIR/opencode"
    echo -e "${GREEN}OpenCode installed in $INSTALL_DIR${NC}\n"
}

# ----------------------------------------------------------------------
# PATH konfigurieren
# ----------------------------------------------------------------------
configure_path() {
    echo -e "${YELLOW}[4/5] Configuring PATH...${NC}"

    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    SHELL_NAME=$(basename "$SHELL")

    case "$SHELL_NAME" in
        bash)
            PROFILE="$HOME/.bashrc"
            ;;
        zsh)
            PROFILE="${ZDOTDIR:-$HOME}/.zshrc"
            ;;
        fish)
            PROFILE="$HOME/.config/fish/config.fish"
            ;;
        *)
            PROFILE="$HOME/.profile"
            ;;
    esac

    PATH_LINE="export PATH=\"$INSTALL_DIR:\$PATH\""

    if [ -f "$PROFILE" ]; then
        if ! grep -qF "$INSTALL_DIR" "$PROFILE" 2>/dev/null; then
            echo "" >> "$PROFILE"
            echo "# OpenCode" >> "$PROFILE"
            echo "$PATH_LINE" >> "$PROFILE"
            echo -e "${GREEN}PATH configured in $PROFILE${NC}"
        else
            echo -e "${GREEN}PATH already configured${NC}"
        fi
    else
        echo -e "${YELLOW}No profile file found. Please add manually:${NC}"
        echo "  $PATH_LINE"
    fi

    export PATH="$INSTALL_DIR:$PATH"
    echo -e "${GREEN}PATH set for this session${NC}\n"
}

# Node.js installieren (falls nicht vorhanden)
sudo apt update
sudo apt install nodejs npm -y

# Version prüfen
node --version
npm --version

npx get-shit-done-cc@latest

# ----------------------------------------------------------------------
# Installation verifizieren
# ----------------------------------------------------------------------
verify_installation() {
    echo -e "${YELLOW}[5/5] Verifying installation...${NC}"

    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"

    if [ -x "$INSTALL_DIR/opencode" ]; then
        echo -e "${GREEN}OpenCode binary found${NC}"

        # Prüfe auf fehlende Shared Libraries
        MISSING_LIBS=$(ldd "$INSTALL_DIR/opencode" 2>/dev/null | grep "not found" || true)
        if [ -n "$MISSING_LIBS" ]; then
            echo -e "${YELLOW}Warning: Missing system libraries:${NC}"
            echo "$MISSING_LIBS"
        fi

        if "$INSTALL_DIR/opencode" --version >/dev/null 2>&1; then
            VERSION=$("$INSTALL_DIR/opencode" --version)
            echo -e "${GREEN}OpenCode version: $VERSION${NC}"
        else
            echo -e "${YELLOW}OpenCode cannot be executed (missing system dependencies)${NC}"
        fi
    else
        echo -e "${RED}OpenCode binary not found or not executable${NC}"
        exit 1
    fi

    echo -e "\n${GREEN}=== Installation completed! ===${NC}\n"
    echo "____________________________________________________________________________"
    echo ""
    echo "     reboot one time and start OpenCode in the terminal with:   opencode    "
    echo ""
    echo "____________________________________________________________________________"
}

# ----------------------------------------------------------------------
# Hauptfunktion
# ----------------------------------------------------------------------
main() {
    check_root "$@"
    install_dependencies
    check_requirements
    install_opencode
    configure_path
    verify_installation
}

main "$@"
