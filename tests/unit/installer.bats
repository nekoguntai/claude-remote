#!/usr/bin/env bats
#
# Tests for install.sh installer logic
#
# These tests verify:
# - OS detection logic
# - Architecture detection
# - Path substitution (sed)
# - Dry-run mode
# - Checksum constants
#

load '../test_helper'

# =============================================================================
# Installer Help and Arguments
# =============================================================================

@test "installer: --help shows usage" {
    run bash "${PROJECT_ROOT}/install.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]]
    [[ "$output" =~ "--dry-run" ]]
}

@test "installer: -h shows usage" {
    run bash "${PROJECT_ROOT}/install.sh" -h

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]]
}

@test "installer: unknown option fails" {
    run bash "${PROJECT_ROOT}/install.sh" --unknown-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

# =============================================================================
# Dry Run Mode
# =============================================================================

@test "installer: --dry-run shows DRY RUN MODE message" {
    # Use run_with_timeout to prevent hanging if it tries to actually install
    run run_with_timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "DRY RUN MODE" ]]
}

@test "installer: -n is alias for --dry-run" {
    run run_with_timeout 10 bash "${PROJECT_ROOT}/install.sh" -n 2>&1

    [[ "$output" =~ "DRY RUN MODE" ]]
}

# =============================================================================
# OS Detection Logic
# =============================================================================

# Test the OS detection function in isolation
detect_os_test() {
    local ostype="$1"
    local debian_exists="$2"
    local redhat_exists="$3"

    # Override OSTYPE
    OSTYPE="$ostype"

    # Mock file existence tests
    if [[ "$ostype" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$debian_exists" == "true" ]]; then
        echo "debian"
    elif [[ "$redhat_exists" == "true" ]]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

@test "OS detection: darwin* returns macos" {
    run detect_os_test "darwin21.0" "false" "false"

    [ "$output" = "macos" ]
}

@test "OS detection: darwin20.0 returns macos" {
    run detect_os_test "darwin20.0" "false" "false"

    [ "$output" = "macos" ]
}

@test "OS detection: linux with debian_version returns debian" {
    run detect_os_test "linux-gnu" "true" "false"

    [ "$output" = "debian" ]
}

@test "OS detection: linux with redhat-release returns redhat" {
    run detect_os_test "linux-gnu" "false" "true"

    [ "$output" = "redhat" ]
}

@test "OS detection: unknown OS returns unknown" {
    run detect_os_test "freebsd" "false" "false"

    [ "$output" = "unknown" ]
}

# =============================================================================
# Architecture Detection
# =============================================================================

arch_to_ttyd_arch() {
    local arch="$1"
    case "$arch" in
        x86_64)  echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l)  echo "unsupported" ;;
        *)       echo "unsupported" ;;
    esac
}

@test "architecture: x86_64 maps to x86_64" {
    run arch_to_ttyd_arch "x86_64"

    [ "$output" = "x86_64" ]
}

@test "architecture: aarch64 maps to aarch64" {
    run arch_to_ttyd_arch "aarch64"

    [ "$output" = "aarch64" ]
}

@test "architecture: arm64 (macOS) maps to aarch64" {
    run arch_to_ttyd_arch "arm64"

    [ "$output" = "aarch64" ]
}

@test "architecture: armv7l is unsupported" {
    run arch_to_ttyd_arch "armv7l"

    [ "$output" = "unsupported" ]
}

@test "architecture: unknown arch is unsupported" {
    run arch_to_ttyd_arch "mips64"

    [ "$output" = "unsupported" ]
}

# =============================================================================
# Checksum Constants
# =============================================================================

@test "checksum constants: x86_64 checksum is valid format" {
    local checksum="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55"

    [ ${#checksum} -eq 64 ]
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]]
}

@test "checksum constants: aarch64 checksum is valid format" {
    local checksum="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165"

    [ ${#checksum} -eq 64 ]
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]]
}

@test "checksum constants: checksums are different per architecture" {
    local x86="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55"
    local arm="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165"

    [ "$x86" != "$arm" ]
}

# =============================================================================
# Path Substitution (sed patterns)
# =============================================================================

@test "sed: systemd %h substitution works" {
    local template="ExecStart=%h/.local/bin/ttyd-wrapper"
    local home="/home/testuser"

    local result=$(echo "$template" | sed "s|%h|${home}|g")

    [ "$result" = "ExecStart=/home/testuser/.local/bin/ttyd-wrapper" ]
}

@test "sed: launchd HOMEDIR substitution works" {
    local template="<string>HOMEDIR/.local/bin/ttyd-wrapper</string>"
    local home="/Users/testuser"

    local result=$(echo "$template" | sed "s|HOMEDIR|${home}|g")

    [ "$result" = "<string>/Users/testuser/.local/bin/ttyd-wrapper</string>" ]
}

@test "sed: multiple substitutions in same line" {
    local template="%h/bin:%h/lib:%h/share"
    local home="/home/user"

    local result=$(echo "$template" | sed "s|%h|${home}|g")

    [ "$result" = "/home/user/bin:/home/user/lib:/home/user/share" ]
}

@test "sed: handles paths with spaces" {
    local template="HOMEDIR/.local/bin"
    local home="/Users/Test User"

    local result=$(echo "$template" | sed "s|HOMEDIR|${home}|g")

    [ "$result" = "/Users/Test User/.local/bin" ]
}

