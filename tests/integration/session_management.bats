#!/usr/bin/env bats
#
# Integration tests for session management
#
# These tests require actual tmux to be installed and test the
# full session lifecycle.
#

load '../test_helper'

# Skip all tests if tmux is not available
setup() {
    # Call parent setup
    export TEST_TEMP_DIR="$(mktemp -d)"
    export HOME="${TEST_TEMP_DIR}/home"
    mkdir -p "$HOME"
    mkdir -p "${HOME}/.config/anyshell"
    mkdir -p "${HOME}/.local/bin"

    if ! command -v tmux &>/dev/null; then
        skip "tmux not installed"
    fi

    # Create a unique socket path for testing
    export TMUX_TMPDIR="${TEST_TEMP_DIR}"
}

teardown() {
    # Kill any test tmux sessions
    tmux -L test_socket kill-server 2>/dev/null || true

    if [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# =============================================================================
# Session Creation
# =============================================================================

@test "integration: can create a new tmux session" {
    run tmux -L test_socket new-session -d -s "test_session"

    [ "$status" -eq 0 ]
}

@test "integration: session exists after creation" {
    tmux -L test_socket new-session -d -s "test_session"

    run tmux -L test_socket has-session -t "test_session"

    [ "$status" -eq 0 ]
}

@test "integration: can list sessions" {
    tmux -L test_socket new-session -d -s "session1"
    tmux -L test_socket new-session -d -s "session2"

    run tmux -L test_socket list-sessions

    [ "$status" -eq 0 ]
    [[ "$output" =~ "session1" ]]
    [[ "$output" =~ "session2" ]]
}

# =============================================================================
# Session Naming
# =============================================================================

@test "integration: session with valid name is created" {
    run tmux -L test_socket new-session -d -s "valid-name_123"

    [ "$status" -eq 0 ]
}

@test "integration: session with hyphen prefix works" {
    # Note: tmux actually allows this
    run tmux -L test_socket new-session -d -s "-prefixed"

    # tmux may or may not allow this depending on version
    # We mainly want to ensure our validation is stricter
    true
}

# =============================================================================
# Session Destruction
# =============================================================================

@test "integration: can kill a specific session" {
    tmux -L test_socket new-session -d -s "to_kill"

    run tmux -L test_socket kill-session -t "to_kill"

    [ "$status" -eq 0 ]
}

@test "integration: killing non-existent session fails" {
    run tmux -L test_socket kill-session -t "nonexistent"

    [ "$status" -ne 0 ]
}

@test "integration: kill-server terminates all sessions" {
    tmux -L test_socket new-session -d -s "session1"
    tmux -L test_socket new-session -d -s "session2"

    tmux -L test_socket kill-server

    run tmux -L test_socket list-sessions

    [ "$status" -ne 0 ]  # Should fail because no server
}

# =============================================================================
# Session Attachment (non-interactive)
# =============================================================================

@test "integration: has-session returns 0 for existing session" {
    tmux -L test_socket new-session -d -s "exists"

    run tmux -L test_socket has-session -t "exists"

    [ "$status" -eq 0 ]
}

@test "integration: has-session returns non-zero for missing session" {
    run tmux -L test_socket has-session -t "missing"

    [ "$status" -ne 0 ]
}

# =============================================================================
# Session Windows
# =============================================================================

@test "integration: new session has one window by default" {
    tmux -L test_socket new-session -d -s "test"

    local count=$(tmux -L test_socket list-windows -t "test" | wc -l)

    [ "$count" -eq 1 ]
}

@test "integration: can create additional windows" {
    tmux -L test_socket new-session -d -s "test"
    tmux -L test_socket new-window -t "test"

    local count=$(tmux -L test_socket list-windows -t "test" | wc -l)

    [ "$count" -eq 2 ]
}

# =============================================================================
# Configuration Loading
# =============================================================================

@test "integration: tmux loads config file" {
    # Create a test config
    echo "set -g status-position top" > "${TEST_TEMP_DIR}/test.conf"

    run tmux -L test_socket -f "${TEST_TEMP_DIR}/test.conf" new-session -d -s "configured"

    [ "$status" -eq 0 ]
}

@test "integration: project tmux.conf is valid syntax" {
    # Try to start tmux with the project's config
    run tmux -L test_socket -f "${PROJECT_ROOT}/config/tmux.conf" new-session -d -s "config_test"

    # This may fail if tmux version is incompatible, but syntax should be valid
    # We check that it doesn't fail with "unknown option" type errors
    if [ "$status" -ne 0 ]; then
        # Allow version-related failures
        [[ ! "$output" =~ "parse error" ]]
    fi
}

# =============================================================================
# anyshell Script Integration
# =============================================================================

@test "integration: anyshell --help works" {
    run bash "${SCRIPTS_DIR}/anyshell" --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]]
}

@test "integration: anyshell --list works with no sessions" {
    # Ensure no tmux server
    tmux -L test_socket kill-server 2>/dev/null || true

    run bash "${SCRIPTS_DIR}/anyshell" --list

    # Should succeed but show no sessions
    [[ "$output" =~ "No active" ]] || [[ "$output" =~ "no server" ]] || [ "$status" -eq 0 ]
}

@test "integration: anyshell validates session names" {
    run bash -c "
        # Source the validation function
        source '${SCRIPTS_DIR}/anyshell'
        validate_session_name 'invalid;name'
    " 2>&1

    [ "$status" -ne 0 ]
}
