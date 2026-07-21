#!/bin/bash

# shellcheck disable=SC2034

# ==============================================================================
# Offsite Backup V2
# Retention Engine
#
# Responsibilities:
#   - Discover valid snapshots
#   - Build a retention plan
#   - Explain why each snapshot is retained
#   - Print the retention report
#   - Optionally delete expired snapshots
#
# Public functions:
#   - run_retention
#   - run_retention_analysis
# ==============================================================================


declare -a RETENTION_SNAPSHOTS=()
declare -a RETENTION_DELETE_LIST=()
declare -A RETENTION_REASONS=()


# ==============================================================================
# Retention Statistics
# ==============================================================================

RETENTION_TOTAL=0
RETENTION_KEPT=0
RETENTION_DELETED=0


# ==============================================================================
# Snapshot collection
# ==============================================================================

_collect_snapshots() {

    local snapshot_path
    local snapshot_name

    RETENTION_SNAPSHOTS=()

    [[ -d "$SNAPSHOT_DIR" ]] || return 0


    while IFS= read -r snapshot_path; do

        snapshot_name="$(basename "$snapshot_path")"


        if is_snapshot_name "$snapshot_name"; then
            RETENTION_SNAPSHOTS+=("$snapshot_name")
        fi


    done < <(

        find "$SNAPSHOT_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print |
        sort -r

    )

}


# ==============================================================================
# Keep helpers
# ==============================================================================

_mark_snapshot_to_keep() {

    local snapshot="$1"
    local reason="$2"


    if [[ -n "${RETENTION_REASONS[$snapshot]:-}" ]]; then

        RETENTION_REASONS["$snapshot"]+=", $reason"

    else

        RETENTION_REASONS["$snapshot"]="$reason"

    fi

}


_snapshot_is_kept() {

    local snapshot="$1"

    [[ -n "${RETENTION_REASONS[$snapshot]:-}" ]]

}


# ==============================================================================
# Retention policies
# ==============================================================================

