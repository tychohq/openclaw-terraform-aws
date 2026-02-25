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

    # Parse data rows: skip header line (starts with "ID") and non-data lines.
    # Data rows start with a UUID (8 hex chars, dash, ...)
    local data_rows
    data_rows=$(echo "$cron_output" | grep -E '^[0-9a-f]{8}-')

    local total
    total=$(echo "$data_rows" | grep -c '.' 2>/dev/null || echo 0)
    [ -z "$data_rows" ] && total=0

    if [ "$total" -eq 0 ]; then
        report_result "cron.list" "skip" "No cron jobs registered" \
            "Ask OpenClaw to register a cron job"
        return
    fi

    # Collect names and broken jobs
    local names=()
    local broken=()

    while IFS= read -r row; do
        [ -z "$row" ] && continue
        # Fields: ID Name Schedule Next Last Status Target Agent
        # Name is column 2 (may contain spaces — truncated by CLI), Status is col 6
        local name status
        # awk: skip UUID col (1), take col 2 as name, col 6 as status
        name=$(echo "$row" | awk '{print $2}')
        status=$(echo "$row" | awk '{print $6}')
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
