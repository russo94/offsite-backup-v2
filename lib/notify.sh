#!/bin/bash

# ==============================================================================
# Offsite Backup V2
# Discord Notification Module
# ==============================================================================

send_notification() {

    local MESSAGE="$1"
    local JSON_MESSAGE
    local HTTP_CODE
    local CURL_EXIT_CODE

    if [[ "${NOTIFY_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
        echo "Discord webhook URL missing." >&2
        return 1
    fi

    if [[ "${NOTIFY_METHOD:-discord}" != "discord" ]]; then
        echo "Unknown notification method: ${NOTIFY_METHOD}" >&2
        return 1
    fi

    JSON_MESSAGE=$(printf '%s' "$MESSAGE" | python3 -c '
import json
import sys

print(json.dumps(sys.stdin.read()))
')

    if HTTP_CODE=$(curl \
        --silent \
        --show-error \
        --connect-timeout 10 \
        --max-time 30 \
        --output /dev/null \
        --write-out "%{http_code}" \
        --header "Content-Type: application/json" \
        --request POST \
        --data "{\"content\":${JSON_MESSAGE}}" \
        "$DISCORD_WEBHOOK_URL"); then

        :

    else

        CURL_EXIT_CODE=$?

        echo \
            "Discord notification failed: curl exit code ${CURL_EXIT_CODE}." \
            >&2

        return 1

    fi

    if [[ "$HTTP_CODE" != "204" && "$HTTP_CODE" != "200" ]]; then
        echo "Discord notification failed: HTTP ${HTTP_CODE}." >&2
        return 1
    fi

    return 0

}
