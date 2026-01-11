#!/bin/bash
#
# Docker integration test script
# Runs inside the container to test the full installation flow
#

# Don't use set -e - we want to continue even if tests fail
# set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

echo "=============================================="
echo "  Anyshell Docker Integration Tests"
echo "=============================================="
echo ""

# Detect OS
if [ -f /etc/debian_version ]; then
    OS="debian"
    PKG_MGR="apt"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    PKG_MGR="dnf"
else
    OS="unknown"
    PKG_MGR="unknown"
fi
info "Detected OS: $OS (package manager: $PKG_MGR)"

# =============================================================================
# Test 1: Dry run completes without error
# =============================================================================
echo ""
echo "--- Test: Dry run completes without error ---"
if ./install.sh --dry-run 2>&1 | grep -q "DRY RUN MODE"; then
    pass "Dry run shows DRY RUN MODE message"
else
    fail "Dry run did not show DRY RUN MODE message"
fi

# =============================================================================
# Test 2: Dry run detects correct OS
# =============================================================================
echo ""
echo "--- Test: Dry run detects correct OS ---"
DRY_OUTPUT=$(./install.sh --dry-run 2>&1)
if echo "$DRY_OUTPUT" | grep -q "Detected OS: $OS"; then
    pass "Correctly detected OS as $OS"
else
    fail "Did not detect OS as $OS"
    echo "Output was:"
    echo "$DRY_OUTPUT" | grep -i "detect"
fi

# =============================================================================
# Test 3: Dry run shows package manager commands
# =============================================================================
echo ""
echo "--- Test: Dry run shows package manager commands ---"
if echo "$DRY_OUTPUT" | grep -qi "$PKG_MGR"; then
    pass "Shows $PKG_MGR commands"
else
    fail "Did not show $PKG_MGR commands"
fi

# =============================================================================
# Test 4: Dry run shows ttyd download
# =============================================================================
echo ""
echo "--- Test: Dry run shows ttyd download ---"
if echo "$DRY_OUTPUT" | grep -q "ttyd"; then
    pass "Shows ttyd installation"
else
    fail "Did not show ttyd installation"
fi

# =============================================================================
# Test 5: Dry run shows credential generation
# =============================================================================
echo ""
echo "--- Test: Dry run shows credential generation ---"
if echo "$DRY_OUTPUT" | grep -qi "credential\|password"; then
    pass "Shows credential generation"
else
    fail "Did not show credential generation"
fi

# =============================================================================
# Test 6: Dry run shows systemd service setup
# =============================================================================
echo ""
echo "--- Test: Dry run shows systemd service setup ---"
if echo "$DRY_OUTPUT" | grep -qi "systemd\|systemctl\|service"; then
    pass "Shows systemd service setup"
else
    fail "Did not show systemd service setup"
fi

# =============================================================================
# Test 7: Full installation (actual install)
# =============================================================================
echo ""
echo "--- Test: Full installation ---"
info "Running actual installation..."

if ./install.sh 2>&1; then
    pass "Installation completed without error"
else
    fail "Installation failed"
fi

# =============================================================================
# Test 8: Verify tmux is installed
# =============================================================================
echo ""
echo "--- Test: tmux is installed ---"
if command -v tmux &>/dev/null; then
    pass "tmux is installed"
else
    fail "tmux is not installed"
fi

# =============================================================================
# Test 9: Verify mosh is installed
# =============================================================================
echo ""
echo "--- Test: mosh is installed ---"
if command -v mosh &>/dev/null; then
    pass "mosh is installed"
else
    fail "mosh is not installed"
fi

# =============================================================================
# Test 10: Verify ttyd is installed
# =============================================================================
echo ""
echo "--- Test: ttyd is installed ---"
if [ -x "$HOME/.local/bin/ttyd" ]; then
    pass "ttyd is installed at ~/.local/bin/ttyd"
else
    fail "ttyd is not installed at ~/.local/bin/ttyd"
fi

