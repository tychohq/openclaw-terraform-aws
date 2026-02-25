#!/bin/bash
# Check: OpenClaw Gateway service and health

check_gateway() {
    section "GATEWAY"

    # ── Service / process check (OS-aware) ────────────────────────────────────

    if $IS_LINUX; then
        if safe_timeout 5 systemctl --user is-active openclaw-gateway &>/dev/null 2>&1; then
            report_result "gateway.service" "pass" "openclaw-gateway systemd service is active"
        else
            report_result "gateway.service" "fail" "openclaw-gateway service is not active" \
                "systemctl --user start openclaw-gateway"
        fi

    elif $IS_MACOS; then
        local lc_out
        lc_out=$(launchctl list ai.openclaw.gateway 2>/dev/null)
        if echo "$lc_out" | grep -q '"PID"'; then
            local pid
            pid=$(echo "$lc_out" | grep '"PID"' | grep -oE '[0-9]+')
            report_result "gateway.service" "pass" "openclaw-gateway launchctl service is running (pid $pid)"
        else
            local last_exit
            last_exit=$(echo "$lc_out" | grep '"LastExitStatus"' | grep -oE '[0-9]+' || echo "unknown")
            report_result "gateway.service" "fail" \
                "openclaw-gateway not running (last exit: $last_exit)" \
                "launchctl start ai.openclaw.gateway  # or: openclaw gateway start"
        fi
    else
        # Fallback: look for the node/openclaw process by arguments
        if pgrep -f 'openclaw/dist/index.*gateway' &>/dev/null 2>&1; then
            report_result "gateway.service" "pass" "openclaw gateway process found"
        else
            report_result "gateway.service" "fail" "openclaw gateway process not found" \
                "openclaw gateway start"
        fi
    fi

    # ── HTTP health check ──────────────────────────────────────────────────────
    # Try the configured port first, then fall back to common defaults

    local configured_port
    configured_port=$(get_gateway_port)

    local ports_to_try=()
    [ -n "$configured_port" ] && ports_to_try+=("$configured_port")
    ports_to_try+=(3033 3000 4433)

    local health_port=""
    for port in "${ports_to_try[@]}"; do
        if safe_timeout 5 curl -sf "http://localhost:$port/health" &>/dev/null 2>&1; then
            health_port=$port
            break
        fi
    done

    if [ -n "$health_port" ]; then
        report_result "gateway.http" "pass" "Gateway responding on port $health_port"
    else
        report_result "gateway.http" "fail" \
            "Gateway not responding on any port (tried: ${ports_to_try[*]})" \
            "openclaw gateway start"
    fi

    # ── openclaw CLI version ───────────────────────────────────────────────────

    if has_cmd openclaw; then
        local version
        version=$(safe_timeout 5 openclaw --version 2>/dev/null | head -1 || echo "unknown")
        report_result "gateway.version" "pass" "openclaw: $version"
    else
        report_result "gateway.version" "fail" "openclaw not found in PATH" \
            "npm install -g openclaw"
    fi
}
