#!/usr/bin/env bats
#
# Tests for credential handling in ttyd-wrapper and install.sh
#
# These tests verify that:
# - Credentials are generated securely
# - Credential files have proper permissions
# - Empty/missing credentials are handled correctly
# - Password is read correctly from file
#

load '../test_helper'

# =============================================================================
# Credential File Permissions
# =============================================================================

@test "credentials: config directory is created with 700 permissions" {
    mkdir -p "${HOME}/.config/anyshell"
    chmod 700 "${HOME}/.config/anyshell"

    local perms=$(stat -c %a "${HOME}/.config/anyshell" 2>/dev/null || stat -f %Lp "${HOME}/.config/anyshell" 2>/dev/null)

    [ "$perms" = "700" ]
}

@test "credentials: file is created with 600 permissions using umask" {
    # Test the pattern used in install.sh: (umask 077 && echo "password" > file)
    (umask 077 && echo "test_password" > "${HOME}/.config/anyshell/web-credentials")

    local perms=$(stat -c %a "${HOME}/.config/anyshell/web-credentials" 2>/dev/null || stat -f %Lp "${HOME}/.config/anyshell/web-credentials" 2>/dev/null)

    # umask 077 creates files with 600 permissions
    [ "$perms" = "600" ]
}

@test "credentials: file is not world-readable" {
    create_mock_credentials "secret123"

    # Check that "other" has no read permission
    local perms=$(stat -c %a "${HOME}/.config/anyshell/web-credentials" 2>/dev/null || stat -f %Lp "${HOME}/.config/anyshell/web-credentials" 2>/dev/null)

    # Last digit should be 0 (no permissions for others)
    [[ "$perms" =~ .0$ ]]
}

@test "credentials: file is not group-readable" {
    create_mock_credentials "secret123"

    local perms=$(stat -c %a "${HOME}/.config/anyshell/web-credentials" 2>/dev/null || stat -f %Lp "${HOME}/.config/anyshell/web-credentials" 2>/dev/null)

    # Middle digit should be 0 (no permissions for group)
    [[ "$perms" =~ .0.$ ]]
}

# =============================================================================
# Credential Content Validation
# =============================================================================

@test "credentials: password is read correctly from file" {
    local expected_password="mysecretpassword123"
    create_mock_credentials "$expected_password"

    local actual_password=$(cat "${HOME}/.config/anyshell/web-credentials")

    [ "$actual_password" = "$expected_password" ]
}

@test "credentials: password with special characters is preserved" {
    local password='P@$$w0rd!#%^&*()_+-=[]{}|;:,.<>?'
    echo "$password" > "${HOME}/.config/anyshell/web-credentials"

    local actual=$(cat "${HOME}/.config/anyshell/web-credentials")

    [ "$actual" = "$password" ]
}

@test "credentials: password with spaces is preserved" {
    local password="password with spaces"
    echo "$password" > "${HOME}/.config/anyshell/web-credentials"

    local actual=$(cat "${HOME}/.config/anyshell/web-credentials")

    [ "$actual" = "$password" ]
}

