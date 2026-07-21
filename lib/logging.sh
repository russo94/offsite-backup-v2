#!/bin/bash

# ==============================================================================
# Logging Functions
# ==============================================================================

# Only use colors when running in a terminal
if [[ -t 1 ]]; then
    RED="\e[31m"
    GREEN="\e[32m"
    YELLOW="\e[33m"
    BLUE="\e[34m"
    CYAN="\e[36m"
    RESET="\e[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    RESET=""
fi

log() {

    local LEVEL="$1"
    local MESSAGE="$2"

    local TIMESTAMP
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    local COLOR=""

    case "$LEVEL" in
        INFO)
            COLOR="$BLUE"
            ;;
        WARN)
            COLOR="$YELLOW"
            ;;
        ERROR)
            COLOR="$RED"
            ;;
        SUCCESS)
            COLOR="$GREEN"
            ;;
        *)
            COLOR="$CYAN"
            ;;
    esac

    # Terminal (colored)
    printf "${COLOR}[%s] [%s] %s${RESET}\n" "$TIMESTAMP" "$LEVEL" "$MESSAGE"

    # Log file (plain text)
    printf "[%s] [%s] %s\n" "$TIMESTAMP" "$LEVEL" "$MESSAGE" >> "$LOG_FILE_PATH"

}

log_info() {
    log INFO "$1"
}

log_warn() {
    log WARN "$1"
}

log_error() {
    log ERROR "$1"
}

log_success() {
    log SUCCESS "$1"
}

log_section() {

    echo
    printf "%b============================================================%b\n" "$CYAN" "$RESET"

    log_info "$1"

    printf "%b============================================================%b\n" "$CYAN" "$RESET"

}
