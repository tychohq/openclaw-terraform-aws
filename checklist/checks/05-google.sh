#!/bin/bash
# Check: Google integration via gog CLI (github.com/steipete/gogcli)

# Map gog service name to a display label
_gog_label() {
    case "$1" in
        gmail)     echo "Gmail"     ;; calendar)  echo "Calendar"  ;;
        drive)     echo "Drive"     ;; docs)      echo "Docs"      ;;
        sheets)    echo "Sheets"    ;; contacts)  echo "Contacts"  ;;
        chat)      echo "Chat"      ;; tasks)     echo "Tasks"     ;;
        classroom) echo "Classroom" ;; people)    echo "People"    ;;
        *)         echo "$1"        ;;
    esac
}

# Determine read/write level from newline-separated OAuth scope URLs.
# Any non-readonly scope → read+write; all readonly → read-only; empty → authorized
_gog_access() {
    local scopes="$1"
    [ -z "$scopes" ] && echo "authorized" && return
    while IFS= read -r s; do
        [ -z "$s" ] && continue
        if ! echo "$s" | grep -q '\.readonly'; then
            echo "read+write"
            return
        fi
    done <<< "$scopes"
    echo "read-only"
}

# Run a live API test for a service and report result.
# Usage: _gog_test_service <result_id> <label> <account> <access_level> <cmd...>
_gog_test_service() {
    local result_id="$1" label="$2" account="$3" access="$4"
    shift 4
    if safe_timeout 10 "$@" &>/dev/null 2>&1; then
        report_result "$result_id" "pass" "$label: accessible ($access)"
    else
        report_result "$result_id" "warn" "$label: API call failed" \
            "gog auth add $account --services ${label,,}  # re-authorize"
    fi
}

