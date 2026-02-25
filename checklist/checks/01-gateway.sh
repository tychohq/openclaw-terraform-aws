#!/bin/bash
# Check: OpenClaw Gateway — uses openclaw health + status CLI

check_gateway() {
    section "GATEWAY"

    if ! has_cmd openclaw; then
        report_result "gateway.running" "fail" "openclaw CLI not found in PATH" \
            "npm install -g openclaw  # or: bun add -g openclaw"
        return
    fi

    # ── Health check ───────────────────────────────────────────────────────────
    # openclaw health works iff the gateway is reachable.
    # Output: "Discord: ok (@Axel) (995ms)", "Telegram: ok (...)", session info, etc.

    local health_output
    health_output=$(safe_timeout 20 openclaw health 2>&1)
    local health_exit=$?

    if [ $health_exit -ne 0 ] || [ -z "$health_output" ]; then
        local start_cmd="openclaw gateway start"
        $IS_LINUX && start_cmd="systemctl --user start openclaw-gateway"
        report_result "gateway.running" "fail" \
            "openclaw health failed — gateway not running" \
            "$start_cmd"
        return
    fi

    report_result "gateway.running" "pass" "Gateway is running (openclaw health responded)"

    # Parse channel status lines: "Discord: ok (@Axel) (995ms)"
    while IFS= read -r line; do
        local channel status
        channel=$(echo "$line" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
        status=$(echo "$line" | awk '{print $2}')
        if [ "$status" = "ok" ]; then
            report_result "gateway.channel.$channel" "pass" "$line"
        else
            report_result "gateway.channel.$channel" "warn" "$line" \
                "openclaw health  # diagnose channel"
        fi
    done < <(echo "$health_output" | \
        grep -E '^[A-Za-z]+: (ok|warn|error|fail|connecting|disconnected|timeout)')

    # Active session count
    local sessions
    sessions=$(echo "$health_output" | grep -oE '\([0-9]+ entries\)' | \
        grep -oE '[0-9]+' | head -1)
    [ -n "$sessions" ] && \
        report_result "gateway.sessions" "pass" "Session store: $sessions active sessions"

    # ── Status check ───────────────────────────────────────────────────────────
    # openclaw status reports gateway reachability, version, and update status.

    local status_output
    status_output=$(safe_timeout 20 openclaw status 2>&1)

    # Gateway reachability + app version (from the Gateway table row)
    local reachable app_version
    reachable=$(echo "$status_output" | grep -oE 'reachable [0-9]+ms' | head -1)
    app_version=$(echo "$status_output" | \
        grep -oE '\bapp [0-9]{4}\.[0-9]+\.[0-9]+\b' | head -1 | awk '{print $2}')

    if [ -n "$reachable" ]; then
        report_result "gateway.reachable" "pass" \
            "Gateway ${reachable}${app_version:+ · v$app_version}"
    else
        report_result "gateway.reachable" "warn" \
            "Could not determine gateway reachability from status" \
            "openclaw status  # check manually"
    fi

    # Update status: "npm latest YYYY.M.D" means on latest; anything else may need update
    if echo "$status_output" | grep -q 'npm latest'; then
        local update_ver
        update_ver=$(echo "$status_output" | grep 'npm latest' | \
            grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+' | head -1)
        report_result "gateway.update" "pass" \
            "openclaw is up to date (v${update_ver:-unknown})"
    elif echo "$status_output" | grep -q 'Update'; then
        report_result "gateway.update" "warn" \
            "openclaw may have an update available" \
            "bun add -g openclaw@latest  # or: npm install -g openclaw@latest"
    else
        report_result "gateway.update" "skip" \
            "Could not determine openclaw update status"
    fi
}
