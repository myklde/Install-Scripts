#!/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ----------------------------------------------------------------------
# Prüfen, ob das Skript mit root-Rechten läuft; falls nicht, mit sudo neu starten
# ----------------------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Dieses Skript benötigt Root-Rechte für Systempakete.${NC}"
        if command -v sudo >/dev/null 2>&1; then
            echo -e "${YELLOW}Starte mit sudo neu...${NC}"
            exec sudo -E "$0" "$@"
        else
            echo -e "${RED}sudo nicht verfügbar. Bitte als root ausführen.${NC}"
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
        echo -e "${RED}Kann OS nicht erkennen.${NC}"
        exit 1
    fi
}

# ----------------------------------------------------------------------
# Abhängigkeiten installieren (inkl. Node.js/npm)
# ----------------------------------------------------------------------
install_dependencies() {
    echo -e "${YELLOW}[1/6] Installiere Abhängigkeiten...${NC}"
    detect_os
    export DEBIAN_FRONTEND=noninteractive

    case "$OS" in
        ubuntu|debian)
            apt update -qq
            apt install -y --no-install-recommends software-properties-common
            if [[ "$OS" == "ubuntu" ]]; then
                add-apt-repository -y universe
            fi
            apt update -qq
            apt install -y --no-install-recommends \
                curl tar unzip git build-essential git-lfs ca-certificates \
                nodejs npm   # <-- Node.js und npm werden hier installiert
            ;;
        rhel|centos|fedora)
            yum install -y -q curl tar unzip git gcc gcc-c++ make nodejs npm
            ;;
        arch)
            pacman -Sy --noconfirm curl tar unzip git base-devel nodejs npm
            ;;
        alpine)
            apk add --no-cache curl tar unzip git build-base nodejs npm
            ;;
        *)
            echo -e "${RED}Nicht unterstützte Distribution: $OS${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}Abhängigkeiten installiert.${NC}\n"
}

# ----------------------------------------------------------------------
# Voraussetzungen prüfen (curl, tar, unzip, git)
# ----------------------------------------------------------------------
check_requirements() {
    echo -e "${YELLOW}[2/6] Prüfe Voraussetzungen...${NC}"
    local missing=()
    for cmd in curl tar unzip git; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing+=($cmd)
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Fehlende Befehle: ${missing[*]}${NC}"
        exit 1
    fi
    echo -e "${GREEN}Alle Voraussetzungen erfüllt.${NC}\n"
}

# ----------------------------------------------------------------------
# OpenCode installieren
# ----------------------------------------------------------------------
install_opencode() {
    echo -e "${YELLOW}[3/6] Installiere OpenCode...${NC}"
    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    mkdir -p "$INSTALL_DIR"

    if [ -n "${OPENCODE_BINARY:-}" ]; then
        echo -e "${YELLOW}Installiere von lokaler Binärdatei: $OPENCODE_BINARY${NC}"
        cp "$OPENCODE_BINARY" "$INSTALL_DIR/opencode"
    else
        TMP_SCRIPT=$(mktemp)
        echo -e "${YELLOW}Lade OpenCode-Installationsskript herunter...${NC}"
        if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP_SCRIPT" https://opencode.ai/install; then
            echo -e "${RED}Download fehlgeschlagen.${NC}"
            rm -f "$TMP_SCRIPT"
            exit 1
        fi
        bash "$TMP_SCRIPT"
        rm -f "$TMP_SCRIPT"
    fi

    chmod +x "$INSTALL_DIR/opencode"
    echo -e "${GREEN}OpenCode installiert in $INSTALL_DIR${NC}\n"
}

