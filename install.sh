#!/usr/bin/env bash
#
# Claude Remote - Installation Script
# Installs mosh + tmux with web terminal fallback
#
# Usage:
#   ./install.sh              # Normal installation
#   ./install.sh --dry-run    # Show what would be done without doing it
#   ./install.sh --help       # Show help
#

set -e

# Mode flags
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run, -n    Show what would be done without making changes"
            echo "  --verbose, -v    Show verbose output"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  CLAUDE_REMOTE_TEST_MODE=1  Enable test mode (skip actual package installs)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="${HOME}/.local/bin"
LOCAL_SHARE="${HOME}/.local/share/claude-remote"
CONFIG_DIR="${HOME}/.config/claude-remote"

# ttyd version and checksums for verification
# Checksums obtained from official GitHub releases
TTYD_VERSION="1.7.7"

# Checksum lookup function (bash 3.2 compatible, no associative arrays)
# Checksums verified from https://github.com/tsl0922/ttyd/releases/tag/1.7.7
get_ttyd_checksum() {
    local arch="$1"
    case "$arch" in
        x86_64)  echo "8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55" ;;
        aarch64) echo "b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165" ;;
        *)       echo "" ;;  # Unknown architecture
    esac
}

print_banner() {
    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║               Claude Remote Installer                     ║"
    echo "║                                                           ║"
    echo "║   Persistent terminal sessions for mobile productivity    ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BOLD}${CYAN}▶ $1${NC}"
}

print_dry_run() {
    echo -e "  ${YELLOW}[DRY-RUN]${NC} $1"
}

# Execute a command, respecting dry-run mode
run_cmd() {
    if $DRY_RUN; then
        print_dry_run "$*"
        return 0
    fi
    "$@"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        PACKAGE_MANAGER="brew"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        PACKAGE_MANAGER="apt"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        PACKAGE_MANAGER="dnf"
    else
        OS="unknown"
        PACKAGE_MANAGER="unknown"
    fi
    print_info "Detected OS: $OS (package manager: $PACKAGE_MANAGER)"
}

check_command() {
    command -v "$1" &> /dev/null
}

install_packages_macos() {
    # Check for Homebrew
    if ! check_command brew; then
        print_error "Homebrew not found. Please install it first:"
        echo "        /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    print_info "Installing packages via Homebrew..."
    if $DRY_RUN; then
        print_dry_run "brew install mosh tmux ttyd"
    else
        # Install packages that aren't already installed
        local packages_to_install=""
        for pkg in mosh tmux ttyd; do
            if ! brew list "$pkg" &>/dev/null; then
                packages_to_install="$packages_to_install $pkg"
            else
                print_info "$pkg already installed"
            fi
        done
        if [[ -n "$packages_to_install" ]]; then
            brew install $packages_to_install
        fi
    fi
}

install_packages_debian() {
    print_info "Installing packages via apt..."
    if $DRY_RUN; then
        print_dry_run "sudo apt update"
        print_dry_run "sudo apt install -y mosh tmux"
    else
        sudo apt update
        sudo apt install -y mosh tmux
    fi

    # ttyd needs to be installed from GitHub releases or built
    install_ttyd_binary
}

install_packages_redhat() {
    print_info "Installing packages via dnf..."
    if $DRY_RUN; then
        print_dry_run "sudo dnf install -y mosh tmux"
    else
        sudo dnf install -y mosh tmux
    fi

    # ttyd needs to be installed from GitHub releases
    install_ttyd_binary
}

