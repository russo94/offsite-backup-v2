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
# 5. Track whether this backup stopped Mattermost and restart it on normal
#    failures or graceful process exit/interruption.
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
#   - cleanup_mattermost_backup
# ==============================================================================


# ==============================================================================
# Configuration Defaults
# ==============================================================================

MATTERMOST_CTID="${MATTERMOST_CTID:-111}"
MATTERMOST_SERVICE="${MATTERMOST_SERVICE:-mattermost}"
MATTERMOST_DB_NAME="${MATTERMOST_DB_NAME:-mattermost}"
MATTERMOST_HOST_BACKUP_ROOT="${MATTERMOST_HOST_BACKUP_ROOT:-/backup/mattermost}"
MATTERMOST_CONTAINER_BACKUP_ROOT="${MATTERMOST_CONTAINER_BACKUP_ROOT:-/opt/mattermost/backups}"

# Runtime state used by the orchestrator EXIT cleanup. The restart flag tracks
# whether this backup may have stopped Mattermost. The active candidate allows
# cleanup to remove an incomplete capture or recover an interrupted promotion.
MATTERMOST_RESTART_REQUIRED=false
MATTERMOST_ACTIVE_CANDIDATE=""


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

    for required_command in pg_dump psql createdb dropdb rsync python3; do

        if ! pct exec "$MATTERMOST_CTID" -- sh -c "command -v '$required_command' >/dev/null 2>&1"; then
            log_error "Required Mattermost backup command not found in LXC $MATTERMOST_CTID: $required_command"
            return 1
        fi

    done

    log_success "Mattermost backup environment verified."
}


# ==============================================================================
# Candidate Helpers
# ==============================================================================

