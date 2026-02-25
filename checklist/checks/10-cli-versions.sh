#!/bin/bash
# Check: CLI version audit — installed vs latest on npm

check_cli_versions() {
    section "CLI VERSIONS"

    # required_clis: always checked (skip if not installed, don't fail)
    # optional_clis: skip silently if not installed
    # Format: "binary:npm_pkg" — use "__skip__" as npm_pkg for non-npm tools
    local required_clis=("openclaw:openclaw" "clawhub:clawhub" "agent-browser:agent-browser" "mcporter:mcporter")
    local optional_clis=("gog:__skip__" "bird:bird")
    # gog is a Homebrew formula (Go binary from github.com/steipete/gogcli), not on npm

    # Extract installed version — tries --version (stdout+stderr), then -V fallback
    _get_installed_version() {
        local pkg="$1"
        local ver
        # Capture stdout+stderr: catches "ClawHub CLI v0.6.0" in help/error text
        ver=$("$pkg" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$ver" ] && echo "$ver" && return
        # Fallback: -V flag (e.g. clawhub -V outputs clean "0.6.0")
        ver=$("$pkg" -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$ver" ] && echo "$ver" && return
        echo "unknown"
    }

    _check_cli_version() {
        local entry="$1" optional="${2:-false}"
        local pkg="${entry%%:*}"
        local npm_pkg="${entry##*:}"

        if ! has_cmd "$pkg"; then
            if $optional; then
                report_result "cli.$pkg" "skip" "$pkg: not installed (optional)"
            else
                report_result "cli.$pkg" "skip" "$pkg: not installed"
            fi
            return
        fi

        local installed
        installed=$(_get_installed_version "$pkg")

        # Non-npm tools: just report installed version, no registry check
        if [ "$npm_pkg" = "__skip__" ]; then
            report_result "cli.$pkg" "pass" "$pkg v$installed (not an npm package — no registry check)"
            return
        fi

        # Fetch latest from npm registry (handles macOS homebrew npm wrapper)
        local latest
        latest=$(npm_registry_view "$npm_pkg")

        if [ "$latest" = "unknown" ]; then
            report_result "cli.$pkg" "pass" "$pkg v$installed (latest: unknown — may be offline)"
            return
        fi

        if [ "$installed" = "$latest" ]; then
            report_result "cli.$pkg" "pass" "$pkg v$installed (up to date)"
        else
            report_result "cli.$pkg" "warn" "$pkg v$installed (latest: v$latest)" \
                "npm install -g ${npm_pkg}@latest"
        fi
    }

    for entry in "${required_clis[@]}"; do
        _check_cli_version "$entry" false
    done

    for entry in "${optional_clis[@]}"; do
        _check_cli_version "$entry" true
    done
}