install_ttyd_binary() {
    if check_command ttyd; then
        print_success "ttyd already installed"
        return
    fi

    print_info "Installing ttyd from GitHub releases..."

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  TTYD_ARCH="x86_64" ;;
        aarch64|arm64) TTYD_ARCH="aarch64" ;;  # arm64 is macOS name for aarch64
        armv7l)
            print_error "armhf (armv7l) architecture is not supported"
            print_error "No verified checksum available for this platform"
            exit 1
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # Get expected checksum
    EXPECTED_CHECKSUM="$(get_ttyd_checksum "$TTYD_ARCH")"
    if [[ -z "$EXPECTED_CHECKSUM" ]]; then
        print_error "No checksum available for architecture: $TTYD_ARCH"
        exit 1
    fi

    # Download URL (pinned version for security)
    TTYD_URL="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}"

    if $DRY_RUN; then
        print_dry_run "curl -fsSL '$TTYD_URL' -o /tmp/ttyd"
        print_dry_run "Verify SHA256: $EXPECTED_CHECKSUM"
        print_dry_run "mv /tmp/ttyd '${LOCAL_BIN}/ttyd'"
        print_dry_run "chmod +x '${LOCAL_BIN}/ttyd'"
        return
    fi

    # Download to temporary file
    run_cmd mkdir -p "$LOCAL_BIN"
    TEMP_FILE=$(mktemp)
    curl -fsSL "$TTYD_URL" -o "$TEMP_FILE"

    # Verify checksum (handle both Linux sha256sum and macOS shasum)
    if command -v sha256sum &>/dev/null; then
        ACTUAL_CHECKSUM=$(sha256sum "$TEMP_FILE" | cut -d' ' -f1)
    else
        ACTUAL_CHECKSUM=$(shasum -a 256 "$TEMP_FILE" | cut -d' ' -f1)
    fi

    if [[ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]]; then
        rm -f "$TEMP_FILE"
        print_error "Checksum verification failed!"
        print_error "Expected: $EXPECTED_CHECKSUM"
        print_error "Got:      $ACTUAL_CHECKSUM"
        print_error "The binary may have been tampered with. Aborting."
        exit 1
    fi

    # Move to final location
    mv "$TEMP_FILE" "${LOCAL_BIN}/ttyd"
    chmod +x "${LOCAL_BIN}/ttyd"

    print_success "ttyd installed to ${LOCAL_BIN}/ttyd (checksum verified)"
}

generate_credentials() {
    print_step "Generating web terminal credentials"

    if $DRY_RUN; then
        print_dry_run "mkdir -p '$CONFIG_DIR'"
        print_dry_run "chmod 700 '$CONFIG_DIR'"
        print_dry_run "Generate random password with: openssl rand -hex 16"
        print_dry_run "Save to: ${CONFIG_DIR}/web-credentials"
        CLAUDE_WEB_PASSWORD="<generated-password>"
        return
    fi

    # Create secure config directory
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # Generate random password if not exists
    CRED_FILE="${CONFIG_DIR}/web-credentials"
    if [[ -f "$CRED_FILE" ]]; then
        print_info "Existing credentials found"
        WEB_PASSWORD=$(cat "$CRED_FILE")
    else
        # Generate secure random password (32 hex chars = 128 bits)
        # Use umask to create file with secure permissions atomically (fixes TOCTOU)
        WEB_PASSWORD=$(openssl rand -hex 16)
        (umask 077 && echo "$WEB_PASSWORD" > "$CRED_FILE")
        print_success "Generated new credentials"
    fi

    # Store for later display (local variable, not exported to child processes)
    CLAUDE_WEB_PASSWORD="$WEB_PASSWORD"
}

