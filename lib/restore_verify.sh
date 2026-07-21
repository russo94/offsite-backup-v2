#!/bin/bash

# ==============================================================================
# Offsite Backup V2
# Dynamic Restore Verification Module
# ==============================================================================


# ==============================================================================
# Configuration
# ==============================================================================
#
# RESTORE_REQUIRED_PATHS may optionally be declared in backup.conf:
#
# RESTORE_REQUIRED_PATHS=(
#     "proxmox/vzdump"
#     "proxmox/config"
# )
#
# Every other top-level directory is discovered automatically.
# ==============================================================================

if ! declare -p RESTORE_REQUIRED_PATHS &>/dev/null; then

    RESTORE_REQUIRED_PATHS=(
        "proxmox/vzdump"
        "proxmox/config"
    )

fi


RESTORE_IGNORED_DIRECTORIES=(
    "lost+found"
)


# ==============================================================================
# Exported Verification Results
# ==============================================================================

RESTORE_VERIFY_TOTAL=0
RESTORE_VERIFY_PASSED=0
RESTORE_VERIFY_FAILED=0

RESTORE_VERIFY_REQUIRED_TOTAL=0
RESTORE_VERIFY_REQUIRED_PASSED=0
RESTORE_VERIFY_REQUIRED_FAILED=0

RESTORE_VERIFY_DISCOVERED_TOTAL=0
RESTORE_VERIFY_DISCOVERED_PASSED=0
RESTORE_VERIFY_DISCOVERED_FAILED=0

RESTORE_VERIFY_STATUS="UNKNOWN"
RESTORE_VERIFY_REPORT=""


# ==============================================================================
# Internal Helpers
# ==============================================================================

_restore_directory_is_ignored() {

    local DIRECTORY_NAME="$1"
    local IGNORED_DIRECTORY

    for IGNORED_DIRECTORY in "${RESTORE_IGNORED_DIRECTORIES[@]}"; do

        if [[ "$DIRECTORY_NAME" == "$IGNORED_DIRECTORY" ]]; then
            return 0
        fi

    done

    return 1

}


_restore_top_level_is_covered_by_required_path() {

    local TOP_LEVEL_DIRECTORY="$1"
    local REQUIRED_PATH

    for REQUIRED_PATH in "${RESTORE_REQUIRED_PATHS[@]}"; do

        if [[ "$REQUIRED_PATH" == "$TOP_LEVEL_DIRECTORY" ]] ||
           [[ "$REQUIRED_PATH" == "$TOP_LEVEL_DIRECTORY/"* ]]; then
            return 0
        fi

    done

    return 1

}


_restore_find_usable_files() {

    local DIRECTORY="$1"

    find "$DIRECTORY" \
        -type f \
        ! -name ".snapshot-info" \
        ! -name "*.log" \
        ! -name "*.notes" \
        ! -name "*.tmp" \
        ! -name "*.partial" \
        -print 2>/dev/null

}


_restore_count_files() {

    local DIRECTORY="$1"

    _restore_find_usable_files "$DIRECTORY" |
        awk 'END {print NR}'

}


_restore_find_latest_file() {

    local DIRECTORY="$1"

    find "$DIRECTORY" \
        -type f \
        ! -name ".snapshot-info" \
        ! -name "*.log" \
        ! -name "*.notes" \
        ! -name "*.tmp" \
        ! -name "*.partial" \
        -printf '%T@|%p\n' 2>/dev/null |
        sort -n |
        tail -n 1 |
        cut -d'|' -f2-

}


_restore_get_file_age_hours() {

    local FILE_PATH="$1"
    local FILE_TIME
    local CURRENT_TIME
    local AGE_SECONDS

    FILE_TIME=$(stat -c '%Y' "$FILE_PATH")
    CURRENT_TIME=$(date +%s)

    AGE_SECONDS=$((CURRENT_TIME - FILE_TIME))

    if (( AGE_SECONDS < 0 )); then
        AGE_SECONDS=0
    fi

    echo $((AGE_SECONDS / 3600))

}


_restore_format_file_size() {

    local FILE_PATH="$1"

    du -h "$FILE_PATH" | awk '{print $1}'

}


_restore_add_failed_check() {

    local CHECK_TYPE="$1"
    local RELATIVE_PATH="$2"
    local REASON="$3"

    RESTORE_VERIFY_TOTAL=$((RESTORE_VERIFY_TOTAL + 1))
    RESTORE_VERIFY_FAILED=$((RESTORE_VERIFY_FAILED + 1))

    case "$CHECK_TYPE" in

        required)

            RESTORE_VERIFY_REQUIRED_TOTAL=$((RESTORE_VERIFY_REQUIRED_TOTAL + 1))
            ;;

        discovered)

            RESTORE_VERIFY_DISCOVERED_TOTAL=$((RESTORE_VERIFY_DISCOVERED_TOTAL + 1))
            ;;

    esac

    case "$CHECK_TYPE" in

        required)
            RESTORE_VERIFY_REQUIRED_FAILED=$((RESTORE_VERIFY_REQUIRED_FAILED + 1))
            ;;

        discovered)
            RESTORE_VERIFY_DISCOVERED_FAILED=$((RESTORE_VERIFY_DISCOVERED_FAILED + 1))
            ;;

    esac

    RESTORE_VERIFY_REPORT+="

   ❌ ${RELATIVE_PATH}

      Check:
         ${CHECK_TYPE}

      Problem:
         ${REASON}"

}