# ----------------------------------------------------------------------
# PATH konfigurieren
# ----------------------------------------------------------------------
configure_path() {
    echo -e "${YELLOW}[4/6] Konfiguriere PATH...${NC}"
    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    SHELL_NAME=$(basename "$SHELL")

    case "$SHELL_NAME" in
        bash) PROFILE="$HOME/.bashrc" ;;
        zsh)  PROFILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
        fish) PROFILE="$HOME/.config/fish/config.fish" ;;
        *)    PROFILE="$HOME/.profile" ;;
    esac

    PATH_LINE="export PATH=\"$INSTALL_DIR:\$PATH\""

    if [ -f "$PROFILE" ]; then
        if ! grep -qF "$INSTALL_DIR" "$PROFILE" 2>/dev/null; then
            echo "" >> "$PROFILE"
            echo "# OpenCode" >> "$PROFILE"
            echo "$PATH_LINE" >> "$PROFILE"
            echo -e "${GREEN}PATH in $PROFILE konfiguriert.${NC}"
        else
            echo -e "${GREEN}PATH bereits konfiguriert.${NC}"
        fi
    else
        echo -e "${YELLOW}Keine Profildatei gefunden. Bitte manuell hinzufügen:${NC}"
        echo "  $PATH_LINE"
    fi

    export PATH="$INSTALL_DIR:$PATH"
    echo -e "${GREEN}PATH für diese Sitzung gesetzt.${NC}\n"
}

# ----------------------------------------------------------------------
# Installation verifizieren (OpenCode)
# ----------------------------------------------------------------------
verify_installation() {
    echo -e "${YELLOW}[5/6] Verifiziere OpenCode-Installation...${NC}"
    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"

    if [ -x "$INSTALL_DIR/opencode" ]; then
        echo -e "${GREEN}OpenCode-Binärdatei gefunden.${NC}"
        # Prüfe auf fehlende Shared Libraries
        MISSING_LIBS=$(ldd "$INSTALL_DIR/opencode" 2>/dev/null | grep "not found" || true)
        if [ -n "$MISSING_LIBS" ]; then
            echo -e "${YELLOW}Warnung: Fehlende Systembibliotheken:${NC}"
            echo "$MISSING_LIBS"
        fi
        # Versuche Version auszulesen
        if "$INSTALL_DIR/opencode" --version >/dev/null 2>&1; then
            VERSION=$("$INSTALL_DIR/opencode" --version)
            echo -e "${GREEN}OpenCode-Version: $VERSION${NC}"
        else
            echo -e "${YELLOW}OpenCode kann nicht ausgeführt werden (fehlende Abhängigkeiten).${NC}"
        fi
    else
        echo -e "${RED}OpenCode nicht gefunden oder nicht ausführbar.${NC}"
        exit 1
    fi
    echo -e "${GREEN}OpenCode-Installation abgeschlossen.${NC}\n"
}

# ----------------------------------------------------------------------
# GSD (get-shit-done-cc) installieren / ausführen
# ----------------------------------------------------------------------
install_gsd() {
    echo -e "${YELLOW}[6/6] Führe npx get-shit-done-cc@latest aus...${NC}"
    echo -e "${YELLOW}Das folgende Skript fragt interaktiv nach der gewünschten Runtime (OpenCode, Claude Code, Gemini).${NC}"
    echo -e "${YELLOW}Wähle 'OpenCode' (oder nutze die nicht-interaktiven Flags, siehe Hinweis).${NC}\n"

    # Optional: Nicht-interaktive Installation mit vordefinierten Optionen
    # npx get-shit-done-cc@latest --opencode --global

    # Hier die interaktive Variante (Benutzer wird gefragt)
    npx get-shit-done-cc@latest

    echo -e "${GREEN}GSD-Installation abgeschlossen.${NC}\n"
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
    install_gsd

    echo -e "\n${GREEN}=== Alle Installationen abgeschlossen! ===${NC}\n"
    echo "____________________________________________________________________________"
    echo ""
    echo "     Starte OpenCode mit:   opencode"
    echo "     (nach einem Neustart der Shell oder 'source ~/.bashrc')"
    echo ""
    echo "     In OpenCode kannst du dann /gsd:help eingeben."
    echo ""
    echo "____________________________________________________________________________"
}

main "$@"
