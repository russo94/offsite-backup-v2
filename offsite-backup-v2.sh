#!/bin/bash

# ==============================================================================
# Offsite Backup V2
# Main Orchestrator
# ==============================================================================

set -Eeuo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# ==============================================================================
# Load Configuration
# ==============================================================================

source "${SCRIPT_DIR}/backup.conf"


# ==============================================================================
# Load Modules
# ==============================================================================

source "${SCRIPT_DIR}/lib/util.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/verify.sh"
source "${SCRIPT_DIR}/lib/snapshot.sh"
source "${SCRIPT_DIR}/lib/metadata.sh"
source "${SCRIPT_DIR}/lib/retention.sh"
source "${SCRIPT_DIR}/lib/notify.sh"
source "${SCRIPT_DIR}/lib/restore_verify.sh"
source "${SCRIPT_DIR}/lib/health.sh"


# ==============================================================================
# Failure Tracking
# ==============================================================================

CURRENT_STAGE="Starting"


backup_failed() {

    local EXIT_CODE="${1:-1}"
    local FAILED_COMMAND="${2:-Unknown}"
    local FAILED_LINE="${3:-Unknown}"
    local FAILURE_MESSAGE

    FAILURE_MESSAGE="🚨 OFFSITE BACKUP FAILED

🖥 Host:
   $(hostname)

❌ Failed Stage:
   ${CURRENT_STAGE}

⚙️ Command:
   ${FAILED_COMMAND}

📍 Line:
   ${FAILED_LINE}

⏰ Time:
   $(date '+%Y-%m-%d %H:%M:%S')

❌ Exit Code:
   ${EXIT_CODE}

📌 Check:
   journalctl -u offsite-backup-v2.service"

    send_notification "$FAILURE_MESSAGE" || true

}


# ==============================================================================
# Command Handling
# ==============================================================================

COMMAND="${1:-backup}"


case "$COMMAND" in

    health)

        health_report
        exit 0
        ;;

    backup)
        ;;

    *)

        echo "Usage:"
        echo "  $0           Run backup"
        echo "  $0 health    Run health report"
        exit 1
        ;;

esac


# ==============================================================================
# Runtime Setup
# ==============================================================================

mkdir -p "$LOG_DIR"


LOG_FILE_PATH="${LOG_DIR}/backup-$(date '+%Y-%m-%d_%H-%M-%S').log"


exec 9>"$LOCK_FILE"


if ! flock -n 9; then
    echo "Another backup is already running."
    exit 1
fi


cleanup() {

    if [[ -n "${TEMP_SNAPSHOT:-}" && -d "${TEMP_SNAPSHOT:-}" ]]; then
        rm -rf "$TEMP_SNAPSHOT" || true
    fi

}


trap cleanup EXIT
trap 'backup_failed "$?" "$BASH_COMMAND" "$LINENO"' ERR


# ==============================================================================
# Start Backup
# ==============================================================================

log_section "Offsite Backup V2 Started"


START_TIME=$(date +%s)


CURRENT_STAGE="Environment Checks"

run_environment_checks


CURRENT_STAGE="Snapshot Creation"

create_snapshot


CURRENT_STAGE="Metadata Writing"

write_snapshot_metadata "$CURRENT_SNAPSHOT_TYPE"


CURRENT_STAGE="Retention Management"

run_retention


CURRENT_STAGE="Finalizing Backup"


END_TIME=$(date +%s)


DURATION=$((END_TIME - START_TIME))


SNAPSHOT_SIZE=$(du -sh "$CURRENT_SNAPSHOT" | awk '{print $1}')


SNAPSHOT_NAME=$(basename "$CURRENT_SNAPSHOT")


# ==============================================================================
# Read Snapshot Metadata
# ==============================================================================

SNAPSHOT_METADATA="${CURRENT_SNAPSHOT}/.snapshot-info"


KERNEL_VERSION=$(
    grep "^KERNEL=" "$SNAPSHOT_METADATA" |
        cut -d= -f2
)


PVE_VERSION_INFO=$(
    grep "^PVE_VERSION=" "$SNAPSHOT_METADATA" |
        cut -d= -f2-
)


# ==============================================================================
# Completion Logging
# ==============================================================================

log_section "Backup Completed"


log_success "Snapshot : $SNAPSHOT_NAME"
log_success "Type     : $CURRENT_SNAPSHOT_TYPE"
log_success "Size     : $SNAPSHOT_SIZE"
log_success "Duration : ${DURATION} seconds"
log_success "Log File : $LOG_FILE_PATH"


# ==============================================================================
# Discord Success Notification
# ==============================================================================

BACKUP_MESSAGE="✅ OFFSITE BACKUP COMPLETED

🖥 Host:
   $(hostname)

📦 Backup Version:
   ${BACKUP_VERSION}

📸 Snapshot:
   ${SNAPSHOT_NAME}

🔄 Type:
   ${CURRENT_SNAPSHOT_TYPE}

💽 Size:
   ${SNAPSHOT_SIZE}

🧹 Retention:

   Policy:
      ${KEEP_DAILY} daily
      ${KEEP_WEEKLY} weekly
      ${KEEP_MONTHLY} monthly

   Total:
      ${RETENTION_TOTAL} snapshots

   Kept:
      ${RETENTION_KEPT} snapshots

   Deleted:
      ${RETENTION_DELETED} snapshots

🐧 Kernel:
   ${KERNEL_VERSION}

🖥 Proxmox:
   ${PVE_VERSION_INFO}

⏱ Duration:
   ${DURATION} seconds

🟢 Status:
   SUCCESS"


if ! send_notification "$BACKUP_MESSAGE"; then
    log_warning "Backup completed, but the success notification failed."
fi
