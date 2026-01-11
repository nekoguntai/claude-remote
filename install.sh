#!/usr/bin/env bash
#
# Anyshell - Installation Script
# Installs mosh + tmux with web terminal fallback
#
# Usage:
#   ./install.sh              # Fresh installation
#   ./install.sh --upgrade    # Upgrade existing installation
#   ./install.sh --dry-run    # Show what would be done without doing it
#   ./install.sh --version    # Show version
#   ./install.sh --help       # Show help
#

set -e

# Version
VERSION="1.0.0"

# Mode flags
DRY_RUN=false
VERBOSE=false
UPGRADE_MODE=false
SKIP_TTYD=false

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
        --upgrade|-u)
            UPGRADE_MODE=true
            shift
            ;;
        --version|-V)
            echo "anyshell version $VERSION"
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --upgrade, -u    Upgrade existing installation"
            echo "  --dry-run, -n    Show what would be done without making changes"
            echo "  --verbose, -v    Show verbose output"
            echo "  --version, -V    Show version information"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  ANYSHELL_TEST_MODE=1  Enable test mode (skip actual package installs)"
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
LOCAL_SHARE="${HOME}/.local/share/anyshell"
CONFIG_DIR="${HOME}/.config/anyshell"
VERSION_FILE="${CONFIG_DIR}/version"

# Get currently installed version (returns "none" if not installed)
get_installed_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "none"
    fi
}

# Compare versions: returns 0 if v1 > v2, 1 if v1 = v2, 2 if v1 < v2
# Simple semver comparison (works for X.Y.Z format)
version_compare() {
    local v1="$1"
    local v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        return 1  # Equal
    fi

    # Split versions into arrays
    local IFS='.'
    # shellcheck disable=SC2206
    local v1_parts=($v1)
    # shellcheck disable=SC2206
    local v2_parts=($v2)

    # Compare each part
    for i in 0 1 2; do
        local p1="${v1_parts[$i]:-0}"
        local p2="${v2_parts[$i]:-0}"
        if (( p1 > p2 )); then
            return 0  # v1 > v2
        elif (( p1 < p2 )); then
            return 2  # v1 < v2
        fi
    done

    return 1  # Equal
}

# Save version to file
save_version() {
    mkdir -p "$CONFIG_DIR"
    echo "$VERSION" > "$VERSION_FILE"
}

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
    local installed_version
    installed_version=$(get_installed_version)

    echo -e "${BOLD}${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    if $UPGRADE_MODE; then
        echo "║               Anyshell Upgrader                      ║"
    else
        echo "║               Anyshell Installer                     ║"
    fi
    echo "║                                                           ║"
    echo "║   Persistent terminal sessions for mobile productivity    ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Show version info
    if $UPGRADE_MODE; then
        if [[ "$installed_version" == "none" ]]; then
            echo -e "${YELLOW}No existing installation found. Performing fresh install.${NC}"
            UPGRADE_MODE=false
        else
            echo -e "  ${CYAN}Installed version:${NC} ${installed_version}"
            echo -e "  ${CYAN}New version:${NC}       ${VERSION}"

            # Check if upgrade is needed
            local cmp=0
            version_compare "$VERSION" "$installed_version" && cmp=0 || cmp=$?
            if [[ $cmp -eq 0 ]]; then
                echo -e "  ${GREEN}Upgrading...${NC}"
            elif [[ $cmp -eq 1 ]]; then
                echo -e "  ${YELLOW}Already at version ${VERSION}. Re-installing...${NC}"
            else
                echo -e "  ${YELLOW}Warning: Installed version is newer. Proceeding anyway...${NC}"
            fi
        fi
        echo ""
    else
        echo -e "  ${CYAN}Version:${NC} ${VERSION}"
        if [[ "$installed_version" != "none" ]]; then
            echo -e "  ${YELLOW}Note: Existing installation detected (v${installed_version})${NC}"
            echo -e "  ${YELLOW}Use --upgrade for cleaner upgrade messaging${NC}"
        fi
        echo ""
    fi
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

# Ensure Homebrew is in PATH on macOS (may not be set in non-interactive shells)
init_homebrew_path() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        return
    fi

    # Check if brew is already in PATH
    if command -v brew &>/dev/null; then
        return
    fi

    # Try Apple Silicon location first, then Intel
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        print_info "Added Homebrew to PATH (Apple Silicon: /opt/homebrew)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        print_info "Added Homebrew to PATH (Intel: /usr/local)"
    fi
}

check_command() {
    command -v "$1" &> /dev/null
}

