#!/bin/bash
# Check: Google integration via gog CLI (github.com/steipete/gogcli)

check_google() {
    section "GOOGLE (gog CLI)"

    # gog installed?
    if ! has_cmd gog; then
        report_result "google.installed" "skip" "gog CLI not installed (optional)" \
            "brew install gogcli  # or: see github.com/steipete/gogcli"
        return
    fi

    local gog_ver
    gog_ver=$(gog --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    report_result "google.installed" "pass" "gog CLI installed (v$gog_ver)"

    # Auth check: gog stores tokens in macOS Keychain, so config_exists is always false.
    # Use credentials file as the reliable signal that gog has been authenticated.
    local creds_file
    if $IS_MACOS; then
        creds_file="$HOME/Library/Application Support/gogcli/credentials.json"
    else
        creds_file="$HOME/.config/gogcli/credentials.json"
    fi

    if [ -f "$creds_file" ]; then
        report_result "google.auth" "pass" "gog credentials found ($creds_file)"
    else
        report_result "google.auth" "fail" "gog credentials not found — not authenticated" \
            "gog auth login"
        return
    fi

    # Determine account flag for per-service tests
    local conf_account="${CHECKLIST_CONF[GOOGLE_ACCOUNT]:-}"
    local account_flag=""
    [ -n "$conf_account" ] && account_flag="--account $conf_account"

    if [ -n "$conf_account" ]; then
        report_result "google.account" "pass" "Using account: $conf_account"
    else
        # GOOGLE_ACCOUNT not set — try without --account (gog uses its default account)
        report_result "google.account" "skip" \
            "GOOGLE_ACCOUNT not set — using gog default account" \
            "Set GOOGLE_ACCOUNT=you@gmail.com in checklist.conf to be explicit"
    fi

    # Gmail — live API call confirms auth actually works
    # shellcheck disable=SC2086
    if safe_timeout 10 gog gmail search 'newer_than:1d' --max 1 \
        --json --no-input $account_flag &>/dev/null 2>&1; then
        report_result "google.gmail" "pass" "Gmail: accessible"
    else
        report_result "google.gmail" "warn" "Gmail: API call failed" \
            "gog auth login  # may need to re-grant Gmail scope"
    fi

    # Calendar
    # shellcheck disable=SC2086
    if safe_timeout 10 gog calendar list --json --no-input $account_flag &>/dev/null 2>&1; then
        report_result "google.calendar" "pass" "Google Calendar: accessible"
    else
        report_result "google.calendar" "warn" "Google Calendar: API call failed" \
            "gog auth login  # may need to re-grant Calendar scope"
    fi

    # Drive
    # shellcheck disable=SC2086
    if safe_timeout 10 gog drive ls / --json --no-input --max 1 $account_flag &>/dev/null 2>&1; then
        report_result "google.drive" "pass" "Google Drive: accessible"
    else
        report_result "google.drive" "warn" "Google Drive: API call failed" \
            "gog auth login  # may need to re-grant Drive scope"
    fi
}
