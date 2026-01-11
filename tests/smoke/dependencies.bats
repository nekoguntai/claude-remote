#!/usr/bin/env bats
#
# Smoke tests for required dependencies and commands
#
# These tests verify that:
# - Required external commands are available
# - Common system utilities work correctly
#

load '../test_helper'

# =============================================================================
# Core System Commands
# =============================================================================

@test "dependency: bash is available" {
    run command -v bash

    [ "$status" -eq 0 ]
}

@test "dependency: bash version is 3.2+ (macOS) or 4.0+ (Linux)" {
    local version="${BASH_VERSINFO[0]}"

    # macOS ships with bash 3.2, Linux typically has 4.0+
    # Our scripts work with bash 3.2+ but prefer 4.0+
    [ "$version" -ge 3 ]
}

@test "dependency: cat is available" {
    run command -v cat

    [ "$status" -eq 0 ]
}

@test "dependency: echo is available" {
    run command -v echo

    [ "$status" -eq 0 ]
}

@test "dependency: grep is available" {
    run command -v grep

    [ "$status" -eq 0 ]
}

@test "dependency: sed is available" {
    run command -v sed

    [ "$status" -eq 0 ]
}

@test "dependency: awk is available" {
    run command -v awk

    [ "$status" -eq 0 ]
}

@test "dependency: mktemp is available" {
    run command -v mktemp

    [ "$status" -eq 0 ]
}

@test "dependency: chmod is available" {
    run command -v chmod

    [ "$status" -eq 0 ]
}

@test "dependency: mkdir is available" {
    run command -v mkdir

    [ "$status" -eq 0 ]
}

@test "dependency: cp is available" {
    run command -v cp

    [ "$status" -eq 0 ]
}

@test "dependency: mv is available" {
    run command -v mv

    [ "$status" -eq 0 ]
}

@test "dependency: rm is available" {
    run command -v rm

    [ "$status" -eq 0 ]
}

@test "dependency: stat is available" {
    run command -v stat

    [ "$status" -eq 0 ]
}

@test "dependency: wc is available" {
    run command -v wc

    [ "$status" -eq 0 ]
}

@test "dependency: sort is available" {
    run command -v sort

    [ "$status" -eq 0 ]
}

@test "dependency: head is available" {
    run command -v head

    [ "$status" -eq 0 ]
}

@test "dependency: tail is available" {
    run command -v tail

    [ "$status" -eq 0 ]
}

@test "dependency: cut is available" {
    run command -v cut

    [ "$status" -eq 0 ]
}

@test "dependency: tr is available" {
    run command -v tr

    [ "$status" -eq 0 ]
}

@test "dependency: date is available" {
    run command -v date

    [ "$status" -eq 0 ]
}

@test "dependency: touch is available" {
    run command -v touch

    [ "$status" -eq 0 ]
}

@test "dependency: du is available" {
    run command -v du

    [ "$status" -eq 0 ]
}

@test "dependency: df is available" {
    run command -v df

    [ "$status" -eq 0 ]
}

# =============================================================================
# Security-Related Commands
# =============================================================================

@test "dependency: sha256sum or shasum is available" {
    command -v sha256sum &>/dev/null || command -v shasum &>/dev/null
}

@test "dependency: openssl is available" {
    run command -v openssl

    [ "$status" -eq 0 ]
}

@test "dependency: openssl rand works" {
    run openssl rand -hex 16

    [ "$status" -eq 0 ]
    [ ${#output} -eq 32 ]
}

# =============================================================================
# Process Management Commands
# =============================================================================

@test "dependency: ps is available" {
    run command -v ps

    [ "$status" -eq 0 ]
}

@test "dependency: pgrep is available" {
    run command -v pgrep

    [ "$status" -eq 0 ]
}

@test "dependency: kill is available" {
    run command -v kill

    [ "$status" -eq 0 ]
}

@test "dependency: who is available" {
    run command -v who

    [ "$status" -eq 0 ]
}

# =============================================================================
# Network Commands (may not be present)
# =============================================================================

@test "dependency: curl is available" {
    run command -v curl

    [ "$status" -eq 0 ]
}

# =============================================================================
# Optional Application Dependencies (informational)
# =============================================================================

@test "optional: tmux is available" {
    if ! command -v tmux &>/dev/null; then
        skip "tmux not installed (will be installed by install.sh)"
    fi
    run command -v tmux
    [ "$status" -eq 0 ]
}

@test "optional: mosh is available" {
    if ! command -v mosh &>/dev/null; then
        skip "mosh not installed (will be installed by install.sh)"
    fi
    run command -v mosh
    [ "$status" -eq 0 ]
}

@test "optional: ttyd is available" {
    if ! command -v ttyd &>/dev/null; then
        skip "ttyd not installed (will be installed by install.sh)"
    fi
    run command -v ttyd
    [ "$status" -eq 0 ]
}

@test "optional: tailscale is available" {
    if ! command -v tailscale &>/dev/null; then
        skip "tailscale not installed (optional)"
    fi
    run command -v tailscale
    [ "$status" -eq 0 ]
}

# =============================================================================
# Test Infrastructure
# =============================================================================

@test "test infra: bats is running" {
    [ -n "$BATS_VERSION" ] || [ -n "$BATS_TEST_FILENAME" ]
}

@test "test infra: TEST_TEMP_DIR is set" {
    [ -n "$TEST_TEMP_DIR" ]
}

@test "test infra: TEST_TEMP_DIR is writable" {
    touch "${TEST_TEMP_DIR}/write_test"
    [ -f "${TEST_TEMP_DIR}/write_test" ]
}

@test "test infra: PROJECT_ROOT is set correctly" {
    [ -f "${PROJECT_ROOT}/install.sh" ]
}

@test "test infra: SCRIPTS_DIR points to scripts" {
    [ -d "${SCRIPTS_DIR}" ]
    [ -f "${SCRIPTS_DIR}/anyshell" ]
}