check_google() {
    section "GOOGLE (gog CLI)"

    if ! has_cmd gog; then
        report_result "google.installed" "skip" "gog CLI not installed (optional)" \
            "brew install gogcli  # or: see github.com/steipete/gogcli"
        return
    fi

    local gog_ver
    gog_ver=$(gog --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    report_result "google.installed" "pass" "gog CLI installed (v$gog_ver)"

    if ! has_cmd jq; then
        report_result "google.auth" "fail" "jq not installed (required for gog checks)" \
            "brew install jq"
        return
    fi

    local conf_account="${CHECKLIST_CONF[GOOGLE_ACCOUNT]:-}"

    # ── Try gog auth list --json ───────────────────────────────────────────────
    # Works when the Keychain is accessible (interactive terminal).
    # Falls back to keychain enumeration in headless/subprocess contexts.

    local auth_list_json
    auth_list_json=$(safe_timeout 10 gog auth list --json 2>/dev/null)

    if [ -n "$auth_list_json" ] && \
       echo "$auth_list_json" | jq -e '.accounts | length > 0' &>/dev/null 2>&1; then

        # ── Full mode ─────────────────────────────────────────────────────────
        local account_count
        account_count=$(echo "$auth_list_json" | jq '.accounts | length')
        report_result "google.accounts" "pass" "$account_count Google account(s) configured"

        local i=0
        while [ "$i" -lt "$account_count" ]; do
            local email authorized_at svc_count svc_type services_raw
            email=$(echo "$auth_list_json" | jq -r --argjson n "$i" '.accounts[$n].email // empty')

            authorized_at=$(echo "$auth_list_json" | jq -r --argjson n "$i" \
                '.accounts[$n] | .authorizedAt // .createdAt // empty' 2>/dev/null | cut -c1-10)

            # Services — handle both string arrays and object arrays
            svc_type=$(echo "$auth_list_json" | jq -r --argjson n "$i" \
                '.accounts[$n].services // [] |
                 if   length == 0        then "empty"
                 elif .[0] | type == "object" then "objects"
                 else "strings" end' 2>/dev/null)

            if [ "$svc_type" = "objects" ]; then
                services_raw=$(echo "$auth_list_json" | jq -r --argjson n "$i" \
                    '.accounts[$n].services | .[].name' 2>/dev/null)
            elif [ "$svc_type" = "strings" ]; then
                services_raw=$(echo "$auth_list_json" | jq -r --argjson n "$i" \
                    '.accounts[$n].services | .[]' 2>/dev/null)
            else
                services_raw=""
            fi

            svc_count=$(echo "$services_raw" | grep -c '.' 2>/dev/null || echo 0)
            [ -z "$services_raw" ] && svc_count=0

            local header="📧 $email ($svc_count service(s)"
            [ -n "$authorized_at" ] && header="${header}, authorized $authorized_at"
            info_msg ""
            info_msg "${header})"

            local safe_email
            safe_email=$(echo "$email" | tr -cs 'a-zA-Z0-9' '_' | sed 's/_*$//')

            while IFS= read -r svc; do
                [ -z "$svc" ] && continue
                local label access scopes_raw
                label=$(_gog_label "$svc")

                # Get scopes for this service (only available in object-array format)
                if [ "$svc_type" = "objects" ]; then
                    scopes_raw=$(echo "$auth_list_json" | jq -r \
                        --argjson n "$i" --arg s "$svc" \
                        '.accounts[$n].services |
                         map(select(.name == $s)) | .[0].scopes // [] | .[]' 2>/dev/null)
                else
                    scopes_raw=""
                fi
                access=$(_gog_access "$scopes_raw")

                local rid="google.${safe_email}.$svc"
                case "$svc" in
                    gmail)
                        _gog_test_service "$rid" "$label" "$email" "$access" \
                            gog gmail search 'newer_than:1d' --max 1 \
                            --json --no-input --account "$email" ;;
                    calendar)
                        _gog_test_service "$rid" "$label" "$email" "$access" \
                            gog calendar list \
                            --json --no-input --account "$email" ;;
                    drive)
                        _gog_test_service "$rid" "$label" "$email" "$access" \
                            gog drive ls \
                            --json --no-input --max 1 --account "$email" ;;
                    *)
                        # Non-testable services: just report authorization status
                        report_result "$rid" "pass" "$label: $access" ;;
                esac
            done <<< "$services_raw"

            i=$((i + 1))
        done

    else
        # ── Fallback mode: Keychain blocked (headless/subprocess context) ──────
        # Extract account emails from macOS Keychain metadata and attempt API calls.

        local creds_file
        $IS_MACOS && creds_file="$HOME/Library/Application Support/gogcli/credentials.json" \
                  || creds_file="$HOME/.config/gogcli/credentials.json"

        if [ ! -f "$creds_file" ]; then
            report_result "google.auth" "fail" "gog credentials not found — not authenticated" \
                "gog auth login"
            return
        fi

        # Read account email names from Keychain entry metadata (no token read required).
        # Entries with "token:email@domain" in the account field; skip "token:default:..." aliases.
        local keychain_emails=""
        if $IS_MACOS; then
            keychain_emails=$(security dump-keychain 2>/dev/null | \
                grep -oE '"token:[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+"' | \
                sed 's/"token://; s/"//' | sort -u)
        fi

        # Config-specified account overrides auto-detected list
        local primary_account="${conf_account:-$(echo "$keychain_emails" | head -1)}"

        if [ -n "$keychain_emails" ]; then
            local email_count
            email_count=$(echo "$keychain_emails" | wc -l | tr -d ' ')
            local email_list
            email_list=$(echo "$keychain_emails" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
            report_result "google.accounts" "pass" \
                "$email_count account(s) in keychain: $email_list"
        else
            report_result "google.accounts" "pass" "gog authenticated (credentials found)"
        fi

        if [ -z "$primary_account" ]; then
            report_result "google.account" "warn" \
                "Could not determine primary account for API tests" \
                "Set GOOGLE_ACCOUNT=you@gmail.com in checklist.conf"
            return
        fi

        info_msg ""
        info_msg "Testing with: $primary_account (set GOOGLE_ACCOUNT in checklist.conf to change)"

        _gog_test_service "google.gmail" "Gmail" "$primary_account" "read+write" \
            gog gmail search 'newer_than:1d' --max 1 \
            --json --no-input --account "$primary_account"

        _gog_test_service "google.calendar" "Calendar" "$primary_account" "read+write" \
            gog calendar list \
            --json --no-input --account "$primary_account"

        _gog_test_service "google.drive" "Drive" "$primary_account" "read+write" \
            gog drive ls \
            --json --no-input --max 1 --account "$primary_account"
    fi
}
