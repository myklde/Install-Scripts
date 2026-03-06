#!/bin/bash






# INSTALL THE SCRIPT WITH THIS COMMAND: 
# ->     apt update && apt install curl -y && curl -sSL -o install.sh https://raw.githubusercontent.com/myklde/Install-Scripts/main/OpenCode-install-script-Debian-13.sh && chmod +x install.sh && ./install.sh






set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== OpenCode Installation Script ===${NC}\n"

install_dependencies() {
    echo -e "${YELLOW}[1/5] Installing dependencies...${NC}"
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y -qq curl tar unzip git build-essential git-lfs ca-certificates
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q curl tar unzip git gcc gcc-c++ make
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl tar unzip git base-devel
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl tar unzip git build-base
    else
        echo -e "${RED}No supported package manager found!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Dependencies installed${NC}\n"
}

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

install_opencode() {
    echo -e "${YELLOW}[3/5] Installing OpenCode...${NC}"
    
    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    mkdir -p "$INSTALL_DIR"
    
    if [ -n "${OPENCODE_BINARY:-}" ]; then
        echo -e "${YELLOW}Installing from local binary: $OPENCODE_BINARY${NC}"
        cp "$OPENCODE_BINARY" "$INSTALL_DIR/opencode"
    else
        echo -e "${YELLOW}Downloading OpenCode...${NC}"
        curl -fsSL https://opencode.ai/install | bash
    fi
    
    chmod +x "$INSTALL_DIR/opencode"
    echo -e "${GREEN}OpenCode installed in $INSTALL_DIR${NC}\n"
}

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

verify_installation() {
    echo -e "${YELLOW}[5/5] Verifying installation...${NC}"
    
    INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}"
    
    if [ -x "$INSTALL_DIR/opencode" ]; then
        echo -e "${GREEN}OpenCode binary found${NC}"
        
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
    echo "     reboot one time and Start OpenCode in the Terminal with:   opencode    "
    echo ""
    echo "____________________________________________________________________________"
}

main() {
    install_dependencies
    check_requirements
    install_opencode
    configure_path
    verify_installation
}

main "$@"
