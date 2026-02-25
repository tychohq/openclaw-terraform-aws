#!/bin/bash
# Check: CLI version audit — installed vs latest on npm

check_cli_versions() {
    section "CLI VERSIONS"

    local required_clis=("openclaw" "clawhub" "agent-browser" "mcporter")
    local optional_clis=("gog" "bird")

    _check_cli_version() {
        local pkg="$1" optional="${2:-false}"

        if ! has_cmd "$pkg"; then
            if $optional; then
                report_result "cli.$pkg" "skip" "$pkg: not installed (optional)"
            else
                report_result "cli.$pkg" "skip" "$pkg: not installed"
            fi
            return
        fi

        local installed
        installed=$(get_npm_version "$pkg")

        # Fetch latest from npm with timeout — graceful offline handling
        local latest
        latest=$(timeout 5 npm view "$pkg" version 2>/dev/null || echo "unknown")

        if [ "$latest" = "unknown" ]; then
            report_result "cli.$pkg" "pass" "$pkg v$installed (latest: unknown — may be offline)"
            return
        fi

        if [ "$installed" = "$latest" ]; then
            report_result "cli.$pkg" "pass" "$pkg v$installed (up to date)"
        else
            report_result "cli.$pkg" "warn" "$pkg v$installed (latest: v$latest)" \
                "npm install -g ${pkg}@latest"
        fi
    }

    for pkg in "${required_clis[@]}"; do
        _check_cli_version "$pkg" false
    done

    for pkg in "${optional_clis[@]}"; do
        _check_cli_version "$pkg" true
    done
}
