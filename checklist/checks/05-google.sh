#!/bin/bash
# Check: Google integration via gog CLI (github.com/steipete/gogcli)

check_google() {
    section "GOOGLE (gog CLI)"

    # gog installed?
    if ! has_cmd gog; then
        report_result "google.installed" "skip" "gog CLI not installed (optional)" \
            "npm install -g gogcli  # or: see github.com/steipete/gogcli"
        return
    fi

    local gog_ver
    gog_ver=$(gog --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    report_result "google.installed" "pass" "gog CLI installed (v$gog_ver)"

    # Auth status — check config_exists + accounts
    local auth_out
    auth_out=$(timeout 10 gog auth status 2>/dev/null || echo "")

    if echo "$auth_out" | grep -qi 'config_exists.*true\|authenticated\|accounts'; then
        report_result "google.auth" "pass" "gog authenticated (config found)"
    elif [ -z "$auth_out" ]; then
        report_result "google.auth" "fail" "gog auth status returned no output" \
            "gog auth login"
        return
    else
        report_result "google.auth" "fail" "gog not authenticated" \
            "gog auth login"
        return
    fi

    # Determine account flag for per-service tests
    local account_flag=""
    local conf_account="${CHECKLIST_CONF[GOOGLE_ACCOUNT]:-}"
    if [ -n "$conf_account" ]; then
        account_flag="--account $conf_account"
    fi

    if [ -z "$conf_account" ]; then
        report_result "google.account" "skip" "GOOGLE_ACCOUNT not set — skipping per-service tests" \
            "Set GOOGLE_ACCOUNT=you@gmail.com in checklist.conf"
        return
    fi

    report_result "google.account" "pass" "Using account: $conf_account"

    # Gmail read test
    # shellcheck disable=SC2086
    if timeout 10 gog gmail list --limit 1 --json --no-input $account_flag &>/dev/null 2>&1; then
        report_result "google.gmail" "pass" "Gmail: accessible"
    else
        report_result "google.gmail" "warn" "Gmail: could not list messages" \
            "gog auth login  # may need to re-grant Gmail scope"
    fi

    # Calendar test
    # shellcheck disable=SC2086
    if timeout 10 gog calendar list --json --no-input $account_flag &>/dev/null 2>&1; then
        report_result "google.calendar" "pass" "Google Calendar: accessible"
    else
        report_result "google.calendar" "warn" "Google Calendar: could not list calendars" \
            "gog auth login  # may need to re-grant Calendar scope"
    fi

    # Drive test
    # shellcheck disable=SC2086
    if timeout 10 gog drive ls / --json --no-input --max 1 $account_flag &>/dev/null 2>&1; then
        report_result "google.drive" "pass" "Google Drive: accessible"
    else
        report_result "google.drive" "warn" "Google Drive: could not list files" \
            "gog auth login  # may need to re-grant Drive scope"
    fi
}
