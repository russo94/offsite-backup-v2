#!/usr/bin/env bash

# Shared utility functions for Phanom Backup.
#
# Keep this module small. Functions should only be added here when they are
# genuinely reusable across multiple parts of the backup system.


# Convert a byte count into a human-readable value.
#
# Example:
#   human_size 1073741824
#   Output: 1.0 GiB
human_size() {
    local bytes="${1:-0}"

    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "unknown"
        return 1
    fi

    awk -v bytes="$bytes" '
        function human(value) {
            split("B KiB MiB GiB TiB PiB", units, " ")
            unit = 1

            while (value >= 1024 && unit < 6) {
                value /= 1024
                unit++
            }

            if (unit == 1) {
                return sprintf("%.0f %s", value, units[unit])
            }

            return sprintf("%.1f %s", value, units[unit])
        }

        BEGIN {
            print human(bytes)
        }
    '
}


# Check whether a value matches the snapshot directory naming format.
#
# Valid example:
#   2026-07-20_22-27-14
is_snapshot_name() {
    local name="${1:-}"

    [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]
}


# Convert a valid snapshot name into a Unix timestamp.
#
# Example:
#   snapshot_epoch "2026-07-20_22-27-14"
snapshot_epoch() {
    local snapshot_name="${1:-}"
    local formatted_date

    if ! is_snapshot_name "$snapshot_name"; then
        return 1
    fi

    formatted_date="${snapshot_name/_/ }"
    formatted_date="${formatted_date:0:13}:${formatted_date:14:2}:${formatted_date:17:2}"

    date --date="$formatted_date" +%s 2>/dev/null
}


# Return the number of bytes used by a file or directory.
#
# Output:
#   Integer byte count
path_size_bytes() {
    local path="${1:-}"

    if [[ ! -e "$path" ]]; then
        return 1
    fi

    du --summarize --bytes "$path" 2>/dev/null | awk '{print $1}'
}


# Create a directory if it does not already exist.
#
# Returns an error if the path exists but is not a directory.
ensure_directory() {
    local directory="${1:-}"

    if [[ -z "$directory" ]]; then
        return 1
    fi

    if [[ -e "$directory" && ! -d "$directory" ]]; then
        return 1
    fi

    mkdir -p "$directory"
}
