#!/bin/bash

# ==============================================================================
# Snapshot Functions
# ==============================================================================

create_snapshot() {

    log_section "Creating Snapshot"

    TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

    TEMP_SNAPSHOT="${SNAPSHOT_DIR}/.${TIMESTAMP}.tmp"
    FINAL_SNAPSHOT="${SNAPSHOT_DIR}/${TIMESTAMP}"

    mkdir -p "$TEMP_SNAPSHOT"

    LAST_SNAPSHOT=""

    if [[ -L "${SNAPSHOT_DIR}/current" ]]; then
        LAST_SNAPSHOT=$(readlink -f "${SNAPSHOT_DIR}/current")
        CURRENT_SNAPSHOT_TYPE="incremental"
        log_info "Using incremental snapshot."
    else
        CURRENT_SNAPSHOT_TYPE="full"
        log_info "No previous snapshot found. Creating full snapshot."
    fi

    if [[ "$CURRENT_SNAPSHOT_TYPE" == "incremental" ]]; then

        if ! rsync \
            -aHAX \
            --delete \
            --link-dest="$LAST_SNAPSHOT" \
            "$SOURCE"/ \
            "$TEMP_SNAPSHOT"/; then

            log_error "rsync failed."
            rm -rf "$TEMP_SNAPSHOT"
            return 1

        fi

    else

        if ! rsync \
            -aHAX \
            --delete \
            "$SOURCE"/ \
            "$TEMP_SNAPSHOT"/; then

            log_error "rsync failed."
            rm -rf "$TEMP_SNAPSHOT"
            return 1

        fi

    fi

    mv "$TEMP_SNAPSHOT" "$FINAL_SNAPSHOT"

    ln -sfn "$FINAL_SNAPSHOT" "${SNAPSHOT_DIR}/current"

    CURRENT_SNAPSHOT="$FINAL_SNAPSHOT"

    log_success "Snapshot created successfully."
    log_info "Snapshot type: ${CURRENT_SNAPSHOT_TYPE}"

}
