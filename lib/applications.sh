#!/usr/bin/env bash

# ==============================================================================
# Offsite Backup V2
# Application Backup Coordinator
# ==============================================================================
#
# Coordinates application-specific preparation steps that must complete before
# the normal Offsite Backup V2 snapshot is created.
#
# Application modules prepare recoverable datasets under SOURCE. Snapshot
# creation, retention, metadata, health reporting, and notifications remain
# responsibilities of the existing Offsite Backup V2 modules.
#
# Public API:
#   - prepare_application_backups
#   - cleanup_application_backups
# ==============================================================================


APPLICATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENABLE_MATTERMOST_BACKUP="${ENABLE_MATTERMOST_BACKUP:-false}"

source "${APPLICATIONS_DIR}/applications/mattermost.sh"


prepare_application_backups() {

    log_section "Preparing Application Backups"

    case "$ENABLE_MATTERMOST_BACKUP" in

        true)
            log_info "Mattermost application backup is enabled."
            prepare_mattermost_backup
            ;;

        false)
            log_info "Mattermost application backup is disabled."
            ;;

        *)
            log_error "Invalid ENABLE_MATTERMOST_BACKUP value: $ENABLE_MATTERMOST_BACKUP"
            log_error "Allowed values: true or false"
            return 1
            ;;

    esac

}


cleanup_application_backups() {

    cleanup_mattermost_backup

}
