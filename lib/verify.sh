#!/usr/bin/env bash

# ==============================================================================
# Verification Module
#
# Responsible for validating that the backup environment is safe before any
# data is written.
#
# Public API:
#   - run_environment_checks
#
# Private helpers:
#   - _verify_root
#   - _verify_mount
#   - _verify_uuid
#   - _verify_source
#   - _verify_space
# ==============================================================================

_verify_root() {

    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit 1
    fi

}

_verify_mount() {

    if ! mountpoint -q "$DESTINATION"; then
        log_error "Backup destination is not mounted."
        exit 1
    fi

    log_success "Backup destination is mounted."

}

_verify_uuid() {

    local current_uuid

    current_uuid=$(blkid -s UUID -o value "$(findmnt -n -o SOURCE "$DESTINATION")")

    if [[ "$current_uuid" != "$EXPECTED_UUID" ]]; then
        log_error "USB UUID mismatch!"
        log_error "Expected: $EXPECTED_UUID"
        log_error "Found:    $current_uuid"
        exit 1
    fi

    log_success "USB UUID verified."

}

_verify_source() {

    if [[ ! -d "$SOURCE" ]]; then
        log_error "Source directory not found: $SOURCE"
        exit 1
    fi

    log_success "Source directory verified."

}

_verify_space() {

    local free_gb

    free_gb=$(df -BG "$DESTINATION" | awk 'NR==2 {gsub(/G/, "", $4); print $4}')

    if (( free_gb < MIN_FREE_GB )); then
        log_error "Only ${free_gb}GB free. Minimum required is ${MIN_FREE_GB}GB."
        exit 1
    fi

    log_success "${free_gb}GB free space available."

}

run_environment_checks() {

    log_section "Running Environment Checks"

    _verify_root
    _verify_mount
    _verify_uuid
    _verify_source
    _verify_space
}