_restore_add_passed_check() {

    local CHECK_TYPE="$1"
    local RELATIVE_PATH="$2"
    local FILE_COUNT="$3"
    local LATEST_FILE="$4"

    local LATEST_FILE_NAME
    local LATEST_FILE_SIZE
    local LATEST_FILE_AGE

    LATEST_FILE_NAME=$(basename "$LATEST_FILE")
    LATEST_FILE_SIZE=$(_restore_format_file_size "$LATEST_FILE")
    LATEST_FILE_AGE=$(_restore_get_file_age_hours "$LATEST_FILE")

    RESTORE_VERIFY_TOTAL=$((RESTORE_VERIFY_TOTAL + 1))
    RESTORE_VERIFY_PASSED=$((RESTORE_VERIFY_PASSED + 1))

    case "$CHECK_TYPE" in

        required)

            RESTORE_VERIFY_REQUIRED_TOTAL=$((RESTORE_VERIFY_REQUIRED_TOTAL + 1))

            RESTORE_VERIFY_REQUIRED_PASSED=$((RESTORE_VERIFY_REQUIRED_PASSED + 1))
            ;;

        discovered)

            RESTORE_VERIFY_DISCOVERED_TOTAL=$((RESTORE_VERIFY_DISCOVERED_TOTAL + 1))

            RESTORE_VERIFY_DISCOVERED_PASSED=$((RESTORE_VERIFY_DISCOVERED_PASSED + 1))
            ;;

    esac

    RESTORE_VERIFY_REPORT+="

   ✅ ${RELATIVE_PATH}

      Check:
         ${CHECK_TYPE}

      Backup Files:
         ${FILE_COUNT}

      Latest:
         ${LATEST_FILE_NAME}

      Size:
         ${LATEST_FILE_SIZE}

      Age:
         ${LATEST_FILE_AGE} hours"

}


_restore_check_directory() {

    local SNAPSHOT_PATH="$1"
    local RELATIVE_PATH="$2"
    local CHECK_TYPE="$3"

    local FULL_PATH
    local FILE_COUNT
    local LATEST_FILE

    FULL_PATH="${SNAPSHOT_PATH}/${RELATIVE_PATH}"


    if [[ ! -d "$FULL_PATH" ]]; then

        _restore_add_failed_check \
            "$CHECK_TYPE" \
            "$RELATIVE_PATH" \
            "Directory is missing"

        return 1

    fi


    FILE_COUNT=$(_restore_count_files "$FULL_PATH")


    if (( FILE_COUNT == 0 )); then

        _restore_add_failed_check \
            "$CHECK_TYPE" \
            "$RELATIVE_PATH" \
            "Directory contains no usable backup files"

        return 1

    fi


    LATEST_FILE=$(_restore_find_latest_file "$FULL_PATH")


    if [[ -z "$LATEST_FILE" || ! -f "$LATEST_FILE" ]]; then

        _restore_add_failed_check \
            "$CHECK_TYPE" \
            "$RELATIVE_PATH" \
            "No usable regular backup file was found"

        return 1

    fi


    _restore_add_passed_check \
        "$CHECK_TYPE" \
        "$RELATIVE_PATH" \
        "$FILE_COUNT" \
        "$LATEST_FILE"

    return 0

}


# ==============================================================================
# Main Verification Function
# ==============================================================================

