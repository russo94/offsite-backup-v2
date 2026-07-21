#!/bin/bash

# ==============================================================================
# Snapshot Metadata Functions
# ==============================================================================

write_snapshot_metadata() {

    local SNAPSHOT_TYPE="$1"

    local METADATA_FILE="${CURRENT_SNAPSHOT}/.snapshot-info"

    cat > "$METADATA_FILE" <<EOF
BACKUP_VERSION=${BACKUP_VERSION}
HOSTNAME=$(hostname)
CREATED=$(date --iso-8601=seconds)
TIMESTAMP=$(basename "$CURRENT_SNAPSHOT")
SNAPSHOT_TYPE=${SNAPSHOT_TYPE}
SOURCE=${SOURCE}
DESTINATION=${DESTINATION}
USER=$(whoami)
KERNEL=$(uname -r)
PVE_VERSION=$(pveversion | head -n1)
EOF

    log_success "Snapshot metadata written."

}