install_scripts() {
    print_step "Installing scripts"

    if $DRY_RUN; then
        print_dry_run "mkdir -p '$LOCAL_BIN'"
        print_dry_run "mkdir -p '$LOCAL_SHARE' (chmod 700)"
        print_dry_run "Create log files in '$LOCAL_SHARE'"
        print_dry_run "Copy scripts to '$LOCAL_BIN':"
        print_dry_run "  - claude-session"
        print_dry_run "  - web-terminal"
        print_dry_run "  - ttyd-wrapper"
        print_dry_run "  - claude-status"
        print_dry_run "  - claude-maintenance"
        return
    fi

    mkdir -p "$LOCAL_BIN"

    # Create secure data directory
    mkdir -p "$LOCAL_SHARE"
    chmod 700 "$LOCAL_SHARE"

    # Create log files with secure permissions
    touch "${LOCAL_SHARE}/ttyd.log"
    touch "${LOCAL_SHARE}/ttyd.error.log"
    chmod 600 "${LOCAL_SHARE}/ttyd.log"
    chmod 600 "${LOCAL_SHARE}/ttyd.error.log"

    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # Copy scripts
    cp "${SCRIPT_DIR}/scripts/claude-session" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/web-terminal" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/ttyd-wrapper" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/status" "${LOCAL_BIN}/claude-status"
    cp "${SCRIPT_DIR}/scripts/maintenance" "${LOCAL_BIN}/claude-maintenance"

    # Make executable
    chmod +x "${LOCAL_BIN}/claude-session"
    chmod +x "${LOCAL_BIN}/web-terminal"
    chmod +x "${LOCAL_BIN}/ttyd-wrapper"
    chmod +x "${LOCAL_BIN}/claude-status"
    chmod +x "${LOCAL_BIN}/claude-maintenance"

    print_success "Scripts installed to ${LOCAL_BIN}"

    # Check if LOCAL_BIN is in PATH
    if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
        print_warning "${LOCAL_BIN} is not in your PATH"
        print_info "Add this to your shell profile (.bashrc, .zshrc, etc.):"
        echo -e "        ${YELLOW}export PATH=\"\${HOME}/.local/bin:\${PATH}\"${NC}"
    fi
}

install_tmux_config() {
    print_step "Installing tmux configuration"

    if $DRY_RUN; then
        if [[ -f "${HOME}/.tmux.conf" ]]; then
            print_dry_run "Backup existing ~/.tmux.conf"
        fi
        print_dry_run "cp '${SCRIPT_DIR}/config/tmux.conf' '${HOME}/.tmux.conf'"
        return
    fi

    if [[ -f "${HOME}/.tmux.conf" ]]; then
        # Backup existing config
        BACKUP="${HOME}/.tmux.conf.backup.$(date +%Y%m%d%H%M%S)"
        cp "${HOME}/.tmux.conf" "$BACKUP"
        print_info "Existing config backed up to: $BACKUP"
    fi

    cp "${SCRIPT_DIR}/config/tmux.conf" "${HOME}/.tmux.conf"
    print_success "tmux config installed to ~/.tmux.conf"
}

install_service_linux() {
    print_step "Installing systemd services"

    if $DRY_RUN; then
        print_dry_run "mkdir -p '${HOME}/.config/systemd/user'"
        print_dry_run "Install claude-web.service (with %h -> ${HOME})"
        print_dry_run "Install claude-maintenance.service"
        print_dry_run "Install claude-maintenance.timer"
        print_dry_run "systemctl --user daemon-reload"
        print_dry_run "systemctl --user enable claude-web.service"
        print_dry_run "systemctl --user start claude-web.service"
        print_dry_run "systemctl --user enable claude-maintenance.timer"
        print_dry_run "systemctl --user start claude-maintenance.timer"
        return
    fi

    # Create user systemd directory
    mkdir -p "${HOME}/.config/systemd/user"

    # Copy web service file, substituting home directory
    sed "s|%h|${HOME}|g" "${SCRIPT_DIR}/systemd/claude-web.service" > "${HOME}/.config/systemd/user/claude-web.service"

    # Copy maintenance service and timer
    sed "s|%h|${HOME}|g" "${SCRIPT_DIR}/systemd/claude-maintenance.service" > "${HOME}/.config/systemd/user/claude-maintenance.service"
    cp "${SCRIPT_DIR}/systemd/claude-maintenance.timer" "${HOME}/.config/systemd/user/claude-maintenance.timer"

    # Check if systemctl is available (not in containers)
    if command -v systemctl &>/dev/null; then
        # Reload systemd
        systemctl --user daemon-reload

        # Enable and start web service
        systemctl --user enable claude-web.service
        systemctl --user start claude-web.service

        # Enable maintenance timer (runs weekly)
        systemctl --user enable claude-maintenance.timer
        systemctl --user start claude-maintenance.timer

        print_success "Systemd services installed and started"
        print_info "Web service: systemctl --user {start|stop|restart|status} claude-web.service"
        print_info "Maintenance: runs weekly (systemctl --user list-timers)"
    else
        print_warning "systemctl not available (running in container?)"
        print_info "Service files installed to ~/.config/systemd/user/"
        print_info "Start manually when systemd is available"
    fi
}