_apply_latest_retention() {

    if (( ${#RETENTION_SNAPSHOTS[@]} > 0 )); then

        _mark_snapshot_to_keep \
            "${RETENTION_SNAPSHOTS[0]}" \
            "Latest"

    fi

}


_apply_daily_retention() {

    local snapshot
    local snapshot_date
    local retained_days=0

    local -A selected_dates=()


    if (( KEEP_DAILY <= 0 )); then
        return 0
    fi


    for snapshot in "${RETENTION_SNAPSHOTS[@]}"; do

        snapshot_date="${snapshot:0:10}"


        if [[ -z "${selected_dates[$snapshot_date]:-}" ]]; then

            _mark_snapshot_to_keep \
                "$snapshot" \
                "Daily ($snapshot_date)"


            selected_dates["$snapshot_date"]=1


            ((retained_days += 1))


            if (( retained_days >= KEEP_DAILY )); then
                break
            fi

        fi

    done

}


_apply_weekly_retention() {

    local snapshot
    local epoch
    local week_key
    local retained_weeks=0

    local -A selected_weeks=()


    if (( KEEP_WEEKLY <= 0 )); then
        return 0
    fi


    for snapshot in "${RETENTION_SNAPSHOTS[@]}"; do

        epoch="$(snapshot_epoch "$snapshot")"


        week_key="$(date -d "@$epoch" '+%G-W%V')"


        if [[ -z "${selected_weeks[$week_key]:-}" ]]; then

            _mark_snapshot_to_keep \
                "$snapshot" \
                "Weekly ($week_key)"


            selected_weeks["$week_key"]=1


            ((retained_weeks += 1))


            if (( retained_weeks >= KEEP_WEEKLY )); then
                break
            fi

        fi

    done

}


_apply_monthly_retention() {

    local snapshot
    local month_key
    local retained_months=0

    local -A selected_months=()


    if (( KEEP_MONTHLY <= 0 )); then
        return 0
    fi


    for snapshot in "${RETENTION_SNAPSHOTS[@]}"; do

        month_key="${snapshot:0:7}"


        if [[ -z "${selected_months[$month_key]:-}" ]]; then

            _mark_snapshot_to_keep \
                "$snapshot" \
                "Monthly ($month_key)"


            selected_months["$month_key"]=1


            ((retained_months += 1))


            if (( retained_months >= KEEP_MONTHLY )); then
                break
            fi

        fi

    done

}


_build_delete_list() {

    local snapshot


    RETENTION_DELETE_LIST=()


    for snapshot in "${RETENTION_SNAPSHOTS[@]}"; do

        if ! _snapshot_is_kept "$snapshot"; then

            RETENTION_DELETE_LIST+=("$snapshot")

        fi

    done

}


# ==============================================================================
# Retention Plan Builder
# ==============================================================================

build_retention_plan() {

    RETENTION_REASONS=()
    RETENTION_DELETE_LIST=()


    _collect_snapshots


    if (( ${#RETENTION_SNAPSHOTS[@]} == 0 )); then
        return 0
    fi


    _apply_latest_retention
    _apply_daily_retention
    _apply_weekly_retention
    _apply_monthly_retention
    _build_delete_list

}


# ==============================================================================
# Reporting
# ==============================================================================

_print_retention_report() {

    local snapshot
    local kept_count=0
    local delete_count="${#RETENTION_DELETE_LIST[@]}"


    log_section "Retention Analysis"


    log_info "Policy: ${KEEP_DAILY} daily, ${KEEP_WEEKLY} weekly, ${KEEP_MONTHLY} monthly"
    log_info "Mode  : ${RETENTION_MODE}"


    if (( ${#RETENTION_SNAPSHOTS[@]} == 0 )); then

        log_warn "No valid snapshots were found."

        RETENTION_TOTAL=0
        RETENTION_KEPT=0
        RETENTION_DELETED=0

        return 0

    fi


    echo

    log_info "KEEP"


    for snapshot in "${RETENTION_SNAPSHOTS[@]}"; do

        if _snapshot_is_kept "$snapshot"; then

            log_success "$snapshot (${RETENTION_REASONS[$snapshot]})"


            ((kept_count += 1))

        fi

    done


    echo

    log_info "DELETE"


    if (( delete_count == 0 )); then

        log_info "No snapshots are eligible for deletion."

    else

        for snapshot in "${RETENTION_DELETE_LIST[@]}"; do

            log_warn "$snapshot"

        done

    fi


    echo

    log_info "Total snapshots : ${#RETENTION_SNAPSHOTS[@]}"
    log_info "Keep            : $kept_count"
    log_info "Delete          : $delete_count"


    # Export retention statistics.

    RETENTION_TOTAL="${#RETENTION_SNAPSHOTS[@]}"
    RETENTION_KEPT="$kept_count"
    RETENTION_DELETED="$delete_count"

}


# ==============================================================================
# Deletion execution
# ==============================================================================

_execute_retention_deletions() {

    local snapshot
    local snapshot_path
    local resolved_snapshot
    local resolved_snapshot_dir
    local deleted_count=0


    if [[ "$RETENTION_MODE" != "delete" ]]; then

        log_warn "Dry run only. No snapshots were deleted."

        return 0

    fi


    if (( ${#RETENTION_DELETE_LIST[@]} == 0 )); then

        log_success "No snapshots required deletion."

        return 0

    fi


    log_section "Executing Retention Deletions"


    if ! resolved_snapshot_dir=$(realpath -- "$SNAPSHOT_DIR"); then

        log_error "Unable to resolve snapshot directory:"
        log_error "  $SNAPSHOT_DIR"

        return 1

    fi


    if [[ -z "$resolved_snapshot_dir" || ! -d "$resolved_snapshot_dir" ]]; then

        log_error "Resolved snapshot directory is invalid:"
        log_error "  ${resolved_snapshot_dir:-Unavailable}"

        return 1

    fi


    for snapshot in "${RETENTION_DELETE_LIST[@]}"; do

        if ! is_snapshot_name "$snapshot"; then

            log_error "Refusing to delete invalid snapshot name: $snapshot"

            return 1

        fi


        snapshot_path="${SNAPSHOT_DIR}/${snapshot}"


        if [[ ! -d "$snapshot_path" ]]; then

            log_warn "Snapshot no longer exists: $snapshot"

            continue

        fi


        if ! resolved_snapshot=$(realpath -- "$snapshot_path"); then

            log_error "Unable to resolve snapshot path:"
            log_error "  $snapshot_path"

            return 1

        fi


        if [[ -z "$resolved_snapshot" ]]; then

            log_error "Resolved snapshot path is empty:"
            log_error "  $snapshot_path"

            return 1

        fi


        case "$resolved_snapshot" in

            "$resolved_snapshot_dir"/*)
                ;;

            *)

                log_error "Refusing unsafe deletion path:"
                log_error "  $resolved_snapshot"

                return 1

                ;;

        esac


        if ! rm -rf -- "$resolved_snapshot"; then

            log_error "Failed to delete snapshot:"
            log_error "  $resolved_snapshot"

            return 1

        fi


        log_success "Deleted snapshot: $snapshot"


        ((deleted_count += 1))

    done


    log_success "Retention deletion completed: $deleted_count snapshot(s) deleted."

}


# ==============================================================================
# Public API
# ==============================================================================

run_retention() {

    case "$RETENTION_MODE" in

        dry-run|delete)
            ;;

        *)

            log_error "Invalid RETENTION_MODE: $RETENTION_MODE"
            log_error 'Allowed values are "dry-run" and "delete".'

            return 1

            ;;

    esac


    build_retention_plan


    _print_retention_report


    _execute_retention_deletions

}


run_retention_analysis() {

    local previous_mode="$RETENTION_MODE"
    local retention_status=0


    RETENTION_MODE="dry-run"


    if ! run_retention; then
        retention_status=$?
    fi


    RETENTION_MODE="$previous_mode"


    return "$retention_status"

}
