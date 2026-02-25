#!/bin/bash
# Check: Discord channel connectivity via openclaw health

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

    # Look for Discord line: "Discord: ok (@BotName) (995ms)"
    local discord_line
    discord_line=$(echo "$health_output" | grep -i '^Discord:')

    if [ -z "$discord_line" ]; then
        report_result "discord.connected" "warn" \
            "Discord not reported in openclaw health output" \
            "openclaw health  # check full output"
        return
    fi

    if echo "$discord_line" | grep -q ': ok'; then
        report_result "discord.connected" "pass" "$discord_line"
    else
        report_result "discord.connected" "warn" \
            "Discord status: $discord_line" \
            "openclaw health  # diagnose"
    fi
}
