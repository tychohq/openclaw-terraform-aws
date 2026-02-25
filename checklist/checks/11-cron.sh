#!/bin/bash
# Check: Cron scheduler — aligned table display with humanized schedules

# Convert a raw truncated schedule string to human-readable text.
# Input: "cron 0 */6 * * * @ America/Ne..." or "at 2026-03-11 15:00Z"
_humanize_cron_schedule() {
    local sched="$1"

    # at-job: "at 2026-03-11 15:00Z"
    if echo "$sched" | grep -qE '^at '; then
        local date_part
        date_part=$(echo "$sched" | awk '{print $2}')
        local month day
        month=$(echo "$date_part" | cut -d- -f2)
        day=$(echo "$date_part" | cut -d- -f3 | sed 's/^0//')
        local month_name
        case "$month" in
            01) month_name="Jan" ;; 02) month_name="Feb" ;; 03) month_name="Mar" ;;
            04) month_name="Apr" ;; 05) month_name="May" ;; 06) month_name="Jun" ;;
            07) month_name="Jul" ;; 08) month_name="Aug" ;; 09) month_name="Sep" ;;
            10) month_name="Oct" ;; 11) month_name="Nov" ;; 12) month_name="Dec" ;;
            *) month_name="month-$month" ;;
        esac
        echo "one-shot $month_name $day"
        return
    fi

    # cron: "cron <min> <hour> <dom> <month> <dow> @ <tz>..."
    if echo "$sched" | grep -qE '^cron '; then
        local min_f hour_f dom_f
        min_f=$(echo "$sched"  | awk '{print $2}')
        hour_f=$(echo "$sched" | awk '{print $3}')
        dom_f=$(echo "$sched"  | awk '{print $4}')

        # Every N hours: */N
        if echo "$hour_f" | grep -qE '^\*/[0-9]+$'; then
            local n
            n=$(echo "$hour_f" | cut -d/ -f2)
            echo "every ${n}h"
            return
        fi

        # Every N minutes: hour=* and min=*/N
        if [ "$hour_f" = "*" ] && echo "$min_f" | grep -qE '^\*/[0-9]+$'; then
            local n
            n=$(echo "$min_f" | cut -d/ -f2)
            echo "every ${n}min"
            return
        fi

        # Multiple specific hours (comma-separated)
        if echo "$hour_f" | grep -qE '^[0-9]+(,[0-9]+)+$'; then
            local count
            count=$(echo "$hour_f" | tr ',' '\n' | wc -l | tr -d ' ')
            echo "${count}x daily"
            return
        fi

        # Single specific hour
        if echo "$hour_f" | grep -qE '^[0-9]+$'; then
            echo "daily"
            return
        fi

        # Fallback
        echo "scheduled"
        return
    fi

    echo "$sched"
}

# Truncate a name to maxlen chars at a word boundary; append "..." if truncated.
_truncate_name() {
    local name="$1" maxlen="$2"
    if [ "${#name}" -le "$maxlen" ]; then
        echo "$name"
        return
    fi
    # Find last space at or before (maxlen-3) to avoid cutting mid-word
    local trunc
    trunc=$(echo "$name" | awk -v max="$((maxlen - 3))" '{
        result = ""
        n = split($0, words, " ")
        for (i = 1; i <= n; i++) {
            test = (result ? result " " : "") words[i]
            if (length(test) > max) break
            result = test
        }
        if (result == "") result = substr($0, 1, max)
        print result "..."
    }')
    echo "$trunc"
}

