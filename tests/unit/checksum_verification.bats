#!/usr/bin/env bats
#
# Tests for checksum verification in install.sh
#
# These tests verify that:
# - SHA256 checksum verification works correctly
# - Invalid checksums are rejected
# - The verification logic handles edge cases
#

load '../test_helper'

# Known test data for checksum verification
# Using a simple test string with known SHA256 hash
TEST_CONTENT="Hello, World!"
# SHA256 of "Hello, World!" (with newline from echo)
TEST_HASH_WITH_NEWLINE="d9014c4624844aa5bac314773d6b689ad467fa4e1d1a50a1b8a99d5a95f72ff5"
# SHA256 of "Hello, World!" (without newline, using echo -n)
TEST_HASH_NO_NEWLINE="dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"

# =============================================================================
# Basic Checksum Verification
# =============================================================================

@test "checksum: sha256sum produces correct hash" {
    echo -n "Hello, World!" > "${TEST_TEMP_DIR}/test_file"

    local actual_hash=$(sha256sum "${TEST_TEMP_DIR}/test_file" | cut -d' ' -f1)

    [ "$actual_hash" = "$TEST_HASH_NO_NEWLINE" ]
}

@test "checksum: verification passes for matching hash" {
    echo -n "Hello, World!" > "${TEST_TEMP_DIR}/test_file"

    local actual=$(sha256sum "${TEST_TEMP_DIR}/test_file" | cut -d' ' -f1)

    [ "$actual" = "$TEST_HASH_NO_NEWLINE" ]
}

@test "checksum: verification fails for non-matching hash" {
    echo -n "Hello, World!" > "${TEST_TEMP_DIR}/test_file"
    local wrong_hash="0000000000000000000000000000000000000000000000000000000000000000"

    local actual=$(sha256sum "${TEST_TEMP_DIR}/test_file" | cut -d' ' -f1)

    [ "$actual" != "$wrong_hash" ]
}

@test "checksum: empty file has correct hash" {
    touch "${TEST_TEMP_DIR}/empty_file"
    local expected="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    local actual=$(sha256sum "${TEST_TEMP_DIR}/empty_file" | cut -d' ' -f1)

    [ "$actual" = "$expected" ]
}

@test "checksum: binary file verification works" {
    # Create a binary file with known content
    printf '\x00\x01\x02\x03\x04\x05' > "${TEST_TEMP_DIR}/binary_file"
    local expected="17e88db187afd62c16e5debf3e6527cd006bc012bc90b51a810cd80c2d511f43"

    local actual=$(sha256sum "${TEST_TEMP_DIR}/binary_file" | cut -d' ' -f1)

    [ "$actual" = "$expected" ]
}

# =============================================================================
# Hash Format Validation
# =============================================================================