# =============================================================================
# Test 11: Verify scripts are installed
# =============================================================================
echo ""
echo "--- Test: Scripts are installed ---"
SCRIPTS_OK=true
for script in anyshell web-terminal ttyd-wrapper anyshell-status anyshell-maintenance; do
    if [ -x "$HOME/.local/bin/$script" ]; then
        pass "Script $script is installed and executable"
    else
        fail "Script $script is missing or not executable"
        SCRIPTS_OK=false
    fi
done

# =============================================================================
# Test 12: Verify config directory exists
# =============================================================================
echo ""
echo "--- Test: Config directory exists ---"
if [ -d "$HOME/.config/anyshell" ]; then
    pass "Config directory exists"
else
    fail "Config directory missing"
fi

# =============================================================================
# Test 13: Verify credentials file exists with correct permissions
# =============================================================================
echo ""
echo "--- Test: Credentials file has correct permissions ---"
CRED_FILE="$HOME/.config/anyshell/web-credentials"
if [ -f "$CRED_FILE" ]; then
    PERMS=$(stat -c %a "$CRED_FILE" 2>/dev/null || stat -f %Lp "$CRED_FILE" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
        pass "Credentials file has 600 permissions"
    else
        fail "Credentials file has wrong permissions: $PERMS (expected 600)"
    fi
else
    fail "Credentials file missing"
fi

# =============================================================================
# Test 14: Verify tmux config is installed
# =============================================================================
echo ""
echo "--- Test: tmux config is installed ---"
if [ -f "$HOME/.tmux.conf" ]; then
    pass "tmux.conf is installed to ~/.tmux.conf"
else
    fail "tmux.conf is missing"
fi

# =============================================================================
# Test 15: Verify systemd service files are installed
# =============================================================================
echo ""
echo "--- Test: Systemd service files are installed ---"
SYSTEMD_DIR="$HOME/.config/systemd/user"
if [ -f "$SYSTEMD_DIR/anyshell-web.service" ]; then
    pass "anyshell-web.service is installed"
else
    fail "anyshell-web.service is missing"
fi

if [ -f "$SYSTEMD_DIR/anyshell-maintenance.service" ]; then
    pass "anyshell-maintenance.service is installed"
else
    fail "anyshell-maintenance.service is missing"
fi

if [ -f "$SYSTEMD_DIR/anyshell-maintenance.timer" ]; then
    pass "anyshell-maintenance.timer is installed"
else
    fail "anyshell-maintenance.timer is missing"
fi

# =============================================================================
# Test 16: Verify ttyd checksum
# =============================================================================
echo ""
echo "--- Test: ttyd binary checksum verification ---"
TTYD_BIN="$HOME/.local/bin/ttyd"
if [ -x "$TTYD_BIN" ]; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            EXPECTED="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55"
            ;;
        aarch64|arm64)
            EXPECTED="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165"
            ;;
        *)
            EXPECTED=""
            ;;
    esac

    if [ -n "$EXPECTED" ]; then
        ACTUAL=$(sha256sum "$TTYD_BIN" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$TTYD_BIN" 2>/dev/null | cut -d' ' -f1)
        if [ "$ACTUAL" = "$EXPECTED" ]; then
            pass "ttyd checksum verified"
        else
            fail "ttyd checksum mismatch"
            echo "  Expected: $EXPECTED"
            echo "  Actual:   $ACTUAL"
        fi
    else
        info "Skipping checksum verification for architecture: $ARCH"
    fi
else
    fail "ttyd binary not found for checksum verification"
fi

# =============================================================================
# Test 17: Test anyshell help
# =============================================================================
echo ""
echo "--- Test: anyshell --help works ---"
if "$HOME/.local/bin/anyshell" --help 2>&1 | grep -qi "usage\|session"; then
    pass "anyshell --help works"
else
    fail "anyshell --help failed"
fi

# =============================================================================
# Test 18: Test status command
# =============================================================================
echo ""
echo "--- Test: anyshell-status command works ---"
if "$HOME/.local/bin/anyshell-status" 2>&1; then
    pass "anyshell-status command works"
else
    fail "anyshell-status command failed"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo "  Test Summary"
echo "=============================================="
echo -e "  ${GREEN}Passed${NC}: $TESTS_PASSED"
echo -e "  ${RED}Failed${NC}: $TESTS_FAILED"
echo "=============================================="

if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