install_service_macos() {
    print_step "Installing launchd services"

    if $DRY_RUN; then
        print_dry_run "mkdir -p '${HOME}/Library/LaunchAgents'"
        print_dry_run "Install com.claude.web.plist (with HOMEDIR -> ${HOME})"
        print_dry_run "Install com.claude.maintenance.plist"
        if [[ -f "/opt/homebrew/bin/ttyd" ]]; then
            print_dry_run "Update ttyd path for Apple Silicon: /opt/homebrew/bin/ttyd"
        fi
        print_dry_run "launchctl load '${HOME}/Library/LaunchAgents/com.claude.web.plist'"
        print_dry_run "launchctl load '${HOME}/Library/LaunchAgents/com.claude.maintenance.plist'"
        return
    fi

    # Create LaunchAgents directory
    mkdir -p "${HOME}/Library/LaunchAgents"

    # Copy and customize web service plist (replace HOMEDIR placeholder)
    sed "s|HOMEDIR|${HOME}|g" "${SCRIPT_DIR}/launchd/com.claude.web.plist" > "${HOME}/Library/LaunchAgents/com.claude.web.plist"

    # Copy and customize maintenance plist
    sed "s|HOMEDIR|${HOME}|g" "${SCRIPT_DIR}/launchd/com.claude.maintenance.plist" > "${HOME}/Library/LaunchAgents/com.claude.maintenance.plist"

    # Update ttyd path if installed via brew (Apple Silicon)
    if [[ -f "/opt/homebrew/bin/ttyd" ]]; then
        sed -i '' "s|/usr/local/bin/ttyd|/opt/homebrew/bin/ttyd|g" "${HOME}/Library/LaunchAgents/com.claude.web.plist"
    fi

    # Load the services
    launchctl load "${HOME}/Library/LaunchAgents/com.claude.web.plist"
    launchctl load "${HOME}/Library/LaunchAgents/com.claude.maintenance.plist"

    print_success "Launchd services installed and started"
    print_info "Web service: launchctl {load|unload} ~/Library/LaunchAgents/com.claude.web.plist"
    print_info "Maintenance: runs weekly (Sundays 3:00 AM)"
}

