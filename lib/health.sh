#!/bin/bash

# ==============================================================================
# Offsite Backup V2
# Health Reporting Module
# ==============================================================================


health_report() {

    local HEALTH_LOG
    local REPORT
    local OVERALL_LEVEL="healthy"
    local OVERALL_TITLE
    local HEALTH_EXIT_CODE=0

    local HOST_NAME
    local PROXMOX_VERSION
    local KERNEL_VERSION

    local USB_STATUS="🔴 FAILED"
    local SNAPSHOT_DIR_STATUS="🔴 FAILED"

    local TOTAL_SPACE="Unavailable"
    local USED_SPACE="Unavailable"
    local FREE_SPACE="Unavailable"
    local USED_PERCENT="Unavailable"
    local STORAGE_STATUS="🔴 FAILED"

    local SNAPSHOT_COUNT=0
    local LATEST_SNAPSHOT="None"
    local SNAPSHOT_PATH=""
    local SNAPSHOT_SIZE="Unavailable"
    local SNAPSHOT_BYTES=0
    local CONTENT_STATUS="🔴 FAILED"

    local METADATA_FILE=""
    local METADATA_STATUS="🔴 FAILED"
    local REQUIRED_FIELDS_STATUS="🔴 FAILED"
    local INTEGRITY_STATUS="🔴 CRITICAL"

    local SNAPSHOT_TYPE="Unknown"
    local SNAPSHOT_CREATED="Unknown"

    local LAST_BACKUP_DISPLAY="Unknown"
    local AGE_HOURS="Unknown"
    local FRESHNESS_STATUS="🔴 CRITICAL"

    local RESTORE_STATUS="🔴 NOT READY TO RESTORE"
    local RESTORE_SUMMARY="Restore verification unavailable."

    local WARNING_HOURS="${HEALTH_WARNING_HOURS:-24}"
    local CRITICAL_HOURS="${HEALTH_CRITICAL_HOURS:-48}"

    local STORAGE_INFO
    local FREE_GB=0
    local SNAPSHOT_TIME
    local SNAPSHOT_DATE
    local CURRENT_TIME
    local AGE_SECONDS

    local METADATA_OK=true
    local FIELD

    local -a SNAPSHOTS=()
    local -a REQUIRED_FIELDS=(
        "BACKUP_VERSION"
        "HOSTNAME"
        "CREATED"
        "TIMESTAMP"
        "SNAPSHOT_TYPE"
    )


    HEALTH_LOG="${LOG_DIR}/health-$(date '+%Y-%m-%d_%H-%M-%S').log"

    HOST_NAME=$(hostname)
    KERNEL_VERSION=$(uname -r)

    PROXMOX_VERSION=$(
        pveversion 2>/dev/null |
        head -n1 |
        awk -F'/' '{print $2}'
    )

    PROXMOX_VERSION="${PROXMOX_VERSION:-Unavailable}"


    # --------------------------------------------------------------------------
    # Internal status helpers
    # --------------------------------------------------------------------------

    mark_warning() {

        if [[ "$OVERALL_LEVEL" == "healthy" ]]; then
            OVERALL_LEVEL="warning"
        fi

    }


    mark_critical() {

        OVERALL_LEVEL="critical"
        HEALTH_EXIT_CODE=1

    }


    # --------------------------------------------------------------------------
    # USB Status
    # --------------------------------------------------------------------------

    if mountpoint -q "$DESTINATION"; then
        USB_STATUS="✅ OK"
    else
        USB_STATUS="🔴 FAILED"
        mark_critical
    fi


    # --------------------------------------------------------------------------
    # Snapshot Directory
    # --------------------------------------------------------------------------

    if [[ -d "$SNAPSHOT_DIR" ]]; then
        SNAPSHOT_DIR_STATUS="✅ OK"
    else
        SNAPSHOT_DIR_STATUS="🔴 FAILED"
        mark_critical
    fi


    # --------------------------------------------------------------------------
    # Storage Health
    # --------------------------------------------------------------------------

    if mountpoint -q "$DESTINATION"; then

        STORAGE_INFO=$(df -BG "$DESTINATION" | awk 'NR == 2')

        TOTAL_SPACE=$(awk '{print $2}' <<< "$STORAGE_INFO")
        USED_SPACE=$(awk '{print $3}' <<< "$STORAGE_INFO")
        FREE_SPACE=$(awk '{print $4}' <<< "$STORAGE_INFO")
        USED_PERCENT=$(awk '{print $5}' <<< "$STORAGE_INFO")

        FREE_GB=${FREE_SPACE%G}

        if (( FREE_GB < MIN_FREE_GB )); then
            STORAGE_STATUS="⚠️ WARNING - Low free space"
            mark_warning
        else
            STORAGE_STATUS="✅ OK"
        fi

    else

        STORAGE_STATUS="🔴 FAILED - USB is not mounted"
        mark_critical

    fi


    # --------------------------------------------------------------------------
    # Snapshot Discovery
    # --------------------------------------------------------------------------

    if mountpoint -q "$DESTINATION" && [[ -d "$SNAPSHOT_DIR" ]]; then

        mapfile -t SNAPSHOTS < <(
            find "$SNAPSHOT_DIR" \
                -mindepth 1 \
                -maxdepth 1 \
                -type d \
                -name "20*" \
                -printf "%f\n" |
            sort
        )

        SNAPSHOT_COUNT=${#SNAPSHOTS[@]}

        if (( SNAPSHOT_COUNT > 0 )); then

            LATEST_SNAPSHOT="${SNAPSHOTS[$((SNAPSHOT_COUNT - 1))]}"
            SNAPSHOT_PATH="${SNAPSHOT_DIR}/${LATEST_SNAPSHOT}"

        else

            mark_critical

        fi

    else

        mark_critical

    fi


    # --------------------------------------------------------------------------
    # Snapshot Size and Contents
    # --------------------------------------------------------------------------

    if [[ -n "$SNAPSHOT_PATH" && -d "$SNAPSHOT_PATH" ]]; then

        SNAPSHOT_SIZE=$(du -sh "$SNAPSHOT_PATH" | awk '{print $1}')
        SNAPSHOT_BYTES=$(du -sb "$SNAPSHOT_PATH" | awk '{print $1}')

        if (( SNAPSHOT_BYTES > 0 )); then
            CONTENT_STATUS="✅ OK"
        else
            CONTENT_STATUS="🔴 FAILED"
            mark_critical
        fi

    else

        CONTENT_STATUS="🔴 FAILED - No snapshot available"
        mark_critical

    fi


    # --------------------------------------------------------------------------
    # Snapshot Metadata and Integrity
    # --------------------------------------------------------------------------

    if [[ -n "$SNAPSHOT_PATH" ]]; then
        METADATA_FILE="${SNAPSHOT_PATH}/.snapshot-info"
    fi


    if [[ -n "$METADATA_FILE" && -f "$METADATA_FILE" ]]; then

        METADATA_STATUS="✅ OK"

        for FIELD in "${REQUIRED_FIELDS[@]}"; do

            if ! grep -q "^${FIELD}=" "$METADATA_FILE"; then
                METADATA_OK=false
            fi

        done


        if $METADATA_OK; then

            REQUIRED_FIELDS_STATUS="✅ OK"
            INTEGRITY_STATUS="🟢 HEALTHY"

        else

            REQUIRED_FIELDS_STATUS="🔴 FAILED"
            INTEGRITY_STATUS="🔴 CRITICAL"
            mark_critical

        fi


        SNAPSHOT_TYPE=$(
            awk -F= '
                $1 == "SNAPSHOT_TYPE" {
                    sub(/^[^=]*=/, "")
                    print
                    exit
                }
            ' "$METADATA_FILE"
        )

        SNAPSHOT_CREATED=$(
            awk -F= '
                $1 == "CREATED" {
                    sub(/^[^=]*=/, "")
                    print
                    exit
                }
            ' "$METADATA_FILE"
        )


        SNAPSHOT_TYPE="${SNAPSHOT_TYPE:-Unknown}"
        SNAPSHOT_CREATED="${SNAPSHOT_CREATED:-Unknown}"

    else

        METADATA_STATUS="🔴 FAILED"
        REQUIRED_FIELDS_STATUS="🔴 FAILED"
        INTEGRITY_STATUS="🔴 CRITICAL"
        mark_critical

    fi


    # --------------------------------------------------------------------------
    # Backup Time and Freshness
    # --------------------------------------------------------------------------

    SNAPSHOT_TIME=""


    if [[ "$SNAPSHOT_CREATED" != "Unknown" ]]; then

        if SNAPSHOT_TIME=$(date -d "$SNAPSHOT_CREATED" +%s 2>/dev/null); then
            LAST_BACKUP_DISPLAY=$(date -d "$SNAPSHOT_CREATED" '+%Y-%m-%d %H:%M:%S')
        else
            SNAPSHOT_TIME=""
        fi

    fi


    if [[ -z "$SNAPSHOT_TIME" && "$LATEST_SNAPSHOT" != "None" ]]; then

        SNAPSHOT_DATE=$(
            awk -F'[_-]' \
                '{print $1"-"$2"-"$3" "$4":"$5":"$6}' \
                <<< "$LATEST_SNAPSHOT"
        )

        if SNAPSHOT_TIME=$(date -d "$SNAPSHOT_DATE" +%s 2>/dev/null); then
            LAST_BACKUP_DISPLAY=$(date -d "$SNAPSHOT_DATE" '+%Y-%m-%d %H:%M:%S')
        else
            SNAPSHOT_TIME=""
        fi

    fi


    if [[ -n "$SNAPSHOT_TIME" ]]; then

        CURRENT_TIME=$(date +%s)
        AGE_SECONDS=$((CURRENT_TIME - SNAPSHOT_TIME))

        if (( AGE_SECONDS < 0 )); then
            AGE_SECONDS=0
        fi

        AGE_HOURS=$((AGE_SECONDS / 3600))


        if (( AGE_HOURS < WARNING_HOURS )); then

            FRESHNESS_STATUS="🟢 HEALTHY"

        elif (( AGE_HOURS < CRITICAL_HOURS )); then

            FRESHNESS_STATUS="⚠️ WARNING"
            mark_warning

        else

            FRESHNESS_STATUS="🔴 CRITICAL"
            mark_critical

        fi

    else

        AGE_HOURS="Unknown"
        FRESHNESS_STATUS="🔴 CRITICAL"
        mark_critical

    fi


    # --------------------------------------------------------------------------
    # Restore Verification
    # --------------------------------------------------------------------------

    if [[ -n "$SNAPSHOT_PATH" && -d "$SNAPSHOT_PATH" ]]; then

        if verify_snapshot_contents "$SNAPSHOT_PATH"; then

            RESTORE_STATUS="🟢 READY TO RESTORE"

        else

            case "$RESTORE_VERIFY_STATUS" in

                WARNING)
                    RESTORE_STATUS="⚠️ RESTORE NOT GUARANTEED"
                    mark_warning
                    ;;

                *)
                    RESTORE_STATUS="🔴 NOT READY TO RESTORE"
                    mark_critical
                    ;;

            esac

        fi


        RESTORE_SUMMARY="${RESTORE_VERIFY_PASSED}/${RESTORE_VERIFY_TOTAL} checks passed"

    else

        RESTORE_STATUS="🔴 NOT READY TO RESTORE"
        RESTORE_SUMMARY="No snapshot available for verification"
        mark_critical

    fi


    # --------------------------------------------------------------------------
    # Overall Status
    # --------------------------------------------------------------------------

    case "$OVERALL_LEVEL" in

        healthy)
            OVERALL_TITLE="🟢 OFFSITE BACKUP SYSTEM: HEALTHY"
            ;;

        warning)
            OVERALL_TITLE="⚠️ OFFSITE BACKUP SYSTEM: WARNING"
            ;;

        critical)
            OVERALL_TITLE="🔴 OFFSITE BACKUP SYSTEM: CRITICAL"
            ;;

    esac


    # --------------------------------------------------------------------------
    # Generate Report
    # --------------------------------------------------------------------------

    if [[ "$OVERALL_LEVEL" == "healthy" ]]; then

        REPORT="🟢 OFFSITE BACKUP HEALTH