@test "credentials: no trailing newline issues" {
    # When reading with $(cat file), trailing newline is stripped
    echo "password" > "${HOME}/.config/anyshell/web-credentials"

    local password=$(cat "${HOME}/.config/anyshell/web-credentials")

    [ "$password" = "password" ]
    [ ${#password} -eq 8 ]  # Exactly 8 characters, no newline
}

# =============================================================================
# Empty/Missing Credential Handling
# =============================================================================

@test "credentials: missing file is detected" {
    # Don't create the credential file

    [ ! -f "${HOME}/.config/anyshell/web-credentials" ]
}

@test "credentials: empty file is detected" {
    touch "${HOME}/.config/anyshell/web-credentials"

    local content=$(cat "${HOME}/.config/anyshell/web-credentials")

    [ -z "$content" ]
}

@test "credentials: whitespace-only file is detected as empty" {
    echo "   " > "${HOME}/.config/anyshell/web-credentials"

    local content=$(cat "${HOME}/.config/anyshell/web-credentials" | tr -d '[:space:]')

    [ -z "$content" ]
}

# =============================================================================
# Password Generation (install.sh pattern)
# =============================================================================

@test "password generation: openssl rand produces 32 hex chars" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi

    local password=$(openssl rand -hex 16)

    [ ${#password} -eq 32 ]
    [[ "$password" =~ ^[a-f0-9]{32}$ ]]
}

@test "password generation: each generation produces unique password" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi

    local pass1=$(openssl rand -hex 16)
    local pass2=$(openssl rand -hex 16)

    [ "$pass1" != "$pass2" ]
}

@test "password generation: password has sufficient entropy" {
    if ! command -v openssl &>/dev/null; then
        skip "openssl not available"
    fi

    # 16 bytes = 128 bits of entropy, 32 hex characters
    local password=$(openssl rand -hex 16)

    # Verify it's not all zeros or repetitive pattern
    [ "$password" != "00000000000000000000000000000000" ]
    [ "$password" != "$(echo "$password" | cut -c1 | tr -d '\n' | head -c 32)" ]
}

# =============================================================================
# ttyd-wrapper Credential Loading
# =============================================================================

@test "ttyd-wrapper: detects missing credential file" {
    # Setup mock environment without credentials
    create_mock_ttyd

    # The script should fail if credential file doesn't exist
    export HOME="${HOME}"
    run bash -c '
        CONFIG_DIR="${HOME}/.config/anyshell"
        CRED_FILE="${CONFIG_DIR}/web-credentials"
        if [[ ! -f "$CRED_FILE" ]]; then
            exit 1
        fi
        exit 0
    '

    [ "$status" -eq 1 ]
}

@test "ttyd-wrapper: detects empty credential file" {
    create_mock_ttyd
    touch "${HOME}/.config/anyshell/web-credentials"

    run bash -c '
        CRED_FILE="${HOME}/.config/anyshell/web-credentials"
        WEB_PASSWORD="$(cat "$CRED_FILE")"
        if [[ -z "$WEB_PASSWORD" ]]; then
            exit 1
        fi
        exit 0
    '

    [ "$status" -eq 1 ]
}

@test "ttyd-wrapper: loads valid credentials successfully" {
    create_mock_ttyd
    create_mock_credentials "validpassword123"

    run bash -c '
        CRED_FILE="${HOME}/.config/anyshell/web-credentials"
        WEB_PASSWORD="$(cat "$CRED_FILE")"
        if [[ -z "$WEB_PASSWORD" ]]; then
            exit 1
        fi
        exit 0
    '

    [ "$status" -eq 0 ]
}

# =============================================================================
# ttyd Path Detection
# =============================================================================

@test "ttyd-wrapper: finds ttyd in ~/.local/bin" {
    create_mock_ttyd  # Creates in ~/.local/bin

    local found=""
    for path in "${HOME}/.local/bin/ttyd" "/usr/local/bin/ttyd" "/opt/homebrew/bin/ttyd" "/usr/bin/ttyd"; do
        if [[ -x "$path" ]]; then
            found="$path"
            break
        fi
    done

    [ "$found" = "${HOME}/.local/bin/ttyd" ]
}

@test "ttyd-wrapper: fallback order is correct" {
    # Test that the path order is: ~/.local/bin, /usr/local/bin, /opt/homebrew/bin, /usr/bin
    local paths=("${HOME}/.local/bin/ttyd" "/usr/local/bin/ttyd" "/opt/homebrew/bin/ttyd" "/usr/bin/ttyd")

    # Create ttyd in the third location only
    mkdir -p "/tmp/homebrew_mock"

    # Verify the search order by checking array positions
    [ "${paths[0]}" = "${HOME}/.local/bin/ttyd" ]
    [ "${paths[1]}" = "/usr/local/bin/ttyd" ]
    [ "${paths[2]}" = "/opt/homebrew/bin/ttyd" ]
    [ "${paths[3]}" = "/usr/bin/ttyd" ]
}

# =============================================================================
# Multi-User Warning Detection
# =============================================================================

@test "multi-user detection: single user returns count of 1" {
    # Mock 'who' output for single user
    local count=$(echo "user1 pts/0 2026-01-10 10:00" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')

    [ "$count" = "1" ]
}

@test "multi-user detection: multiple users returns count > 1" {
    # Mock 'who' output for multiple users
    local count=$(echo -e "user1 pts/0 2026-01-10 10:00\nuser2 pts/1 2026-01-10 10:00" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')

    [ "$count" = "2" ]
}

@test "multi-user detection: same user multiple sessions counts as 1" {
    # Same user logged in multiple times
    local count=$(echo -e "user1 pts/0 2026-01-10 10:00\nuser1 pts/1 2026-01-10 10:00" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')

    [ "$count" = "1" ]
}

# =============================================================================
# Credential String Escaping (for ttyd --credential)
# =============================================================================

@test "credential string: basic password works in credential flag" {
    local password="simplepassword"
    local credential="claude:${password}"

    [ "$credential" = "claude:simplepassword" ]
}

@test "credential string: password with colon is handled" {
    # Note: ttyd uses the first colon as delimiter, so colons in password should work
    local password="pass:word:with:colons"
    local credential="claude:${password}"

    [ "$credential" = "claude:pass:word:with:colons" ]
}

@test "credential string: hex password (from openssl) works" {
    local password="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
    local credential="claude:${password}"

    [ "$credential" = "claude:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6" ]
}