setup_tailscale() {
    print_step "Configuring Tailscale"

    if ! check_command tailscale; then
        print_warning "Tailscale not installed"
        print_info "Install Tailscale for secure remote access:"
        if [[ "$OS" == "macos" ]]; then
            echo "        brew install --cask tailscale"
        else
            echo ""
            echo "        # Download and verify before running:"
            echo "        curl -fsSL https://tailscale.com/install.sh -o /tmp/tailscale-install.sh"
            echo "        less /tmp/tailscale-install.sh  # Review the script"
            echo "        sh /tmp/tailscale-install.sh"
        fi
        print_info "After installing, run: sudo tailscale up"
        print_info "Then re-run this installer to configure web terminal access"
        return
    fi

    # Check if Tailscale is connected
    if ! tailscale status &>/dev/null; then
        print_warning "Tailscale is not connected"
        print_info "Run: sudo tailscale up"
        return
    fi

    if $DRY_RUN; then
        print_dry_run "tailscale serve https:7681 / http://127.0.0.1:7681"
        return
    fi

    print_info "Configuring Tailscale Serve (Tailnet-only access)..."

    # Enable HTTPS serve for Tailnet-only access (no Funnel = not public)
    if tailscale serve https:7681 / http://127.0.0.1:7681 2>/dev/null; then
        print_success "Tailscale Serve enabled (Tailnet-only)"

        # Get the serve URL
        TS_HOSTNAME=$(tailscale status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')
        if [[ -n "$TS_HOSTNAME" ]]; then
            print_success "Web terminal available at: ${BOLD}https://${TS_HOSTNAME}:7681${NC}"
            print_info "Access requires Tailscale - install on your devices"
        fi
    else
        print_warning "Could not configure Tailscale Serve automatically"
        print_info "Run manually: tailscale serve https:7681 / http://127.0.0.1:7681"
    fi
}

print_completion() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}                  Installation Complete!                    ${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Display credentials
    echo -e "${BOLD}${RED}IMPORTANT - Web Terminal Credentials:${NC}"
    echo -e "  Username: ${YELLOW}claude${NC}"
    echo -e "  Password: ${YELLOW}${CLAUDE_WEB_PASSWORD}${NC}"
    echo ""
    echo -e "  ${RED}Save this password securely - you'll need it for web access!${NC}"
    echo -e "  Credentials stored in: ${CONFIG_DIR}/web-credentials"
    echo ""

    echo -e "${BOLD}Quick Start:${NC}"
    echo ""
    echo -e "  ${CYAN}1. Start a persistent session:${NC}"
    echo -e "     ${YELLOW}claude-session${NC}"
    echo ""
    echo -e "  ${CYAN}2. Connect remotely with mosh (recommended):${NC}"
    echo -e "     ${YELLOW}mosh $(whoami)@$(hostname) -- claude-session${NC}"
    echo ""
    echo -e "  ${CYAN}3. Connect via SSH:${NC}"
    echo -e "     ${YELLOW}ssh $(whoami)@$(hostname) -t 'claude-session'${NC}"
    echo ""

    if check_command tailscale && tailscale status &>/dev/null; then
        TS_HOSTNAME=$(tailscale status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')
        if [[ -n "$TS_HOSTNAME" ]]; then
            echo -e "  ${CYAN}4. Connect via web browser (requires Tailscale):${NC}"
            echo -e "     ${YELLOW}https://${TS_HOSTNAME}:7681${NC}"
            echo -e "     (Login with credentials above)"
            echo ""
        fi
    fi

    echo -e "  ${CYAN}Check status:${NC}"
    echo -e "     ${YELLOW}claude-status${NC}"
    echo ""
    echo -e "${BOLD}Security Notes:${NC}"
    echo "  • Web terminal requires Tailscale + password authentication"
    echo "  • Only accessible from devices on your Tailnet (not public)"
    echo "  • ttyd binds to localhost only (127.0.0.1)"
    echo "  • HTTPS encryption via Tailscale"
    echo "  • Max 2 concurrent web connections allowed"
    echo "  • Enable 2FA on your Tailscale account for extra security"
    echo ""
    echo -e "${BOLD}Usage Tips:${NC}"
    echo "  • Start a long-running process and disconnect - it keeps running!"
    echo "  • Reconnect anytime to pick up where you left off"
    echo "  • Use 'claude-session <name>' to create named sessions"
    echo "  • tmux prefix is Ctrl+a (e.g., Ctrl+a d to detach)"
    echo "  • Session auto-locks after 15 minutes idle"
    echo ""
    echo -e "${BLUE}For more help: claude-session --help${NC}"
    echo ""
}

# Main installation flow
main() {
    print_banner

    if $DRY_RUN; then
        echo -e "${BOLD}${YELLOW}DRY RUN MODE - No changes will be made${NC}\n"
    fi

    # Detect OS
    print_step "Detecting operating system"
    detect_os

    if [[ "$OS" == "unknown" ]]; then
        print_error "Unsupported operating system"
        exit 1
    fi

    # Install packages
    print_step "Installing dependencies"
    case "$OS" in
        macos)  install_packages_macos ;;
        debian) install_packages_debian ;;
        redhat) install_packages_redhat ;;
    esac

    print_success "mosh installed"
    print_success "tmux installed"
    print_success "ttyd installed"

    # Generate credentials before installing scripts/services
    generate_credentials

    # Install scripts
    install_scripts

    # Install tmux config
    install_tmux_config

    # Install service
    case "$OS" in
        macos)  install_service_macos ;;
        debian|redhat) install_service_linux ;;
    esac

    # Setup Tailscale
    setup_tailscale

    # Print completion message
    print_completion
}

# Run main
main "$@"
