#!/bin/bash
# Check: Slack channel connectivity + bot config via openclaw health + config

check_slack() {
    section "SLACK"

    if ! has_cmd openclaw; then
        report_result "slack.connected" "fail" "openclaw CLI not found" \
            "Install openclaw to check Slack status"
        return
    fi

    local health_output
    health_output=$(safe_timeout 20 openclaw health 2>&1)

    if [ -z "$health_output" ]; then
        report_result "slack.connected" "fail" \
            "openclaw health returned no output — gateway may not be running" \
            "openclaw gateway start"
        return
    fi

    # Look for Slack line: "Slack: ok (224ms)"
    local slack_line
    slack_line=$(echo "$health_output" | grep -i '^Slack:')

    if [ -z "$slack_line" ]; then
        report_result "slack.connected" "warn" \
            "Slack not reported in openclaw health output" \
            "openclaw health  # check full output; is channels.slack.enabled=true?"
        return
    fi

    if echo "$slack_line" | grep -q ': ok'; then
        report_result "slack.connected" "pass" "$slack_line"
    else
        report_result "slack.connected" "warn" \
            "Slack status: $slack_line" \
            "openclaw health  # diagnose"
        return
    fi

    # ── Bot & policy details from config ──────────────────────────────────
    local slack_config
    slack_config=$(safe_timeout 10 openclaw config get channels.slack 2>/dev/null)

    if [ -z "$slack_config" ] || ! echo "$slack_config" | jq empty 2>/dev/null; then
        return  # can't parse config, skip details
    fi

    # Connection mode
    local mode
    mode=$(echo "$slack_config" | jq -r '.mode // "unknown"')
    report_result "slack.mode" "pass" "Connection mode: $mode"

    # DM policy
    local dm_policy
    dm_policy=$(echo "$slack_config" | jq -r '.dmPolicy // "open"')
    if [ "$dm_policy" = "allowlist" ]; then
        local allow_from allow_count
        allow_from=$(echo "$slack_config" | jq -r '.allowFrom // [] | join(", ")')
        allow_count=$(echo "$slack_config" | jq -r '.allowFrom // [] | length')

        # Try to resolve Slack user IDs to names
        local resolved_users="$allow_from"
        if [ "$allow_count" -gt 0 ] && [ "$allow_count" -le 10 ]; then
            local resolved_list=""
            for uid in $(echo "$slack_config" | jq -r '.allowFrom // [] | .[]'); do
                local uname
                uname=$(safe_timeout 5 openclaw config get "channels.slack.allowFrom" 2>/dev/null | \
                    jq -r ".[] // empty" 2>/dev/null | head -1)
                # Slack IDs start with U — we can't resolve without Slack API access
                # Just show the IDs
                if [ -n "$resolved_list" ]; then
                    resolved_list="$resolved_list, $uid"
                else
                    resolved_list="$uid"
                fi
            done
            resolved_users="$resolved_list"
        fi

        report_result "slack.dm_policy" "pass" \
            "DM policy: allowlist ($allow_count user(s): $resolved_users)"
    elif [ "$dm_policy" = "open" ]; then
        report_result "slack.dm_policy" "warn" \
            "DM policy: open (anyone can DM the bot)" \
            "openclaw config set channels.slack.dmPolicy allowlist  # restrict access"
    elif [ "$dm_policy" = "disabled" ]; then
        report_result "slack.dm_policy" "pass" "DM policy: disabled"
    else
        report_result "slack.dm_policy" "pass" "DM policy: $dm_policy"
    fi

    # Group policy
    local group_policy
    group_policy=$(echo "$slack_config" | jq -r '.groupPolicy // "disabled"')
    report_result "slack.group_policy" "pass" "Group policy: $group_policy"

    # Streaming
    local streaming
    streaming=$(echo "$slack_config" | jq -r '.streaming // "off"')
    local native_streaming
    native_streaming=$(echo "$slack_config" | jq -r '.nativeStreaming // false')
    if [ "$native_streaming" = "true" ]; then
        report_result "slack.streaming" "pass" "Streaming: $streaming (native)"
    else
        report_result "slack.streaming" "pass" "Streaming: $streaming"
    fi
}