_mattermost_candidate_name_is_safe() {

    local candidate_name="$1"

    [[ "$candidate_name" =~ ^\.candidate-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]
}


_remove_mattermost_candidate() {

    local candidate_name="$1"

    if ! _mattermost_candidate_name_is_safe "$candidate_name"; then
        log_error "Refusing to remove unsafe Mattermost candidate name: $candidate_name"
        return 1
    fi

    rm -rf -- "${MATTERMOST_HOST_BACKUP_ROOT}/${candidate_name}"
}


# ==============================================================================
# Service Recovery Cleanup
# ==============================================================================

cleanup_mattermost_backup() {

    local cleanup_failed=false
    local candidate_name="${MATTERMOST_ACTIVE_CANDIDATE:-}"
    local host_candidate
    local current_path
    local previous_path

    if [[ "${MATTERMOST_RESTART_REQUIRED:-false}" == true ]]; then

        log_warn "Mattermost was stopped by the backup process. Attempting recovery startup."

        if [[ "$(pct status "$MATTERMOST_CTID" 2>/dev/null)" != "status: running" ]]; then
            log_error "Unable to restart Mattermost because LXC $MATTERMOST_CTID is not running."
            cleanup_failed=true
        elif ! pct exec "$MATTERMOST_CTID" -- systemctl start "$MATTERMOST_SERVICE"; then
            log_error "Mattermost recovery startup failed."
            cleanup_failed=true
        elif ! pct exec "$MATTERMOST_CTID" -- systemctl is-active --quiet "$MATTERMOST_SERVICE"; then
            log_error "Mattermost is not active after recovery startup."
            cleanup_failed=true
        else
            MATTERMOST_RESTART_REQUIRED=false
            log_success "Mattermost recovery startup completed."
        fi

    fi

    if [[ -n "$candidate_name" ]]; then

        if ! _mattermost_candidate_name_is_safe "$candidate_name"; then
            log_error "Refusing cleanup for unsafe Mattermost candidate name: $candidate_name"
            cleanup_failed=true
        else
            host_candidate="${MATTERMOST_HOST_BACKUP_ROOT}/${candidate_name}"
            current_path="${MATTERMOST_HOST_BACKUP_ROOT}/current"
            previous_path="${MATTERMOST_HOST_BACKUP_ROOT}/.previous-${candidate_name#.candidate-}"

            # If interruption happened after current was moved aside but before
            # candidate promotion completed, restore the previous known-good set.
            if [[ -d "$previous_path" && ! -e "$current_path" && ! -L "$current_path" ]]; then

                if mv -- "$previous_path" "$current_path"; then
                    log_warn "Previous Mattermost recovery set restored after interrupted promotion."
                else
                    log_error "CRITICAL: unable to restore previous Mattermost recovery set during cleanup."
                    cleanup_failed=true
                fi

            fi

            # An active candidate is incomplete unless it has already been moved
            # into current. Remove only the strictly validated candidate path.
            if [[ -e "$host_candidate" || -L "$host_candidate" ]]; then

                if _remove_mattermost_candidate "$candidate_name"; then
                    log_warn "Incomplete Mattermost backup candidate removed during cleanup."
                else
                    log_error "Unable to remove incomplete Mattermost backup candidate during cleanup."
                    cleanup_failed=true
                fi

            fi

            # If the verified candidate was already promoted before interruption,
            # current is valid and the preserved previous set can be discarded.
            if [[ -d "$previous_path" && -d "$current_path" && ! -e "$host_candidate" ]]; then

                if rm -rf -- "$previous_path"; then
                    log_warn "Previous Mattermost recovery set cleaned after interrupted promotion."
                else
                    log_error "Unable to clean previous Mattermost recovery set after interrupted promotion."
                    cleanup_failed=true
                fi

            fi

            if [[ ! -e "$host_candidate" && ! -L "$host_candidate" && ! -d "$previous_path" ]]; then
                MATTERMOST_ACTIVE_CANDIDATE=""
            fi
        fi

    fi

    if [[ "$cleanup_failed" == true ]]; then
        return 1
    fi

    return 0
}


# ==============================================================================
# Candidate Dataset Capture
# ==============================================================================

_capture_mattermost_backup_candidate() {

    local candidate_name="$1"
    local host_candidate="${MATTERMOST_HOST_BACKUP_ROOT}/${candidate_name}"
    local container_candidate="${MATTERMOST_CONTAINER_BACKUP_ROOT}/${candidate_name}"
    local capture_failed=false
    local restart_failed=false

    if ! _mattermost_candidate_name_is_safe "$candidate_name"; then
        log_error "Unsafe Mattermost candidate name: $candidate_name"
        return 1
    fi

    log_section "Capturing Mattermost Backup Candidate"

    if [[ -e "$host_candidate" ]]; then
        log_error "Mattermost backup candidate already exists: $host_candidate"
        return 1
    fi

    # Create the candidate from inside the unprivileged LXC so ownership maps
    # correctly on the host bind mount.
    if ! pct exec "$MATTERMOST_CTID" -- install -d -m 0750 \
        "$container_candidate" \
        "$container_candidate/database" \
        "$container_candidate/config" \
        "$container_candidate/data" \
        "$container_candidate/plugins" \
        "$container_candidate/client-plugins"; then

        log_error "Unable to create Mattermost backup candidate directories."
        return 1
    fi

    log_info "Stopping Mattermost for a consistent application capture."

    # Set the recovery flag before the stop attempt. If the backup process exits
    # gracefully at any point after this, the orchestrator EXIT cleanup retries
    # the service startup.
    MATTERMOST_RESTART_REQUIRED=true

    if ! pct exec "$MATTERMOST_CTID" -- systemctl stop "$MATTERMOST_SERVICE"; then
        log_error "Unable to stop Mattermost."
        cleanup_mattermost_backup || true
        return 1
    fi

    # Normal capture failures still reach the explicit restart path below.

    # The redirection runs as container root. This keeps the dump owned by the
    # LXC root mapping on the host instead of host UID 0, which is important for
    # an unprivileged bind mount. PostgreSQL still performs the database read.
    if ! pct exec "$MATTERMOST_CTID" -- \
        sh -c 'runuser -u postgres -- pg_dump --format=plain --no-owner --no-privileges "$1" > "$2"' \
        sh \
        "$MATTERMOST_DB_NAME" \
        "${container_candidate}/database/mattermost.sql"; then

        log_error "Mattermost PostgreSQL dump failed."
        capture_failed=true
    fi

    if [[ "$capture_failed" == false ]] && \
       ! pct exec "$MATTERMOST_CTID" -- \
            chmod 0640 "${container_candidate}/database/mattermost.sql"; then

        log_error "Unable to secure Mattermost PostgreSQL dump permissions."
        capture_failed=true
    fi

    if [[ "$capture_failed" == false ]] && \
       ! pct exec "$MATTERMOST_CTID" -- \
            rsync -aH --delete \
            /opt/mattermost/config/ \
            "${container_candidate}/config/"; then

        log_error "Mattermost config capture failed."
        capture_failed=true
    fi

    if [[ "$capture_failed" == false ]] && \
       ! pct exec "$MATTERMOST_CTID" -- \
            rsync -aH --delete \
            /opt/mattermost/data/ \
            "${container_candidate}/data/"; then

        log_error "Mattermost data capture failed."
        capture_failed=true
    fi

    if [[ "$capture_failed" == false ]] && \
       ! pct exec "$MATTERMOST_CTID" -- \
            rsync -aH --delete \
            /opt/mattermost/plugins/ \
            "${container_candidate}/plugins/"; then

        log_error "Mattermost plugin capture failed."
        capture_failed=true
    fi

    if [[ "$capture_failed" == false ]] && \
       ! pct exec "$MATTERMOST_CTID" -- \
            rsync -aH --delete \
            /opt/mattermost/client/plugins/ \
            "${container_candidate}/client-plugins/"; then

        log_error "Mattermost client plugin capture failed."
        capture_failed=true
    fi

    log_info "Starting Mattermost."

    if ! pct exec "$MATTERMOST_CTID" -- systemctl start "$MATTERMOST_SERVICE"; then
        log_error "Mattermost failed to start after backup capture."
        restart_failed=true
    elif ! pct exec "$MATTERMOST_CTID" -- systemctl is-active --quiet "$MATTERMOST_SERVICE"; then
        log_error "Mattermost is not active after backup capture."
        restart_failed=true
    else
        MATTERMOST_RESTART_REQUIRED=false
    fi

    if [[ "$capture_failed" == true || "$restart_failed" == true ]]; then

        if [[ "$restart_failed" == true ]]; then
            cleanup_mattermost_backup || true
        fi

        log_error "Mattermost backup candidate capture failed."
        return 1
    fi

    log_success "Mattermost backup candidate captured successfully."
}


# ==============================================================================
# Candidate Restore Verification
# ==============================================================================

_verify_mattermost_backup_candidate() {

    local candidate_name="$1"
    local host_candidate="${MATTERMOST_HOST_BACKUP_ROOT}/${candidate_name}"
    local container_candidate="${MATTERMOST_CONTAINER_BACKUP_ROOT}/${candidate_name}"
    local verify_db="mattermost_restore_verify_$(date +%s)_$$"
    local verify_sql="/var/tmp/${verify_db}.sql"
    local live_tables
    local restored_tables
    local verify_failed=false

    if ! _mattermost_candidate_name_is_safe "$candidate_name"; then
        log_error "Unsafe Mattermost candidate name: $candidate_name"
        return 1
    fi

    log_section "Verifying Mattermost Backup Candidate"

    if [[ ! -s "${host_candidate}/database/mattermost.sql" ]]; then
        log_error "Mattermost database dump is missing or empty."
        return 1
    fi

    if [[ ! -s "${host_candidate}/config/config.json" ]]; then
        log_error "Mattermost config.json is missing or empty."
        return 1
    fi

    local required_directory

    for required_directory in data plugins client-plugins; do

        if [[ ! -d "${host_candidate}/${required_directory}" ]]; then
            log_error "Mattermost backup directory is missing: ${required_directory}"
            return 1
        fi

    done

    if ! pct exec "$MATTERMOST_CTID" -- \
        python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' \
        "${container_candidate}/config/config.json"; then

        log_error "Mattermost config.json failed JSON validation."
        return 1
    fi

    # The recovery tree is intentionally restricted. Copy the dump to a
    # temporary PostgreSQL-owned file for isolated restore verification rather
    # than weakening permissions on the backup itself.
    if ! pct exec "$MATTERMOST_CTID" -- \
        cp -- "${container_candidate}/database/mattermost.sql" "$verify_sql"; then

        log_error "Unable to stage Mattermost dump for restore verification."
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- chown postgres:postgres "$verify_sql" || \
       ! pct exec "$MATTERMOST_CTID" -- chmod 0600 "$verify_sql"; then

        pct exec "$MATTERMOST_CTID" -- rm -f -- "$verify_sql" || true
        log_error "Unable to secure temporary Mattermost verification dump."
        return 1
    fi

    log_info "Restoring Mattermost database into temporary verification database."

    if ! pct exec "$MATTERMOST_CTID" -- \
        runuser -u postgres -- createdb "$verify_db"; then

        pct exec "$MATTERMOST_CTID" -- rm -f -- "$verify_sql" || true
        log_error "Unable to create temporary Mattermost verification database."
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- \
        runuser -u postgres -- \
        psql \
            --set=ON_ERROR_STOP=1 \
            --dbname="$verify_db" \
            --file="$verify_sql" \
            >/dev/null; then

        log_error "Mattermost database restore verification failed."
        verify_failed=true
    fi

    if [[ "$verify_failed" == false ]]; then

        live_tables=$(pct exec "$MATTERMOST_CTID" -- \
            runuser -u postgres -- \
            psql -At \
                --dbname="$MATTERMOST_DB_NAME" \
                --command="SELECT count(*) FROM pg_tables WHERE schemaname = 'public';")

        restored_tables=$(pct exec "$MATTERMOST_CTID" -- \
            runuser -u postgres -- \
            psql -At \
                --dbname="$verify_db" \
                --command="SELECT count(*) FROM pg_tables WHERE schemaname = 'public';")

        if [[ ! "$live_tables" =~ ^[0-9]+$ || ! "$restored_tables" =~ ^[0-9]+$ ]]; then
            log_error "Unable to determine Mattermost database table counts."
            verify_failed=true
        elif (( live_tables == 0 )); then
            log_error "Live Mattermost database contains no public tables."
            verify_failed=true
        elif [[ "$live_tables" != "$restored_tables" ]]; then
            log_error "Mattermost restore table count mismatch: live=${live_tables}, restored=${restored_tables}"
            verify_failed=true
        else
            log_success "Mattermost database restore verified: ${restored_tables} public tables."
        fi

    fi

    if ! pct exec "$MATTERMOST_CTID" -- \
        runuser -u postgres -- dropdb --if-exists "$verify_db"; then

        pct exec "$MATTERMOST_CTID" -- rm -f -- "$verify_sql" || true
        log_error "Unable to remove temporary Mattermost verification database: $verify_db"
        return 1
    fi

    if ! pct exec "$MATTERMOST_CTID" -- rm -f -- "$verify_sql"; then
        log_error "Unable to remove temporary Mattermost verification dump: $verify_sql"
        return 1
    fi

    if [[ "$verify_failed" == true ]]; then
        return 1
    fi

    log_success "Mattermost backup candidate verified successfully."
}


# ==============================================================================
# Candidate Promotion
# ==============================================================================

_promote_mattermost_backup_candidate() {

    local candidate_name="$1"
    local host_candidate="${MATTERMOST_HOST_BACKUP_ROOT}/${candidate_name}"
    local current_path="${MATTERMOST_HOST_BACKUP_ROOT}/current"
    local previous_path="${MATTERMOST_HOST_BACKUP_ROOT}/.previous-${candidate_name#.candidate-}"
    local had_current=false

    if ! _mattermost_candidate_name_is_safe "$candidate_name"; then
        log_error "Unsafe Mattermost candidate name: $candidate_name"
        return 1
    fi

    log_section "Promoting Mattermost Backup Candidate"

    if [[ ! -d "$host_candidate" ]]; then
        log_error "Mattermost backup candidate not found: $host_candidate"
        return 1
    fi

    if [[ -e "$previous_path" || -L "$previous_path" ]]; then
        log_error "Previous promotion path already exists: $previous_path"
        return 1
    fi

    if [[ -e "$current_path" || -L "$current_path" ]]; then

        if [[ ! -d "$current_path" || -L "$current_path" ]]; then
            log_error "Mattermost current recovery set is not a normal directory: $current_path"
            return 1
        fi

        if ! mv -- "$current_path" "$previous_path"; then
            log_error "Unable to preserve previous Mattermost recovery set."
            return 1
        fi

        had_current=true
    fi

    if ! mv -- "$host_candidate" "$current_path"; then

        log_error "Unable to promote Mattermost backup candidate."

        if [[ "$had_current" == true ]]; then

            if mv -- "$previous_path" "$current_path"; then
                log_warn "Previous Mattermost recovery set restored after promotion failure."
            else
                log_error "CRITICAL: previous Mattermost recovery set could not be restored automatically."
            fi

        fi

        return 1
    fi

    if [[ "$had_current" == true ]]; then

        if ! rm -rf -- "$previous_path"; then
            log_error "New Mattermost recovery set is valid, but previous recovery set cleanup failed."
            return 1
        fi

    fi

    log_success "Mattermost recovery set promoted to: $current_path"
}


# ==============================================================================
# Preparation Entry Point
# ==============================================================================

prepare_mattermost_backup() {

    local candidate_name

    candidate_name=".candidate-$(date '+%Y-%m-%d_%H-%M-%S')"
    MATTERMOST_ACTIVE_CANDIDATE="$candidate_name"

    verify_mattermost_backup_environment || {
        MATTERMOST_ACTIVE_CANDIDATE=""
        return 1
    }

    if ! _capture_mattermost_backup_candidate "$candidate_name"; then
        _remove_mattermost_candidate "$candidate_name" || true
        return 1
    fi

    if ! _verify_mattermost_backup_candidate "$candidate_name"; then
        log_error "Mattermost candidate verification failed. Previous recovery set remains untouched."
        _remove_mattermost_candidate "$candidate_name" || true
        return 1
    fi

    if ! _promote_mattermost_backup_candidate "$candidate_name"; then
        _remove_mattermost_candidate "$candidate_name" || true
        return 1
    fi

    MATTERMOST_ACTIVE_CANDIDATE=""

    log_success "Mattermost application recovery set prepared successfully."
}