🖥 Host: ${HOST_NAME}
📦 Backup: v${BACKUP_VERSION}
⚙️ Proxmox: ${PROXMOX_VERSION}
🐧 Kernel: ${KERNEL_VERSION}

🛡 Restore Status
${RESTORE_STATUS} (${RESTORE_VERIFY_PASSED}/${RESTORE_VERIFY_TOTAL})

📸 Latest Backup
• Type: ${SNAPSHOT_TYPE^}
• Created: ${LAST_BACKUP_DISPLAY}
• Size: ${SNAPSHOT_SIZE}
• Snapshots: ${SNAPSHOT_COUNT}

💾 Storage
• Free: ${FREE_SPACE}
• Used: ${USED_PERCENT}

⏱ Freshness
• ${AGE_HOURS} hours old

✅ All systems operational."

    else

        REPORT="========================================
${OVERALL_TITLE}
========================================

🖥 Host:
   ${HOST_NAME}

📦 Backup Version:
   ${BACKUP_VERSION}

⚙️ Proxmox Version:
   ${PROXMOX_VERSION}

🐧 Kernel:
   ${KERNEL_VERSION}

💾 USB Status:
   ${USB_STATUS}

📁 Snapshot Directory:
   ${SNAPSHOT_DIR_STATUS}

💽 Storage:

   Total:
      ${TOTAL_SPACE}

   Used:
      ${USED_SPACE} (${USED_PERCENT})

   Free:
      ${FREE_SPACE}

   Status:
      ${STORAGE_STATUS}

