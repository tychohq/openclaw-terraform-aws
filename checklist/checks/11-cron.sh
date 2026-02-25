#!/bin/bash
# Check: Cron scheduler — jobs registered via gateway API

check_cron() {
    section "CRON SCHEDULER"

    # Prerequisite: gateway must be running (OS-aware via lib.sh helper)
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

    # Fetch registered cron jobs from gateway API
    local cron_output
    cron_output=$(safe_timeout 10 openclaw cron list 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$cron_output" ]; then
        report_result "cron.list" "warn" "openclaw cron list failed or returned no output" \
            "openclaw cron list  # check manually"
        return
    fi

    # Isolate header and data rows (data rows start with a UUID)
    local header_line data_rows
    header_line=$(echo "$cron_output" | grep -E '^ID ')
    data_rows=$(echo "$cron_output" | grep -E '^[0-9a-f]{8}-')

    local total=0
    [ -n "$data_rows" ] && total=$(echo "$data_rows" | wc -l | tr -d ' ')

    if [ "$total" -eq 0 ]; then
        report_result "cron.list" "skip" "No cron jobs registered" \
            "Ask OpenClaw to register a cron job"
        return
    fi

    # Find the character position of the Status column from the header.
    # The output is fixed-width so cut by position to avoid Schedule's spaces.
    local status_col=1
    if [ -n "$header_line" ]; then
        status_col=$(echo "$header_line" | grep -bo 'Status' | cut -d: -f1)
        status_col=$((status_col + 1))   # cut -c is 1-indexed
    fi

    # Collect names and broken jobs
    local names=()
    local broken=()

    while IFS= read -r row; do
        [ -z "$row" ] && continue
        # Name: second whitespace field (after the 36-char UUID)
        local name status
        name=$(echo "$row" | awk '{print $2}')
        # Status: extract from fixed column position, then take first word
        status=$(echo "$row" | cut -c"${status_col}"- | awk '{print $1}')
        names+=("$name")
        if [ -n "$status" ] && [ "$status" != "ok" ] && [ "$status" != "idle" ]; then
            broken+=("$name($status)")
        fi
    done <<< "$data_rows"

    report_result "cron.list" "pass" "$total cron jobs registered: ${names[*]}"

    if [ "${#broken[@]}" -gt 0 ]; then
        report_result "cron.broken" "warn" \
            "${#broken[@]} job(s) with unexpected status: ${broken[*]}" \
            "openclaw cron list  # investigate broken jobs"
    else
        report_result "cron.broken" "pass" "All cron jobs have healthy status"
    fi
}