# macOS: Tailscale CLI is inside the app bundle, not in PATH
TAILSCALE_CMD="tailscale"
if [[ "$OSTYPE" == "darwin"* ]] && ! command -v tailscale &>/dev/null; then
    if [[ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
        TAILSCALE_CMD="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    fi
fi

# Check if Tailscale is available (handles macOS app bundle location)
check_tailscale() {
    command -v tailscale &>/dev/null || [[ -x "$TAILSCALE_CMD" ]]
}

install_homebrew() {
    print_info "Installing Homebrew..."
    echo ""

    if $DRY_RUN; then
        print_dry_run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        return 0
    fi

    # Run the Homebrew installer
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this session (Apple Silicon vs Intel)
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        print_success "Homebrew installed (Apple Silicon)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        print_success "Homebrew installed (Intel)"
    else
        print_error "Homebrew installation may have failed"
        return 1
    fi

    return 0
}

install_packages_macos() {
    # Check what's already installed
    local has_mosh=false
    local has_tmux=false
    local has_ttyd=false

    check_command mosh && has_mosh=true
    check_command tmux && has_tmux=true
    check_command ttyd && has_ttyd=true

    # Check if all packages are already installed
    if $has_mosh && $has_tmux && $has_ttyd; then
        print_success "All packages already installed"
        return
    fi

    # Check for Homebrew
    if ! check_command brew; then
        print_warning "Homebrew is not installed"
        echo ""
        print_info "Homebrew is the recommended way to install packages on macOS."
        print_info "It will install: mosh, tmux, and ttyd"
        echo ""

        if $DRY_RUN; then
            print_dry_run "Would prompt to install Homebrew"
            print_dry_run "brew install mosh tmux ttyd"
            return
        fi

        # Ask user if they want to install Homebrew
        print_info "Note: The Homebrew installer will ask for your Mac password"
        print_info "and may display additional prompts."
        echo ""
        echo -e "${BOLD}Would you like to install Homebrew now? [Y/n]${NC} "
        read -r response
        response=${response:-Y}  # Default to Y if empty

        if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
            install_homebrew || {
                print_error "Failed to install Homebrew"
                echo ""
                print_info "You can install it manually:"
                echo '        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                echo ""
                print_info "Then re-run this installer."
                exit 1
            }
        else
            # User declined Homebrew - check what's available
            echo ""
            if ! $has_mosh || ! $has_tmux; then
                print_error "mosh and tmux are required but not installed."
                echo ""
                print_info "Alternative installation methods:"
                echo ""
                print_info "MacPorts:"
                echo "        sudo port install mosh tmux"
                echo ""
                print_info "From source:"
                echo "        See: https://github.com/mobile-shell/mosh"
                echo "        See: https://github.com/tmux/tmux"
                echo ""
                exit 1
            fi

            # mosh and tmux exist, but no Homebrew for ttyd
            if ! $has_ttyd; then
                print_warning "ttyd not available - web terminal will be disabled"
                print_info "To enable later, install Homebrew and run: brew install ttyd"
                SKIP_TTYD=true
            fi
            return
        fi
    fi

    # Homebrew is available - install packages
    print_info "Installing packages via Homebrew..."

    local packages_to_install=""
    for pkg in mosh tmux ttyd; do
        if ! brew list "$pkg" &>/dev/null && ! check_command "$pkg"; then
            packages_to_install="$packages_to_install $pkg"
        else
            print_info "$pkg already installed"
        fi
    done

    if [[ -n "$packages_to_install" ]]; then
        brew install $packages_to_install
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
        ANYSHELL_WEB_PASSWORD="<generated-password>"
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
    ANYSHELL_WEB_PASSWORD="$WEB_PASSWORD"
}

install_scripts() {
    print_step "Installing scripts"

    if $DRY_RUN; then
        print_dry_run "mkdir -p '$LOCAL_BIN'"
        print_dry_run "mkdir -p '$LOCAL_SHARE' (chmod 700)"
        print_dry_run "Create log files in '$LOCAL_SHARE'"
        print_dry_run "Copy scripts to '$LOCAL_BIN':"
        print_dry_run "  - anyshell"
        print_dry_run "  - web-terminal"
        print_dry_run "  - ttyd-wrapper"
        print_dry_run "  - anyshell-status"
        print_dry_run "  - anyshell-maintenance"
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
    cp "${SCRIPT_DIR}/scripts/anyshell" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/web-terminal" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/ttyd-wrapper" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/anyshell-status" "${LOCAL_BIN}/"
    cp "${SCRIPT_DIR}/scripts/anyshell-maintenance" "${LOCAL_BIN}/"

    # Make executable
    chmod +x "${LOCAL_BIN}/anyshell"
    chmod +x "${LOCAL_BIN}/web-terminal"
    chmod +x "${LOCAL_BIN}/ttyd-wrapper"
    chmod +x "${LOCAL_BIN}/anyshell-status"
    chmod +x "${LOCAL_BIN}/anyshell-maintenance"

    print_success "Scripts installed to ${LOCAL_BIN}"

    # Check if LOCAL_BIN is in PATH and add if needed
    if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
        print_warning "${LOCAL_BIN} is not in your PATH"

        if $DRY_RUN; then
            print_dry_run "Would add PATH export to shell profile"
        else
            # Determine shell profile to update
            local shell_profile=""
            local current_shell=$(basename "$SHELL")

            if [[ "$current_shell" == "zsh" ]]; then
                shell_profile="${HOME}/.zshrc"
            elif [[ "$current_shell" == "bash" ]]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    shell_profile="${HOME}/.bash_profile"
                else
                    shell_profile="${HOME}/.bashrc"
                fi
            fi

            if [[ -n "$shell_profile" ]]; then
                local path_line='export PATH="${HOME}/.local/bin:${PATH}"'

                # Check if already present (avoid duplicates)
                if [[ -f "$shell_profile" ]] && grep -qF '.local/bin' "$shell_profile"; then
                    print_info "PATH already configured in $shell_profile"
                else
                    echo "" >> "$shell_profile"
                    echo "# Added by anyshell installer" >> "$shell_profile"
                    echo "$path_line" >> "$shell_profile"
                    print_success "Added PATH to $shell_profile"
                    print_info "Run 'source $shell_profile' or restart your terminal"
                fi

                # Also add to current session
                export PATH="${LOCAL_BIN}:${PATH}"
            else
                print_info "Add this to your shell profile manually:"
                echo -e "        ${YELLOW}export PATH=\"\${HOME}/.local/bin:\${PATH}\"${NC}"
            fi
        fi
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
        print_dry_run "Install anyshell-web.service (with %h -> ${HOME})"
        print_dry_run "Install anyshell-maintenance.service"
        print_dry_run "Install anyshell-maintenance.timer"
        print_dry_run "systemctl --user daemon-reload"
        print_dry_run "systemctl --user enable anyshell-web.service"
        print_dry_run "systemctl --user start anyshell-web.service"
        print_dry_run "systemctl --user enable anyshell-maintenance.timer"
        print_dry_run "systemctl --user start anyshell-maintenance.timer"
        return
    fi

    # Create user systemd directory
    mkdir -p "${HOME}/.config/systemd/user"

    # Copy web service file, substituting home directory
    sed "s|%h|${HOME}|g" "${SCRIPT_DIR}/systemd/anyshell-web.service" > "${HOME}/.config/systemd/user/anyshell-web.service"

    # Copy maintenance service and timer
    sed "s|%h|${HOME}|g" "${SCRIPT_DIR}/systemd/anyshell-maintenance.service" > "${HOME}/.config/systemd/user/anyshell-maintenance.service"
    cp "${SCRIPT_DIR}/systemd/anyshell-maintenance.timer" "${HOME}/.config/systemd/user/anyshell-maintenance.timer"

    # Check if systemctl is available (not in containers)
    if command -v systemctl &>/dev/null; then
        # Reload systemd
        systemctl --user daemon-reload

        # Enable and start web service
        systemctl --user enable anyshell-web.service
        systemctl --user start anyshell-web.service

        # Enable maintenance timer (runs weekly)
        systemctl --user enable anyshell-maintenance.timer
        systemctl --user start anyshell-maintenance.timer

        print_success "Systemd services installed and started"
        print_info "Web service: systemctl --user {start|stop|restart|status} anyshell-web.service"
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
        print_dry_run "Install com.anyshell.web.plist (with HOMEDIR -> ${HOME})"
        print_dry_run "Install com.anyshell.maintenance.plist"
        if [[ -f "/opt/homebrew/bin/ttyd" ]]; then
            print_dry_run "Update ttyd path for Apple Silicon: /opt/homebrew/bin/ttyd"
        fi
        print_dry_run "launchctl load '${HOME}/Library/LaunchAgents/com.anyshell.web.plist'"
        print_dry_run "launchctl load '${HOME}/Library/LaunchAgents/com.anyshell.maintenance.plist'"
        return
    fi

    # Create LaunchAgents directory
    mkdir -p "${HOME}/Library/LaunchAgents"

    # Copy and customize web service plist (replace HOMEDIR placeholder)
    sed "s|HOMEDIR|${HOME}|g" "${SCRIPT_DIR}/launchd/com.anyshell.web.plist" > "${HOME}/Library/LaunchAgents/com.anyshell.web.plist"

    # Copy and customize maintenance plist
    sed "s|HOMEDIR|${HOME}|g" "${SCRIPT_DIR}/launchd/com.anyshell.maintenance.plist" > "${HOME}/Library/LaunchAgents/com.anyshell.maintenance.plist"

    # Update ttyd path if installed via brew (Apple Silicon)
    if [[ -f "/opt/homebrew/bin/ttyd" ]]; then
        sed -i '' "s|/usr/local/bin/ttyd|/opt/homebrew/bin/ttyd|g" "${HOME}/Library/LaunchAgents/com.anyshell.web.plist"
    fi

    # Load the services
    launchctl load "${HOME}/Library/LaunchAgents/com.anyshell.web.plist"
    launchctl load "${HOME}/Library/LaunchAgents/com.anyshell.maintenance.plist"

    print_success "Launchd services installed and started"
    print_info "Web service: launchctl {load|unload} ~/Library/LaunchAgents/com.anyshell.web.plist"
    print_info "Maintenance: runs weekly (Sundays 3:00 AM)"
}

install_tailscale() {
    print_info "Installing Tailscale..."

    if $DRY_RUN; then
        if [[ "$OS" == "macos" ]]; then
            print_dry_run "brew install --cask tailscale"
        else
            print_dry_run "curl -fsSL https://tailscale.com/install.sh | sh"
        fi
        return 0
    fi

    if [[ "$OS" == "macos" ]]; then
        if check_command brew; then
            brew install --cask tailscale
        else
            print_error "Homebrew required to install Tailscale on macOS"
            print_info "Install manually from: https://tailscale.com/download/mac"
            return 1
        fi
    else
        # Linux - use official install script
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    if check_tailscale; then
        print_success "Tailscale installed"
        return 0
    else
        print_error "Tailscale installation may have failed"
        return 1
    fi
}

setup_tailscale() {
    print_step "Setting up Tailscale"

    # Check if Tailscale is installed
    if ! check_tailscale; then
        print_warning "Tailscale is not installed"
        print_info "Tailscale provides secure remote access to your machine"
        echo ""

        if $DRY_RUN; then
            print_dry_run "Would prompt to install Tailscale"
            return
        fi

        echo -e "${BOLD}Would you like to install Tailscale now? [Y/n]${NC} "
        read -r response
        response=${response:-Y}

        if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
            install_tailscale || {
                print_warning "Tailscale installation failed"
                print_info "You can install it later from: https://tailscale.com/download"
                return
            }
        else
            print_info "Skipping Tailscale installation"
            print_info "Install later from: https://tailscale.com/download"
            return
        fi
    fi

    # Check if Tailscale is connected
    if ! $TAILSCALE_CMD status &>/dev/null; then
        print_warning "Tailscale is installed but not connected"
        echo ""

        if $DRY_RUN; then
            print_dry_run "tailscale up (with timeout)"
            return
        fi

        if [[ "$OS" == "macos" ]]; then
            # macOS: The Tailscale app handles authentication via GUI
            echo ""
            print_warning "ACTION REQUIRED: You must log in to Tailscale to continue"
            echo ""
            print_info "Look for the Tailscale icon in the menu bar (upper right corner of your screen)"
            print_info "  1. Click the Tailscale icon in the menu bar"
            print_info "  2. Click 'Log in' or 'Connect'"
            print_info "  3. Complete authentication in your browser"
            echo ""
            print_warning "This installer is PAUSED and will wait indefinitely until you log in"
            echo ""
            echo -e "${BOLD}Press Enter once you've logged in via the Tailscale menu bar app...${NC}"
            read -r

            # Check if now connected
            if $TAILSCALE_CMD status &>/dev/null; then
                print_success "Tailscale connected"
            else
                print_warning "Tailscale still not connected"
                print_info "Connect via the Tailscale menu bar app when ready"
                return
            fi
        else
            # Linux: Use CLI with timeout
            echo -e "${BOLD}Would you like to connect to Tailscale now? [Y/n]${NC} "
            read -r response
            response=${response:-Y}

            if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
                print_info "Starting Tailscale authentication..."
                print_info "A URL will be displayed - open it in your browser to authenticate"
                print_info "(Timeout: 120 seconds)"
                echo ""

                # Use timeout to prevent indefinite hang
                if sudo tailscale up --timeout=120s 2>&1; then
                    print_success "Tailscale connected"
                else
                    print_warning "Tailscale connection timed out or failed"
                    print_info "Run manually: sudo tailscale up"
                    return
                fi
            else
                print_info "Skipping Tailscale connection"
                print_info "Connect later with: sudo tailscale up"
                return
            fi
        fi
    fi

    print_success "Tailscale is connected"

    # Only configure serve if ttyd is available
    if $SKIP_TTYD; then
        print_info "Skipping Tailscale Serve (ttyd not available)"
        return
    fi

    if $DRY_RUN; then
        print_dry_run "$TAILSCALE_CMD serve --bg --https 7681 http://127.0.0.1:7681"
        return
    fi

    print_info "Configuring Tailscale Serve for web terminal..."

    # Enable HTTPS serve for Tailnet-only access (no Funnel = not public)
    # Use new CLI syntax (old syntax deprecated)
    local SERVE_OUTPUT
    SERVE_OUTPUT=$($TAILSCALE_CMD serve --bg --https 7681 http://127.0.0.1:7681 2>&1)
    local SERVE_EXIT=$?

    # Check if Serve needs to be enabled on the tailnet
    if echo "$SERVE_OUTPUT" | grep -q "Serve is not enabled on your tailnet"; then
        local ENABLE_URL
        ENABLE_URL=$(echo "$SERVE_OUTPUT" | grep -o 'https://login.tailscale.com/[^ ]*' | head -1)

        print_warning "Tailscale Serve is not enabled on your tailnet"
        echo ""
        print_info "To enable Tailscale Serve, visit:"
        echo ""
        echo "    ${ENABLE_URL:-https://login.tailscale.com/admin/machines}"
        echo ""
        print_info "After enabling, run: tailscale serve --bg --https 7681 http://127.0.0.1:7681"
        return
    fi

    if [[ $SERVE_EXIT -eq 0 ]] || echo "$SERVE_OUTPUT" | grep -q "Available within your tailnet"; then
        print_success "Tailscale Serve enabled (Tailnet-only)"

        # Get the serve URL
        TS_HOSTNAME=$($TAILSCALE_CMD status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')
        if [[ -n "$TS_HOSTNAME" ]]; then
            print_success "Web terminal: https://${TS_HOSTNAME}:7681"
        fi
    else
        print_warning "Could not configure Tailscale Serve automatically"
        print_info "Run manually: tailscale serve --bg --https 7681 http://127.0.0.1:7681"
    fi
}

configure_ssh_server() {
    print_step "Checking SSH server (required for mosh)"

    if [[ "$OS" == "macos" ]]; then
        # macOS: Check if Remote Login is enabled
        echo ""
        print_info "Mosh requires SSH to establish the initial connection"
        print_info "On macOS, this is called 'Remote Login'"
        echo ""

        if $DRY_RUN; then
            print_dry_run "Check Remote Login status"
            print_dry_run "sudo systemsetup -setremotelogin on (if needed)"
            return
        fi

        # Check if sshd is listening on port 22
        if sudo lsof -i :22 2>/dev/null | grep -q LISTEN; then
            print_success "SSH server is running (port 22)"
            return
        fi

        # SSH not running - prompt to enable
        print_warning "SSH server is not running"
        echo ""
        print_info "Without SSH enabled, you cannot connect remotely via mosh or ssh"
        echo ""
        echo -e "${BOLD}Enable Remote Login (SSH server)? [Y/n]${NC} "
        read -r response
        response=${response:-Y}

        if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
            print_info "Enabling Remote Login (requires administrator password)..."

            # Try systemsetup first, but it may fail due to Full Disk Access requirement
            local setup_output
            setup_output=$(sudo systemsetup -setremotelogin on 2>&1)
            local setup_exit=$?

            if [[ $setup_exit -eq 0 ]] && ! echo "$setup_output" | grep -qi "Full Disk Access"; then
                print_success "Remote Login enabled"

                # Verify it's actually running now
                sleep 1
                if sudo lsof -i :22 2>/dev/null | grep -q LISTEN; then
                    print_success "SSH server is now accepting connections on port 22"
                else
                    print_warning "SSH may take a moment to start"
                    print_info "Verify with: sudo lsof -i :22"
                fi
            else
                # systemsetup failed - likely Full Disk Access issue
                if echo "$setup_output" | grep -qi "Full Disk Access"; then
                    print_warning "macOS requires Full Disk Access to enable SSH via command line"
                    echo ""
                    print_info "Please enable Remote Login manually:"
                    print_info "  1. Open System Settings"
                    print_info "  2. Go to General > Sharing"
                    print_info "  3. Toggle ON 'Remote Login'"
                    echo ""
                    print_info "(Alternative: Grant Terminal 'Full Disk Access' in Privacy & Security)"
                else
                    print_warning "Could not enable via systemsetup"
                    echo ""
                    print_info "Enable manually via System Settings:"
                    print_info "  System Settings > General > Sharing > Remote Login"
                fi
                echo ""
                echo -e "${BOLD}Press Enter after enabling Remote Login...${NC}"
                read -r

                # Verify after manual enable
                if sudo lsof -i :22 2>/dev/null | grep -q LISTEN; then
                    print_success "SSH server is now running"
                else
                    print_warning "SSH still not detected - verify Remote Login is enabled"
                fi
            fi
        else
            print_warning "Skipping SSH setup"
            print_error "WARNING: Mosh will NOT work without SSH enabled!"
            print_info "Enable later: sudo systemsetup -setremotelogin on"
            print_info "Or: System Settings > General > Sharing > Remote Login"
        fi
        return
    fi

    # Linux: Check if sshd is running
    if $DRY_RUN; then
        print_dry_run "Check if sshd service is running"
        print_dry_run "Enable sshd if needed"
        return
    fi

    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        print_success "SSH server is running"
        return
    fi

    # Check if it's installed but not running
    if systemctl list-unit-files | grep -qE "^ssh(d)?\.service"; then
        print_warning "SSH server is installed but not running"
        echo ""
        echo -e "${BOLD}Start and enable SSH server? [Y/n]${NC} "
        read -r response
        response=${response:-Y}

        if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
            # Try both service names (ssh for Debian, sshd for RHEL)
            if sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null; then
                print_success "SSH server started and enabled"
            else
                print_warning "Failed to start SSH server"
                print_info "Start manually: sudo systemctl enable --now ssh"
            fi
        fi
    else
        print_warning "SSH server (openssh-server) may not be installed"
        print_info "Install with: sudo apt install openssh-server"
    fi
}

optimize_ssh_for_mosh() {
    print_step "Optimizing SSH server for mosh connections"

    local SSHD_CONFIG="/etc/ssh/sshd_config"
    local needs_restart=false

    if $DRY_RUN; then
        print_dry_run "Check/add UseDNS no to $SSHD_CONFIG"
        print_dry_run "Check/add GSSAPIAuthentication no to $SSHD_CONFIG"
        print_dry_run "Reload SSH service if changes made"
        return
    fi

    # Check if sshd_config exists
    if [[ ! -f "$SSHD_CONFIG" ]]; then
        print_warning "SSH config not found at $SSHD_CONFIG"
        return
    fi

    # Check and add UseDNS no (prevents slow DNS reverse lookups)
    if grep -qE "^UseDNS\s+no" "$SSHD_CONFIG" 2>/dev/null; then
        print_success "UseDNS no already configured"
    elif grep -qE "^UseDNS" "$SSHD_CONFIG" 2>/dev/null; then
        print_info "UseDNS is set but not to 'no' - skipping (manual review recommended)"
    else
        print_info "Adding UseDNS no to speed up mosh connections..."
        if echo -e "\n# Disable DNS reverse lookup for faster mosh/ssh connections\nUseDNS no" | sudo tee -a "$SSHD_CONFIG" > /dev/null; then
            print_success "Added UseDNS no"
            needs_restart=true
        else
            print_warning "Failed to add UseDNS setting"
        fi
    fi

    # Check and add GSSAPIAuthentication no (prevents Kerberos timeout delays)
    if grep -qE "^GSSAPIAuthentication\s+no" "$SSHD_CONFIG" 2>/dev/null; then
        print_success "GSSAPIAuthentication no already configured"
    elif grep -qE "^GSSAPIAuthentication" "$SSHD_CONFIG" 2>/dev/null; then
        print_info "GSSAPIAuthentication is set but not to 'no' - skipping (may be needed for Kerberos)"
    else
        print_info "Adding GSSAPIAuthentication no to speed up mosh connections..."
        if echo -e "\n# Disable GSSAPI to prevent authentication delays\nGSSAPIAuthentication no" | sudo tee -a "$SSHD_CONFIG" > /dev/null; then
            print_success "Added GSSAPIAuthentication no"
            needs_restart=true
        else
            print_warning "Failed to add GSSAPIAuthentication setting"
        fi
    fi

    # Reload SSH service if changes were made
    if $needs_restart; then
        print_info "Reloading SSH service to apply changes..."
        if [[ "$OS" == "macos" ]]; then
            # macOS: launchctl stop will cause it to restart automatically
            if sudo launchctl stop com.openssh.sshd 2>/dev/null; then
                print_success "SSH service reloaded"
            else
                print_warning "Could not reload SSH - changes will apply on next restart"
            fi
        else
            # Linux: reload or restart sshd
            if sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null; then
                print_success "SSH service reloaded"
            elif sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null; then
                print_success "SSH service restarted"
            else
                print_warning "Could not reload SSH - changes will apply on next restart"
            fi
        fi
    fi
}

configure_homebrew_path() {
    # Ensure Homebrew is in PATH for non-interactive shells (required for mosh-server)
    # This is only needed on macOS with Homebrew
    if [[ "$OS" != "macos" ]]; then
        return
    fi

    # Check if Homebrew is installed
    local brew_path=""
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        brew_path="/opt/homebrew/bin/brew"  # Apple Silicon
    elif [[ -x "/usr/local/bin/brew" ]]; then
        brew_path="/usr/local/bin/brew"  # Intel Mac
    else
        return  # No Homebrew installed
    fi

    print_step "Configuring Homebrew PATH for remote sessions"

    if $DRY_RUN; then
        print_dry_run "Check if Homebrew PATH is in ~/.zshenv"
        print_dry_run "Add 'eval \"\$($brew_path shellenv)\"' to ~/.zshenv if needed"
        return
    fi

    local zshenv="$HOME/.zshenv"
    local shellenv_cmd="eval \"\$($brew_path shellenv)\""

    # Check if already configured
    if [[ -f "$zshenv" ]] && grep -qF "brew shellenv" "$zshenv" 2>/dev/null; then
        print_success "Homebrew PATH already configured in ~/.zshenv"
        return
    fi

    # Add Homebrew to PATH in .zshenv (sourced for all zsh sessions including non-interactive)
    print_info "Adding Homebrew to PATH in ~/.zshenv..."
    print_info "This ensures mosh-server can be found during remote connections"

    if echo -e "\n# Homebrew PATH (required for mosh-server in non-interactive shells)\n$shellenv_cmd" >> "$zshenv"; then
        print_success "Homebrew PATH added to ~/.zshenv"
    else
        print_warning "Failed to update ~/.zshenv"
        print_info "Add manually: echo '$shellenv_cmd' >> ~/.zshenv"
    fi
}

configure_firewall() {
    print_step "Configuring firewall for mosh"

    # Mosh uses UDP ports 60000-61000
    local MOSH_PORTS="60000:61000/udp"

    if [[ "$OS" == "macos" ]]; then
        # macOS firewall typically doesn't block mosh by default
        # The Application Firewall handles this at the app level
        print_info "macOS firewall typically allows mosh connections"
        print_info "If prompted, allow 'mosh-server' when connecting"

        if $DRY_RUN; then
            print_dry_run "macOS: No firewall changes needed"
            return
        fi

        # Check if firewall is enabled
        if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
            print_info "Application Firewall is enabled"
            print_info "mosh-server will be allowed automatically when first used"
        fi
        return
    fi

    # Linux firewall configuration
    if $DRY_RUN; then
        if check_command ufw; then
            print_dry_run "sudo ufw allow 60000:61000/udp comment 'mosh'"
        elif check_command firewall-cmd; then
            print_dry_run "sudo firewall-cmd --permanent --add-port=60000-61000/udp"
            print_dry_run "sudo firewall-cmd --reload"
        else
            print_dry_run "No firewall detected - skipping"
        fi
        return
    fi

    # Check for UFW (Ubuntu/Debian)
    if check_command ufw; then
        if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
            print_info "UFW firewall detected, opening mosh ports..."

            echo -e "${BOLD}Allow mosh through firewall (UDP 60000-61000)? [Y/n]${NC} "
            read -r response
            response=${response:-Y}

            if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
                if sudo ufw allow 60000:61000/udp comment 'mosh'; then
                    print_success "Firewall configured for mosh"
                else
                    print_warning "Failed to configure UFW"
                    print_info "Run manually: sudo ufw allow 60000:61000/udp"
                fi
            else
                print_info "Skipping firewall configuration"
                print_info "Run manually if needed: sudo ufw allow 60000:61000/udp"
            fi
        else
            print_info "UFW is installed but not active"
        fi
        return
    fi

    # Check for firewalld (Fedora/RHEL)
    if check_command firewall-cmd; then
        if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
            print_info "firewalld detected, opening mosh ports..."

            echo -e "${BOLD}Allow mosh through firewall (UDP 60000-61000)? [Y/n]${NC} "
            read -r response
            response=${response:-Y}

            if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
                if sudo firewall-cmd --permanent --add-port=60000-61000/udp && \
                   sudo firewall-cmd --reload; then
                    print_success "Firewall configured for mosh"
                else
                    print_warning "Failed to configure firewalld"
                    print_info "Run manually: sudo firewall-cmd --permanent --add-port=60000-61000/udp"
                fi
            else
                print_info "Skipping firewall configuration"
            fi
        else
            print_info "firewalld is installed but not running"
        fi
        return
    fi

    # Check for iptables
    if check_command iptables; then
        print_info "iptables detected"
        print_info "To allow mosh, add this rule:"
        echo "        sudo iptables -A INPUT -p udp --dport 60000:61000 -j ACCEPT"
        return
    fi

    print_info "No firewall detected - no configuration needed"
}

configure_mac_sleep() {
    print_step "Configuring Mac sleep settings"

    echo ""
    print_info "For a headless Mac (server/always-on), sleep must be disabled"
    print_info "Otherwise the Mac becomes unreachable when it sleeps"
    echo ""

    if $DRY_RUN; then
        print_dry_run "sudo pmset -a sleep 0 disksleep 0 displaysleep 0"
        return
    fi

    # Check current sleep setting
    local current_sleep
    current_sleep=$(pmset -g | grep -E "^\s*sleep\s+" | awk '{print $2}')

    if [[ "$current_sleep" == "0" ]]; then
        print_success "Sleep already disabled"
        return
    fi

    print_warning "Current sleep setting: ${current_sleep} minutes"
    echo ""
    echo -e "${BOLD}Disable sleep to keep Mac accessible? [Y/n]${NC} "
    read -r response
    response=${response:-Y}

    if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
        print_info "Disabling sleep (requires administrator password)..."
        if sudo pmset -a sleep 0 disksleep 0 displaysleep 0; then
            print_success "Sleep disabled"
            print_info "Mac will stay awake and accessible"
            print_info "To re-enable later: sudo pmset -a sleep 10"
        else
            print_warning "Failed to disable sleep"
            print_info "Run manually: sudo pmset -a sleep 0 disksleep 0 displaysleep 0"
        fi
    else
        print_warning "Skipping sleep configuration"
        print_info "WARNING: Mac may sleep and become unreachable"
        print_info "Disable later: sudo pmset -a sleep 0 disksleep 0 displaysleep 0"
    fi
}

configure_boot_persistence() {
    print_step "Configuring services to survive reboots"

    if [[ "$OS" == "macos" ]]; then
        # macOS: LaunchAgents start at user login by default
        echo ""
        print_info "IMPORTANT: Understanding macOS service persistence"
        echo ""
        print_info "On macOS, there are two types of startup services:"
        print_info "  1. LaunchAgents  - Start when YOU log in (current setup)"
        print_info "  2. LaunchDaemons - Start at BOOT before anyone logs in"
        echo ""

        if $DRY_RUN; then
            print_dry_run "macOS: Services already configured for login startup"
            if [[ -d "/Applications/Tailscale.app" ]]; then
                print_dry_run "Add Tailscale to login items (osascript)"
            fi
            return
        fi

        # Verify services are set to load at login
        if [[ -f "${HOME}/Library/LaunchAgents/com.anyshell.web.plist" ]]; then
            print_success "Web terminal service installed as LaunchAgent"
        fi

        echo ""
        print_warning "CURRENT BEHAVIOR: Services start when you log in to your Mac"
        print_info "This means after a reboot, you must log in (locally or via SSH)"
        print_info "before the web terminal becomes available."
        echo ""

        # Add Tailscale to login items so it starts at boot
        if [[ -d "/Applications/Tailscale.app" ]]; then
            # Check if Tailscale is already in login items
            if ! osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "Tailscale"; then
                print_info "Adding Tailscale to login items..."
                if osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Tailscale.app", hidden:false}' &>/dev/null; then
                    print_success "Tailscale added to login items (will start at login)"
                else
                    print_warning "Could not add Tailscale to login items"
                    print_info "Add manually: System Settings > General > Login Items > Add Tailscale"
                fi
            else
                print_success "Tailscale already in login items"
            fi
        fi

        echo ""
        print_info "FOR HEADLESS/REMOTE MAC SETUP:"
        print_info "  Option 1: Enable 'Automatic Login' in System Settings > Users & Groups"
        print_info "            This logs you in at boot, starting all LaunchAgents"
        echo ""
        print_info "  Option 2: Move services to LaunchDaemons (advanced, requires admin):"
        print_info "            sudo mv ~/Library/LaunchAgents/com.anyshell.*.plist /Library/LaunchDaemons/"
        print_info "            Then update the plist to run as your user"
        echo ""
        print_info "  Option 3: SSH in after reboot to trigger login and start services"
        echo ""

        return
    fi

    # Linux: Enable systemd user lingering
    echo ""
    print_info "IMPORTANT: Understanding Linux service persistence"
    echo ""
    print_info "By default, systemd user services only run while you're logged in."
    print_info "For a headless/remote server, this is a problem - after reboot,"
    print_info "services won't start until you SSH in."
    echo ""
    print_info "Enabling 'lingering' solves this by:"
    print_info "  - Starting your user services at BOOT (no login required)"
    print_info "  - Keeping services running even after you log out"
    echo ""

    if $DRY_RUN; then
        print_dry_run "sudo loginctl enable-linger $(whoami)"
        return
    fi

    echo -e "${BOLD}Enable services to start at boot and survive logout? [Y/n]${NC} "
    read -r response
    response=${response:-Y}

    if [[ "$response" =~ ^[Yy]$ ]] || [[ -z "$response" ]]; then
        if sudo loginctl enable-linger "$(whoami)"; then
            print_success "Lingering enabled - services will survive reboots"
            print_info "Your services will now start automatically at boot"
            print_info "No need to log in - they just work after reboot"
        else
            print_warning "Failed to enable lingering"
            print_info "Run manually: sudo loginctl enable-linger $(whoami)"
        fi
    else
        print_warning "Skipping lingering configuration"
        print_info "WARNING: Services will only run while you're logged in"
        print_info "After reboot, you must SSH in before web terminal is available"
        print_info "Enable later: sudo loginctl enable-linger $(whoami)"
    fi
}

print_completion() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}                  Installation Complete!                    ${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Display credentials (only if web terminal is available)
    if ! $SKIP_TTYD; then
        echo -e "${BOLD}${RED}IMPORTANT - Web Terminal Credentials:${NC}"
        echo -e "  Username: ${YELLOW}claude${NC}"
        echo -e "  Password: ${YELLOW}${ANYSHELL_WEB_PASSWORD}${NC}"
        echo ""
        echo -e "  ${RED}Save this password securely - you'll need it for web access!${NC}"
        echo -e "  Credentials stored in: ${CONFIG_DIR}/web-credentials"
        echo ""
    fi

    echo -e "${BOLD}Quick Start:${NC}"
    echo ""
    echo -e "  ${CYAN}1. Start a persistent session:${NC}"
    echo -e "     ${YELLOW}anyshell${NC}"
    echo ""
    echo -e "  ${CYAN}2. Connect remotely with mosh (recommended):${NC}"
    echo -e "     ${YELLOW}mosh $(whoami)@$(hostname) -- anyshell${NC}"
    echo ""
    echo -e "  ${CYAN}3. Connect via SSH:${NC}"
    echo -e "     ${YELLOW}ssh $(whoami)@$(hostname) -t 'anyshell'${NC}"
    echo ""

    if ! $SKIP_TTYD && check_tailscale && $TAILSCALE_CMD status &>/dev/null; then
        TS_HOSTNAME=$($TAILSCALE_CMD status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\.$//')
        if [[ -n "$TS_HOSTNAME" ]]; then
            echo -e "  ${CYAN}4. Connect via web browser (requires Tailscale):${NC}"
            echo -e "     ${YELLOW}https://${TS_HOSTNAME}:7681${NC}"
            echo -e "     (Login with credentials above)"
            echo ""
        fi
    fi

    echo -e "  ${CYAN}Check status:${NC}"
    echo -e "     ${YELLOW}anyshell-status${NC}"
    echo ""

    if ! $SKIP_TTYD; then
        echo -e "${BOLD}Security Notes:${NC}"
        echo "  • Web terminal requires Tailscale + password authentication"
        echo "  • Only accessible from devices on your Tailnet (not public)"
        echo "  • ttyd binds to localhost only (127.0.0.1)"
        echo "  • HTTPS encryption via Tailscale"
        echo "  • Max 2 concurrent web connections allowed"
        echo "  • Enable 2FA on your Tailscale account for extra security"
        echo ""
        echo -e "${BOLD}${YELLOW}Browser Note:${NC}"
        echo "  • Safari has a known bug with ttyd authentication"
        echo "  • Use Chrome or Firefox for the web terminal"
        echo ""
    else
        echo -e "${BOLD}${YELLOW}Note: Web terminal not available${NC}"
        echo "  To enable web terminal access later:"
        if [[ "$OS" == "macos" ]]; then
            echo "    1. Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo "    2. Install ttyd: brew install ttyd"
        else
            echo "    1. Install ttyd from GitHub releases"
        fi
        echo "    3. Re-run this installer"
        echo ""
    fi

    echo -e "${BOLD}Usage Tips:${NC}"
    echo "  • Start a long-running process and disconnect - it keeps running!"
    echo "  • Reconnect anytime to pick up where you left off"
    echo "  • Use 'anyshell <name>' to create named sessions"
    echo "  • tmux prefix is Ctrl+a (e.g., Ctrl+a d to detach)"
    echo "  • Session auto-locks after 15 minutes idle"
    echo ""
    echo -e "${BLUE}For more help: anyshell --help${NC}"
    echo ""
}

# Main installation flow
main() {
    print_banner

    if $DRY_RUN; then
        if $UPGRADE_MODE; then
            echo -e "${BOLD}${YELLOW}DRY RUN MODE (UPGRADE) - No changes will be made${NC}\n"
        else
            echo -e "${BOLD}${YELLOW}DRY RUN MODE - No changes will be made${NC}\n"
        fi
    fi

    # Detect OS
    print_step "Detecting operating system"
    detect_os

    if [[ "$OS" == "unknown" ]]; then
        print_error "Unsupported operating system"
        exit 1
    fi

    # Ensure Homebrew is in PATH (macOS)
    init_homebrew_path

    # Install packages
    print_step "Installing dependencies"
    case "$OS" in
        macos)  install_packages_macos ;;
        debian) install_packages_debian ;;
        redhat) install_packages_redhat ;;
    esac

    print_success "mosh installed"
    print_success "tmux installed"
    if ! $SKIP_TTYD; then
        print_success "ttyd installed"
    fi

    # Generate credentials before installing scripts/services (only if ttyd is available)
    if ! $SKIP_TTYD; then
        generate_credentials
    fi

    # Install scripts
    install_scripts

    # Install tmux config
    install_tmux_config

    # Install service (only if ttyd is available)
    if ! $SKIP_TTYD; then
        case "$OS" in
            macos)  install_service_macos ;;
            debian|redhat) install_service_linux ;;
        esac
    else
        print_step "Skipping web terminal service (ttyd not available)"
        print_info "Web terminal can be enabled later by installing ttyd"
    fi

    # Configure SSH server (required for mosh)
    configure_ssh_server

    # Optimize SSH for faster mosh connections
    optimize_ssh_for_mosh

    # Configure Homebrew PATH for non-interactive shells (macOS only)
    configure_homebrew_path

    # Configure firewall for mosh
    configure_firewall

    # Configure Mac sleep settings (prevent sleep for headless Mac)
    if [[ "$OS" == "macos" ]]; then
        configure_mac_sleep
    fi

    # Setup Tailscale (useful for both mosh and web terminal)
    setup_tailscale

    # Configure services to survive reboots
    if ! $SKIP_TTYD; then
        configure_boot_persistence
    fi

    # Save version file
    if ! $DRY_RUN; then
        save_version
    fi

    # Print completion message
    print_completion

    if $UPGRADE_MODE && ! $DRY_RUN; then
        echo -e "${GREEN}Successfully upgraded to version ${VERSION}${NC}"
    fi
}

# Run main
main "$@"
