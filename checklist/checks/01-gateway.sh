#!/bin/bash
# Check: OpenClaw Gateway service and health

check_gateway() {
    section "GATEWAY"

    # Systemd service status
    if timeout 5 systemctl --user is-active openclaw-gateway &>/dev/null 2>&1; then
        report_result "gateway.service" "pass" "openclaw-gateway systemd service is active"
    else
        report_result "gateway.service" "fail" "openclaw-gateway service is not active" \
            "systemctl --user start openclaw-gateway"
    fi

    # HTTP health endpoint — try common ports
    local health_port=""
    for port in 3033 3000 4433; do
        if timeout 5 curl -sf "http://localhost:$port/health" &>/dev/null 2>&1; then
            health_port=$port
            break
        fi
    done

    if [ -n "$health_port" ]; then
        report_result "gateway.http" "pass" "Gateway responding on port $health_port"
    else
        report_result "gateway.http" "fail" "Gateway not responding on ports 3033, 3000, or 4433" \
            "openclaw gateway start"
    fi

    # openclaw CLI version
    if has_cmd openclaw; then
        local version
        version=$(timeout 5 openclaw --version 2>/dev/null | head -1 || echo "unknown")
        report_result "gateway.version" "pass" "openclaw: $version"
    else
        report_result "gateway.version" "fail" "openclaw not found in PATH" \
            "npm install -g openclaw"
    fi
}
