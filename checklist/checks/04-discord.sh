#!/bin/bash
# Check: Discord channel connectivity + bot config via openclaw health + config

check_discord() {
    section "DISCORD"

    if ! has_cmd openclaw; then
        report_result "discord.connected" "fail" "openclaw CLI not found" \
            "Install openclaw to check Discord status"
        return
    fi

    local health_output
    health_output=$(safe_timeout 20 openclaw health 2>&1)

    if [ -z "$health_output" ]; then
        report_result "discord.connected" "fail" \
            "openclaw health returned no output — gateway may not be running" \
            "openclaw gateway start"
        return
    fi

    # Look for Discord line: "Discord: ok (@Axel) (995ms)"
    local discord_line
    discord_line=$(echo "$health_output" | grep -i '^Discord:')

    if [ -z "$discord_line" ]; then
        report_result "discord.connected" "warn" \
            "Discord not reported in openclaw health output" \
            "openclaw health  # check full output; is channels.discord.enabled=true?"
        return
    fi

    if echo "$discord_line" | grep -q ': ok'; then
        report_result "discord.connected" "pass" "$discord_line"
    else
        report_result "discord.connected" "warn" \
            "Discord status: $discord_line" \
            "openclaw health  # diagnose"
        return
    fi

    # ── Bot & policy details from config ──────────────────────────────────
    local discord_config
    discord_config=$(safe_timeout 10 openclaw config get channels.discord 2>/dev/null)

    if [ -z "$discord_config" ] || ! echo "$discord_config" | jq empty 2>/dev/null; then
        return  # can't parse config, skip details
    fi

    # Bot name (from health output): "Discord: ok (@Axel) (995ms)" → "Axel"
    local bot_name
    bot_name=$(echo "$discord_line" | grep -oE '\(@[^)]+\)' | tr -d '(@)')
    [ -n "$bot_name" ] && info_msg "Bot: @$bot_name"

    # DM policy
    local dm_policy
    dm_policy=$(echo "$discord_config" | jq -r '.dmPolicy // "open"')
    if [ "$dm_policy" = "allowlist" ]; then
        local allow_from allow_count
        allow_from=$(echo "$discord_config" | jq -r '.allowFrom // [] | join(", ")')
        allow_count=$(echo "$discord_config" | jq -r '.allowFrom // [] | length')

        report_result "discord.dm_policy" "pass" \
            "DM policy: allowlist ($allow_count user(s): $allow_from)"
    elif [ "$dm_policy" = "open" ]; then
        report_result "discord.dm_policy" "warn" \
            "DM policy: open (anyone can DM the bot)" \
            "Set channels.discord.dmPolicy=allowlist in openclaw.json"
    elif [ "$dm_policy" = "disabled" ]; then
        report_result "discord.dm_policy" "pass" "DM policy: disabled"
    else
        report_result "discord.dm_policy" "pass" "DM policy: $dm_policy"
    fi

    # Group policy
    local group_policy
    group_policy=$(echo "$discord_config" | jq -r '.groupPolicy // "disabled"')
    if [ "$group_policy" = "disabled" ]; then
        report_result "discord.group_policy" "pass" "Group policy: disabled"
    elif [ "$group_policy" = "allowlist" ]; then
        local group_allow
        group_allow=$(echo "$discord_config" | jq -r '.allowGroups // [] | join(", ")')
        report_result "discord.group_policy" "pass" \
            "Group policy: allowlist (groups: $group_allow)"
    else
        report_result "discord.group_policy" "pass" "Group policy: $group_policy"
    fi

    # Guild/server ID
    local guild_id
    guild_id=$(echo "$discord_config" | jq -r '.guildId // empty')
    [ -n "$guild_id" ] && info_msg "Guild: $guild_id"
}