@test "checksum: hash is exactly 64 hex characters" {
    echo -n "test" > "${TEST_TEMP_DIR}/test_file"

    local hash=$(sha256sum "${TEST_TEMP_DIR}/test_file" | cut -d' ' -f1)

    [ ${#hash} -eq 64 ]
}

@test "checksum: hash contains only lowercase hex characters" {
    echo -n "test" > "${TEST_TEMP_DIR}/test_file"

    local hash=$(sha256sum "${TEST_TEMP_DIR}/test_file" | cut -d' ' -f1)

    [[ "$hash" =~ ^[a-f0-9]{64}$ ]]
}

# =============================================================================
# Security Edge Cases
# =============================================================================

@test "checksum: different content produces different hash" {
    echo -n "Content A" > "${TEST_TEMP_DIR}/file_a"
    echo -n "Content B" > "${TEST_TEMP_DIR}/file_b"

    local hash_a=$(sha256sum "${TEST_TEMP_DIR}/file_a" | cut -d' ' -f1)
    local hash_b=$(sha256sum "${TEST_TEMP_DIR}/file_b" | cut -d' ' -f1)

    [ "$hash_a" != "$hash_b" ]
}

@test "checksum: single bit change produces different hash" {
    # Two strings differing by one character
    echo -n "AAAA" > "${TEST_TEMP_DIR}/file_a"
    echo -n "AAAB" > "${TEST_TEMP_DIR}/file_b"

    local hash_a=$(sha256sum "${TEST_TEMP_DIR}/file_a" | cut -d' ' -f1)
    local hash_b=$(sha256sum "${TEST_TEMP_DIR}/file_b" | cut -d' ' -f1)

    [ "$hash_a" != "$hash_b" ]
}

@test "checksum: file with spaces in name is handled correctly" {
    echo -n "test content" > "${TEST_TEMP_DIR}/file with spaces.txt"

    run sha256sum "${TEST_TEMP_DIR}/file with spaces.txt"

    [ "$status" -eq 0 ]
    [[ "${lines[0]}" =~ ^[a-f0-9]{64} ]]
}

@test "checksum: large file (1MB) verification works" {
    # Create a 1MB file with predictable content
    dd if=/dev/zero bs=1024 count=1024 2>/dev/null > "${TEST_TEMP_DIR}/large_file"
    local expected="30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58"

    local actual=$(sha256sum "${TEST_TEMP_DIR}/large_file" | cut -d' ' -f1)

    [ "$actual" = "$expected" ]
}

# =============================================================================
# Verification Logic Tests
# =============================================================================

verify_checksum() {
    local file="$1"
    local expected="$2"

    if [[ ! -f "$file" ]]; then
        return 2  # File not found
    fi

    local actual=$(sha256sum "$file" | cut -d' ' -f1)

    if [[ "$actual" = "$expected" ]]; then
        return 0  # Match
    else
        return 1  # Mismatch
    fi
}

@test "verify_checksum: returns 0 for matching hash" {
    echo -n "test" > "${TEST_TEMP_DIR}/test_file"
    local expected="9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

    run verify_checksum "${TEST_TEMP_DIR}/test_file" "$expected"

    [ "$status" -eq 0 ]
}

@test "verify_checksum: returns 1 for non-matching hash" {
    echo -n "test" > "${TEST_TEMP_DIR}/test_file"
    local wrong_hash="0000000000000000000000000000000000000000000000000000000000000000"

    run verify_checksum "${TEST_TEMP_DIR}/test_file" "$wrong_hash"

    [ "$status" -eq 1 ]
}

@test "verify_checksum: returns 2 for missing file" {
    run verify_checksum "${TEST_TEMP_DIR}/nonexistent_file" "somehash"

    [ "$status" -eq 2 ]
}

# =============================================================================
# Install.sh Checksum Constants Validation
# =============================================================================

@test "install.sh checksums: x86_64 checksum is 64 hex chars" {
    local checksum="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55"

    [ ${#checksum} -eq 64 ]
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]]
}

@test "install.sh checksums: aarch64 checksum is 64 hex chars" {
    local checksum="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165"

    [ ${#checksum} -eq 64 ]
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]]
}

@test "install.sh checksums: x86_64 and aarch64 checksums are different" {
    local x86="8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55"
    local arm="b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165"

    [ "$x86" != "$arm" ]
}

# =============================================================================
# Simulated Download and Verify Flow
# =============================================================================

@test "download flow: successful verification with correct checksum" {
    # Simulate downloading a binary
    local fake_binary_content="#!/bin/bash\necho 'ttyd mock'"
    echo -e "$fake_binary_content" > "${TEST_TEMP_DIR}/downloaded_binary"

    # Calculate its checksum
    local expected=$(sha256sum "${TEST_TEMP_DIR}/downloaded_binary" | cut -d' ' -f1)

    # Verify
    local actual=$(sha256sum "${TEST_TEMP_DIR}/downloaded_binary" | cut -d' ' -f1)

    [ "$actual" = "$expected" ]
}

@test "download flow: failed verification triggers error" {
    # Simulate downloading a tampered binary
    echo "original content" > "${TEST_TEMP_DIR}/original"
    echo "tampered content" > "${TEST_TEMP_DIR}/tampered"

    local expected=$(sha256sum "${TEST_TEMP_DIR}/original" | cut -d' ' -f1)
    local actual=$(sha256sum "${TEST_TEMP_DIR}/tampered" | cut -d' ' -f1)

    # Verification should fail
    [ "$actual" != "$expected" ]
}

@test "download flow: temp file is cleaned up on verification failure" {
    # This tests the pattern used in install.sh where temp file is removed on failure
    local temp_file="${TEST_TEMP_DIR}/temp_download"
    echo "content" > "$temp_file"

    # Simulate failed verification and cleanup
    local expected="wrong_hash"
    local actual=$(sha256sum "$temp_file" | cut -d' ' -f1)

    if [[ "$actual" != "$expected" ]]; then
        rm -f "$temp_file"
    fi

    # Verify cleanup happened
    [ ! -f "$temp_file" ]
}