📸 Snapshots:

   Available:
      ${SNAPSHOT_COUNT}

   Latest:
      ${LATEST_SNAPSHOT}

📦 Latest Backup:

   Type:
      ${SNAPSHOT_TYPE}

   Created:
      ${SNAPSHOT_CREATED}

   Size:
      ${SNAPSHOT_SIZE}

   Contents:
      ${CONTENT_STATUS}

🔐 Snapshot Integrity:

   Metadata:
      ${METADATA_STATUS}

   Required Fields:
      ${REQUIRED_FIELDS_STATUS}

   Integrity:
      ${INTEGRITY_STATUS}

⏱ Backup Freshness:

   Last Successful Backup:
      ${LAST_BACKUP_DISPLAY}

   Age:
      ${AGE_HOURS} hours

   Thresholds:
      Warning after ${WARNING_HOURS} hours
      Critical after ${CRITICAL_HOURS} hours

   Status:
      ${FRESHNESS_STATUS}

🛡 Restore Readiness:

   Required Checks:
      ${RESTORE_VERIFY_REQUIRED_PASSED}/${RESTORE_VERIFY_REQUIRED_TOTAL} passed

   Discovered Services:
      ${RESTORE_VERIFY_DISCOVERED_PASSED}/${RESTORE_VERIFY_DISCOVERED_TOTAL} passed

   Total:
      ${RESTORE_SUMMARY}

   Status:
      ${RESTORE_STATUS}

========================================"

    fi


    # --------------------------------------------------------------------------
    # Save, display and notify
    # --------------------------------------------------------------------------

    printf '%s\n' "$REPORT" | tee "$HEALTH_LOG"


    if ! send_notification "$REPORT"; then
        echo
        echo "Warning: health notification could not be sent."
    fi


    echo
    echo "Health log:"
    echo "$HEALTH_LOG"


    return "$HEALTH_EXIT_CODE"

}