check_cron() {
    section "CRON SCHEDULER"

    # Prerequisite: gateway must be running
    if ! gateway_is_running; then
        local start_cmd="openclaw gateway start"
        $IS_LINUX && start_cmd="systemctl --user start openclaw-gateway"
        report_result "cron.gateway" "warn" \
            "Gateway is not running — skipping cron checks" \
            "$start_cmd"
        return
    fi

    report_result "cron.gateway" "pass" "Gateway prerequisite: running"

    if ! has_cmd openclaw; then
        report_result "cron.list" "fail" "openclaw CLI not found" \
            "Install openclaw to manage cron jobs"
        return
    fi

    local cron_output
    cron_output=$(safe_timeout 10 openclaw cron list 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$cron_output" ]; then
        report_result "cron.list" "warn" "openclaw cron list failed or returned no output" \
            "openclaw cron list  # check manually"
        return
    fi

    local header_line data_rows
    header_line=$(echo "$cron_output" | grep -E '^ID ')
    data_rows=$(echo "$cron_output"   | grep -E '^[0-9a-f]{8}-')

    local total=0
    [ -n "$data_rows" ] && total=$(echo "$data_rows" | wc -l | tr -d ' ')

    if [ "$total" -eq 0 ]; then
        report_result "cron.list" "skip" "No cron jobs registered" \
            "Ask OpenClaw to register a cron job"
        return
    fi

    # Derive 1-indexed column positions from the header row
    local name_col sched_col next_col last_col status_col
    name_col=$(echo "$header_line"   | grep -bo 'Name'     | cut -d: -f1)
    sched_col=$(echo "$header_line"  | grep -bo 'Schedule' | cut -d: -f1)
    next_col=$(echo "$header_line"   | grep -bo 'Next'     | cut -d: -f1)
    last_col=$(echo "$header_line"   | grep -bo 'Last'     | cut -d: -f1)
    status_col=$(echo "$header_line" | grep -bo 'Status'   | cut -d: -f1)

    name_col=$((name_col   + 1))
    sched_col=$((sched_col + 1))
    next_col=$((next_col   + 1))
    last_col=$((last_col   + 1))
    status_col=$((status_col + 1))

    # ── First pass: collect job data and find max name length ─────────────────
    local -a job_keys job_names job_scheds job_lasts job_levels
    local max_name=0 ok_count=0 broken_count=0

    while IFS= read -r row; do
        [ -z "$row" ] && continue

        local name sched last status
        name=$(echo "$row"   | cut -c${name_col}-$((sched_col  - 1)) | xargs)
        sched=$(echo "$row"  | cut -c${sched_col}-$((next_col  - 1)) | xargs)
        last=$(echo "$row"   | cut -c${last_col}-$((status_col - 1)) | xargs)
        status=$(echo "$row" | cut -c${status_col}-               | awk '{print $1}')

        local display_name
        display_name=$(_truncate_name "$name" 28)

        local dlen=${#display_name}
        [ "$dlen" -gt "$max_name" ] && max_name="$dlen"

        local human_sched
        human_sched=$(_humanize_cron_schedule "$sched")

        local last_str
        if [ -z "$last" ] || [ "$last" = "-" ]; then
            last_str="not yet run"
        else
            last_str="last ran: $last"
        fi

        local status_level
        case "$status" in
            ok)   status_level="pass"; ok_count=$((ok_count + 1)) ;;
            idle) status_level="skip" ;;
            *)    status_level="warn"; broken_count=$((broken_count + 1)) ;;
        esac

        local safe_name
        safe_name=$(echo "$name" | tr -cs 'a-zA-Z0-9' '_' | sed 's/_*$//')

        job_keys+=("cron.job.$safe_name")
        job_names+=("$display_name")
        job_scheds+=("$human_sched")
        job_lasts+=("$last_str")
        job_levels+=("$status_level")

    done <<< "$data_rows"

    # ── Second pass: report with aligned columns ──────────────────────────────
    info_msg ""
    local idx
    for idx in "${!job_keys[@]}"; do
        local msg
        msg=$(printf "%-*s  %-12s  %s" \
            "$max_name" "${job_names[$idx]}" \
            "${job_scheds[$idx]}" \
            "${job_lasts[$idx]}")
        report_result "${job_keys[$idx]}" "${job_levels[$idx]}" "$msg"
    done
    info_msg ""

    if [ "$broken_count" -gt 0 ]; then
        report_result "cron.summary" "warn" \
            "$total jobs: $ok_count ok · $broken_count with unexpected status" \
            "openclaw cron list  # investigate"
    else
        report_result "cron.summary" "pass" \
            "$total cron jobs registered, all healthy"
    fi
}
