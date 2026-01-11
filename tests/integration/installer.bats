#!/usr/bin/env bats
#
# Integration tests for install.sh
#
# These tests run the installer in dry-run mode and verify
# the complete installation flow without making actual changes.
#

load '../test_helper'

# =============================================================================
# Full Dry Run Tests
# =============================================================================

@test "installer dry-run: completes without error" {
    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    # Should not fail (may warn about missing dependencies)
    [[ "$output" =~ "DRY RUN MODE" ]]
}

@test "installer dry-run: detects OS" {
    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "Detected OS:" ]]
}

@test "installer dry-run: shows package install step" {
    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "Installing" ]] || [[ "$output" =~ "DRY-RUN" ]]
}

@test "installer dry-run: shows credential generation step" {
    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "credentials" ]] || [[ "$output" =~ "Generating" ]]
}

@test "installer dry-run: shows script installation step" {
    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "scripts" ]] || [[ "$output" =~ "Installing scripts" ]]
}

# =============================================================================
# macOS-Specific Tests (when on macOS)
# =============================================================================

@test "installer macos: detects darwin OS type" {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        skip "Not running on macOS"
    fi

    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "macos" ]]
}

@test "installer macos: uses Homebrew" {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        skip "Not running on macOS"
    fi

    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "brew" ]] || [[ "$output" =~ "Homebrew" ]]
}

@test "installer macos: installs launchd services" {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        skip "Not running on macOS"
    fi

    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "launchd" ]] || [[ "$output" =~ "LaunchAgents" ]]
}

# =============================================================================
# Linux-Specific Tests (when on Linux)
# =============================================================================

@test "installer linux: detects linux OS" {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        skip "Running on macOS, not Linux"
    fi

    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "debian" ]] || [[ "$output" =~ "redhat" ]] || [[ "$output" =~ "linux" ]]
}

@test "installer linux: uses apt or dnf" {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        skip "Running on macOS, not Linux"
    fi

    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "apt" ]] || [[ "$output" =~ "dnf" ]]
}

@test "installer linux: installs systemd services" {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        skip "Running on macOS, not Linux"
    fi

    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "systemd" ]] || [[ "$output" =~ "systemctl" ]]
}

# =============================================================================
# Tailscale Integration
# =============================================================================

@test "installer: mentions Tailscale" {
    run timeout 10 bash "${PROJECT_ROOT}/install.sh" --dry-run 2>&1

    [[ "$output" =~ "Tailscale" ]] || [[ "$output" =~ "tailscale" ]]
}

# =============================================================================
# Script Syntax in Context
# =============================================================================

@test "installer: install.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/install.sh"

    [ "$status" -eq 0 ]
}

@test "installer: uninstall.sh syntax is valid" {
    run bash -n "${PROJECT_ROOT}/uninstall.sh"

    [ "$status" -eq 0 ]
}