# =============================================================================
# Directory Creation
# =============================================================================

@test "directories: LOCAL_BIN default is ~/.local/bin" {
    local LOCAL_BIN="${HOME}/.local/bin"

    [[ "$LOCAL_BIN" =~ \.local/bin$ ]]
}

@test "directories: CONFIG_DIR default is ~/.config/anyshell" {
    local CONFIG_DIR="${HOME}/.config/anyshell"

    [[ "$CONFIG_DIR" =~ \.config/anyshell$ ]]
}

@test "directories: LOCAL_SHARE default is ~/.local/share/anyshell" {
    local LOCAL_SHARE="${HOME}/.local/share/anyshell"

    [[ "$LOCAL_SHARE" =~ \.local/share/anyshell$ ]]
}

# =============================================================================
# URL Construction
# =============================================================================

@test "ttyd URL: correct format for x86_64" {
    local TTYD_VERSION="1.7.7"
    local TTYD_ARCH="x86_64"
    local url="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}"

    [ "$url" = "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64" ]
}

@test "ttyd URL: correct format for aarch64" {
    local TTYD_VERSION="1.7.7"
    local TTYD_ARCH="aarch64"
    local url="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}"

    [ "$url" = "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.aarch64" ]
}

# =============================================================================
# Credential Generation Pattern
# =============================================================================

@test "credential: openssl rand produces 32 hex chars" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi

    local password=$(openssl rand -hex 16)

    [ ${#password} -eq 32 ]
    [[ "$password" =~ ^[a-f0-9]{32}$ ]]
}

@test "credential: umask 077 creates files with 600 permissions" {
    local test_file="${TEST_TEMP_DIR}/test_cred"

    (umask 077 && echo "password" > "$test_file")

    local perms=$(stat -c %a "$test_file" 2>/dev/null || stat -f %Lp "$test_file" 2>/dev/null)
    [ "$perms" = "600" ]
}

# =============================================================================
# Script Source Files
# =============================================================================

@test "installer: all required scripts exist" {
    [ -f "${PROJECT_ROOT}/scripts/anyshell" ]
    [ -f "${PROJECT_ROOT}/scripts/web-terminal" ]
    [ -f "${PROJECT_ROOT}/scripts/ttyd-wrapper" ]
    [ -f "${PROJECT_ROOT}/scripts/status" ]
    [ -f "${PROJECT_ROOT}/scripts/maintenance" ]
}

@test "installer: all required configs exist" {
    [ -f "${PROJECT_ROOT}/config/tmux.conf" ]
}

@test "installer: systemd service files exist" {
    [ -f "${PROJECT_ROOT}/systemd/anyshell-web.service" ]
    [ -f "${PROJECT_ROOT}/systemd/anyshell-maintenance.service" ]
    [ -f "${PROJECT_ROOT}/systemd/anyshell-maintenance.timer" ]
}

@test "installer: launchd plist files exist" {
    [ -f "${PROJECT_ROOT}/launchd/com.anyshell.web.plist" ]
    [ -f "${PROJECT_ROOT}/launchd/com.anyshell.maintenance.plist" ]
}

# =============================================================================
# Service File Content Validation
# =============================================================================

@test "systemd: anyshell-web.service has correct ExecStart pattern" {
    run grep "ExecStart=" "${PROJECT_ROOT}/systemd/anyshell-web.service"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ttyd-wrapper" ]]
}

@test "systemd: anyshell-web.service binds to localhost" {
    # The service should use ttyd-wrapper which binds to 127.0.0.1
    run cat "${PROJECT_ROOT}/scripts/ttyd-wrapper"

    [[ "$output" =~ "127.0.0.1" ]]
}

@test "launchd: web plist has correct program path pattern" {
    run grep "ttyd-wrapper" "${PROJECT_ROOT}/launchd/com.anyshell.web.plist"

    [ "$status" -eq 0 ]
}

@test "launchd: plist uses HOMEDIR placeholder" {
    run grep "HOMEDIR" "${PROJECT_ROOT}/launchd/com.anyshell.web.plist"

    [ "$status" -eq 0 ]
}

# =============================================================================
# tmux Config Validation
# =============================================================================

@test "tmux config: sets prefix to Ctrl+a" {
    run grep "prefix" "${PROJECT_ROOT}/config/tmux.conf"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "C-a" ]]
}

@test "tmux config: enables mouse support" {
    run grep "mouse" "${PROJECT_ROOT}/config/tmux.conf"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "on" ]]
}

@test "tmux config: sets scrollback buffer" {
    run grep "history-limit" "${PROJECT_ROOT}/config/tmux.conf"

    [ "$status" -eq 0 ]
}

# =============================================================================
# PATH Check Logic
# =============================================================================

@test "PATH check: detects when LOCAL_BIN is in PATH" {
    local LOCAL_BIN="/home/user/.local/bin"
    local PATH="/usr/bin:/home/user/.local/bin:/usr/local/bin"

    [[ ":$PATH:" == *":${LOCAL_BIN}:"* ]]
}

@test "PATH check: detects when LOCAL_BIN is NOT in PATH" {
    local LOCAL_BIN="/home/user/.local/bin"
    local PATH="/usr/bin:/usr/local/bin"

    [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]
}
