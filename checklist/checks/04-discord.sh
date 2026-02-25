#!/bin/bash
# Check: Discord channel connectivity

check_discord() {
    section "DISCORD"

    local config_file="$HOME/.openclaw/openclaw.json"

    # Config file must exist
    if [ ! -f "$config_file" ]; then
        report_result "discord.config" "fail" "openclaw.json not found at $config_file" \
            "Run: openclaw onboard"
        return
    fi

    if ! has_cmd jq; then
        report_result "discord.config" "fail" "jq not installed (required for config checks)" \
            "dnf install -y jq"
        return
    fi

    # Discord section present in config
    local discord_section
    discord_section=$(jq -r '.discord // empty' "$config_file" 2>/dev/null)

    if [ -z "$discord_section" ] || [ "$discord_section" = "null" ]; then
        report_result "discord.config" "fail" "No discord section in openclaw.json" \
            "Add discord config to ~/.openclaw/openclaw.json"
        return
    fi

    report_result "discord.config" "pass" "Discord section present in config"

    # Bot token set (don't print it)
    local token
    token=$(jq -r '.discord.token // empty' "$config_file" 2>/dev/null)

    if [ -n "$token" ] && [ "$token" != "null" ]; then
        report_result "discord.token" "pass" "Discord bot token is set"
    else
        report_result "discord.token" "fail" "Discord bot token not set" \
            "Set discord.token in ~/.openclaw/openclaw.json"
    fi

    # Recent connection in gateway logs (last hour)
    if has_cmd journalctl; then
        local log_hits
        log_hits=$(journalctl --user -u openclaw-gateway --since "1 hour ago" 2>/dev/null \
            | grep -ci 'discord.*connect\|ready.*discord\|discord.*ready\|gateway.*discord' \
            || echo "0")

        if [ "$log_hits" -gt 0 ]; then
            report_result "discord.connection" "pass" "Discord connection seen in gateway logs (last hour)"
        else
            report_result "discord.connection" "warn" "No Discord connection log entries in last hour" \
                "journalctl --user -u openclaw-gateway -n 100  # check recent logs"
        fi
    else
        report_result "discord.connection" "skip" "journalctl not available — skipping log check"
    fi
}
