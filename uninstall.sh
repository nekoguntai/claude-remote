#!/usr/bin/env bash
#
# Claude Remote - Uninstallation Script
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

LOCAL_BIN="${HOME}/.local/bin"
LOCAL_SHARE="${HOME}/.local/share/claude-remote"
CONFIG_DIR="${HOME}/.config/claude-remote"

print_step() {
    echo -e "\n${BOLD}${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

echo -e "${BOLD}${RED}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║               Claude Remote Uninstaller                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Confirm uninstall
read -p "Are you sure you want to uninstall Claude Remote? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Stop and remove services
print_step "Stopping services"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if [[ -f "${HOME}/Library/LaunchAgents/com.claude.web.plist" ]]; then
        launchctl unload "${HOME}/Library/LaunchAgents/com.claude.web.plist" 2>/dev/null || true
        rm -f "${HOME}/Library/LaunchAgents/com.claude.web.plist"
        print_success "Removed launchd service"
    fi
else
    # Linux
    if [[ -f "${HOME}/.config/systemd/user/claude-web.service" ]]; then
        systemctl --user stop claude-web.service 2>/dev/null || true
        systemctl --user disable claude-web.service 2>/dev/null || true
        rm -f "${HOME}/.config/systemd/user/claude-web.service"
        systemctl --user daemon-reload
        print_success "Removed systemd service"
    fi
fi

# Remove scripts
print_step "Removing scripts"

SCRIPTS=("claude-session" "web-terminal" "ttyd-wrapper" "claude-status")
for script in "${SCRIPTS[@]}"; do
    if [[ -f "${LOCAL_BIN}/${script}" ]]; then
        rm -f "${LOCAL_BIN}/${script}"
        print_success "Removed ${script}"
    fi
done

# Remove data directory
if [[ -d "$LOCAL_SHARE" ]]; then
    rm -rf "$LOCAL_SHARE"
    print_success "Removed ${LOCAL_SHARE}"
fi

# Handle tmux config
print_step "Handling configuration"

if [[ -f "${HOME}/.tmux.conf" ]]; then
    # Check if there's a backup
    BACKUP=$(ls -t "${HOME}/.tmux.conf.backup."* 2>/dev/null | head -1)
    if [[ -n "$BACKUP" ]]; then
        read -p "Restore previous tmux.conf from backup? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "$BACKUP" "${HOME}/.tmux.conf"
            print_success "Restored tmux.conf from backup"
        else
            print_info "Left current tmux.conf in place"
        fi
    else
        read -p "Remove tmux.conf? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "${HOME}/.tmux.conf"
            print_success "Removed tmux.conf"
        else
            print_info "Left tmux.conf in place"
        fi
    fi
fi

# Tailscale Serve
print_step "Tailscale configuration"

if command -v tailscale &> /dev/null; then
    read -p "Disable Tailscale Serve for port 7681? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        tailscale serve off 2>/dev/null || true
        print_success "Disabled Tailscale Serve"
    fi
fi

# Note about packages
print_step "Installed packages"
print_info "The following packages were NOT removed (you may want to keep them):"
echo "        - mosh"
echo "        - tmux"
echo "        - ttyd"
print_info "Remove them manually if desired"

echo ""
echo -e "${GREEN}${BOLD}Uninstallation complete!${NC}"
echo ""