verify_snapshot_contents() {

    local SNAPSHOT_PATH="$1"

    local REQUIRED_PATH
    local DISCOVERED_NAME

    local -a DISCOVERED_DIRECTORIES=()


    RESTORE_VERIFY_TOTAL=0
    RESTORE_VERIFY_PASSED=0
    RESTORE_VERIFY_FAILED=0

    RESTORE_VERIFY_REQUIRED_TOTAL=0
    RESTORE_VERIFY_REQUIRED_PASSED=0
    RESTORE_VERIFY_REQUIRED_FAILED=0

    RESTORE_VERIFY_DISCOVERED_TOTAL=0
    RESTORE_VERIFY_DISCOVERED_PASSED=0
    RESTORE_VERIFY_DISCOVERED_FAILED=0

    RESTORE_VERIFY_STATUS="UNKNOWN"
    RESTORE_VERIFY_REPORT="📂 Dynamic Backup Content Verification:"


    # --------------------------------------------------------------------------
    # Snapshot Validation
    # --------------------------------------------------------------------------

    if [[ -z "$SNAPSHOT_PATH" || ! -d "$SNAPSHOT_PATH" ]]; then

        RESTORE_VERIFY_STATUS="CRITICAL"
        RESTORE_VERIFY_TOTAL=1
        RESTORE_VERIFY_FAILED=1

        RESTORE_VERIFY_REPORT+="

   ❌ Snapshot

      Problem:
         Snapshot path is unavailable

🛡 Restore Readiness:

   Overall:
      🔴 NOT READY TO RESTORE"

        return 1

    fi


    # --------------------------------------------------------------------------
    # Mandatory Path Checks
    # --------------------------------------------------------------------------

    RESTORE_VERIFY_REPORT+="

📌 Required Paths:"


    if (( ${#RESTORE_REQUIRED_PATHS[@]} == 0 )); then

        RESTORE_VERIFY_REPORT+="

   No mandatory paths configured."

    else

        for REQUIRED_PATH in "${RESTORE_REQUIRED_PATHS[@]}"; do

            _restore_check_directory \
                "$SNAPSHOT_PATH" \
                "$REQUIRED_PATH" \
                "required" || true

        done

    fi


    # --------------------------------------------------------------------------
    # Automatic Top-Level Discovery
    # --------------------------------------------------------------------------

    mapfile -t DISCOVERED_DIRECTORIES < <(
        find "$SNAPSHOT_PATH" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -name ".*" \
            -printf '%f\n' 2>/dev/null |
        sort
    )


    RESTORE_VERIFY_REPORT+="

🔎 Automatically Discovered Services:"


    if (( ${#DISCOVERED_DIRECTORIES[@]} == 0 )); then

        RESTORE_VERIFY_REPORT+="

   ❌ No service backup directories were discovered."

        RESTORE_VERIFY_TOTAL=$((RESTORE_VERIFY_TOTAL + 1))
        RESTORE_VERIFY_FAILED=$((RESTORE_VERIFY_FAILED + 1))

        RESTORE_VERIFY_DISCOVERED_TOTAL=$((RESTORE_VERIFY_DISCOVERED_TOTAL + 1))

        RESTORE_VERIFY_DISCOVERED_FAILED=$((RESTORE_VERIFY_DISCOVERED_FAILED + 1))

    else

        for DISCOVERED_NAME in "${DISCOVERED_DIRECTORIES[@]}"; do

            if _restore_directory_is_ignored "$DISCOVERED_NAME"; then
                continue
            fi


            # Skip a top-level directory when it is already covered by one or
            # more required nested paths, such as proxmox/vzdump and
            # proxmox/config.
            if _restore_top_level_is_covered_by_required_path \
                "$DISCOVERED_NAME"; then
                continue
            fi


            _restore_check_directory \
                "$SNAPSHOT_PATH" \
                "$DISCOVERED_NAME" \
                "discovered" || true

        done

    fi


    # --------------------------------------------------------------------------
    # Overall Restore Status
    # --------------------------------------------------------------------------

    if (( RESTORE_VERIFY_FAILED == 0 )); then

        RESTORE_VERIFY_STATUS="READY"

        RESTORE_VERIFY_REPORT+="

🛡 Restore Readiness:

   Required Checks:
      ${RESTORE_VERIFY_REQUIRED_PASSED}/${RESTORE_VERIFY_REQUIRED_TOTAL} passed

   Discovered Services:
      ${RESTORE_VERIFY_DISCOVERED_PASSED}/${RESTORE_VERIFY_DISCOVERED_TOTAL} passed

   Total Checks:
      ${RESTORE_VERIFY_PASSED}/${RESTORE_VERIFY_TOTAL} passed

   Overall:
      🟢 READY TO RESTORE"

        return 0

    fi


    if (( RESTORE_VERIFY_PASSED > 0 )); then

        RESTORE_VERIFY_STATUS="WARNING"

        RESTORE_VERIFY_REPORT+="

🛡 Restore Readiness:

   Required Checks:
      ${RESTORE_VERIFY_REQUIRED_PASSED}/${RESTORE_VERIFY_REQUIRED_TOTAL} passed

   Discovered Services:
      ${RESTORE_VERIFY_DISCOVERED_PASSED}/${RESTORE_VERIFY_DISCOVERED_TOTAL} passed

   Total Checks:
      ${RESTORE_VERIFY_PASSED}/${RESTORE_VERIFY_TOTAL} passed

   Failed Checks:
      ${RESTORE_VERIFY_FAILED}

   Overall:
      ⚠️ RESTORE NOT GUARANTEED"

        return 1

    fi


    RESTORE_VERIFY_STATUS="CRITICAL"

    RESTORE_VERIFY_REPORT+="

🛡 Restore Readiness:

   Required Checks:
      ${RESTORE_VERIFY_REQUIRED_PASSED}/${RESTORE_VERIFY_REQUIRED_TOTAL} passed

   Discovered Services:
      ${RESTORE_VERIFY_DISCOVERED_PASSED}/${RESTORE_VERIFY_DISCOVERED_TOTAL} passed

   Total Checks:
      0/${RESTORE_VERIFY_TOTAL} passed

   Failed Checks:
      ${RESTORE_VERIFY_FAILED}

   Overall:
      🔴 NOT READY TO RESTORE"

    return 1

}
