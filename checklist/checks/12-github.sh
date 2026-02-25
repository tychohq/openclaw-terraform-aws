#!/bin/bash
# Check: GitHub CLI authentication

check_github() {
    section "GITHUB CLI"

    # gh installed?
    if ! has_cmd gh; then
        report_result "github.installed" "fail" "gh CLI not installed" \
            "See: https://cli.github.com/manual/installation"
        return
    fi

    local gh_ver
    gh_ver=$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 \
        || echo "unknown")
    report_result "github.installed" "pass" "gh CLI installed (v$gh_ver)"

    # Auth status
    if safe_timeout 10 gh auth status &>/dev/null 2>&1; then
        report_result "github.auth" "pass" "gh authenticated"
    else
        report_result "github.auth" "fail" "gh not authenticated" \
            "gh auth login"
    fi
}
