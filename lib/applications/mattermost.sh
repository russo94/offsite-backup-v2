#!/usr/bin/env bash

# ==============================================================================
# Offsite Backup V2
# Mattermost Application Backup Module
# ==============================================================================
#
# Purpose
# -------
# Prepare a recoverable Mattermost application dataset under SOURCE before the
# normal Offsite Backup V2 snapshot is created.
#
# Responsibilities
# ----------------
# 1. Verify the Mattermost LXC and required services/tools are available.
# 2. Verify the host backup path and LXC bind mount resolve to the expected
#    locations.
# 3. Create a consistent Mattermost recovery dataset containing the PostgreSQL
#    database plus required Mattermost filesystem data.
# 4. Verify the prepared dataset before returning success.
# 5. If this module stops Mattermost, guarantee that Mattermost is started again
#    before the module exits, including on failure.
#
# Non-responsibilities
# --------------------
# This module does NOT create Offsite Backup V2 snapshots, apply retention,
# update the snapshot current symlink, write V2 snapshot metadata, or send
# notifications. Those remain responsibilities of the existing V2 modules.
#
# Public API
# ----------
#   - verify_mattermost_backup_environment
#   - prepare_mattermost_backup
# ==============================================================================


# ==============================================================================
# Configuration Defaults
# ==============================================================================

MATTERMOST_CTID="${MATTERMOST_CTID:-111}"
MATTERMOST_SERVICE="${MATTERMOST_SERVICE:-mattermost}"
MATTERMOST_DB_NAME="${MATTERMOST_DB_NAME:-mattermost}"
MATTERMOST_HOST_BACKUP_ROOT="${MATTERMOST_HOST_BACKUP_ROOT:-/backup/mattermost}"
MATTERMOST_CONTAINER_BACKUP_ROOT="${MATTERMOST_CONTAINER_BACKUP_ROOT:-/opt/mattermost/backups}"


# ==============================================================================
# Read-only Environment Verification
# ==============================================================================

verify_mattermost_backup_environment() {

    log_section "Verifying Mattermost Backup Environment"

    if ! command -v pct >/dev/null 2>&1; then
        log_error "Required command not found: pct"
        return 1
    fi

    if [[ ! -d "$MATTERMOST_HOST_BACKUP_ROOT" ]]; then
        log_error "Mattermost host backup path not found: $MATTERMOST_HOST_BACKUP_ROOT"
        return 1
    fi

    if [[ "$(pct status "$MATTERMOST_CTID" 2>/dev/null)" != "status: running" ]]; then
        log_error "Mattermost LXC $MATTERMOST_CTID is not running."
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- systemctl is-active --quiet "$MATTERMOST_SERVICE"; then
        log_error "Mattermost service is not active in LXC $MATTERMOST_CTID."
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- systemctl is-active --quiet postgresql; then
        log_error "PostgreSQL service is not active in LXC $MATTERMOST_CTID."
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- test -d "$MATTERMOST_CONTAINER_BACKUP_ROOT"; then
        log_error "Mattermost container backup path not found: $MATTERMOST_CONTAINER_BACKUP_ROOT"
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- mountpoint -q "$MATTERMOST_CONTAINER_BACKUP_ROOT"; then
        log_error "Mattermost container backup path is not a mountpoint: $MATTERMOST_CONTAINER_BACKUP_ROOT"
        return 1
    fi

    local required_command

    for required_command in pg_dump pg_restore psql rsync; do

        if ! pct exec "$MATTERMOST_CTID" -- sh -c "command -v '$required_command' >/dev/null 2>&1"; then
            log_error "Required Mattermost backup command not found in LXC $MATTERMOST_CTID: $required_command"
            return 1
        fi

    done

    log_success "Mattermost backup environment verified."
}


# ==============================================================================
# Preparation Entry Point
# ==============================================================================

prepare_mattermost_backup() {

    # Deliberately fail closed until the application capture and restore
    # verification stages are implemented and tested. This function is not yet
    # wired into the main Offsite Backup V2 orchestrator.
    log_error "Mattermost backup preparation is not implemented yet."
    return 1
}
