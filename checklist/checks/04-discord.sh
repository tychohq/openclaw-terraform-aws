#!/bin/bash
# Check: Discord channel connectivity

check_discord() {
    section "DISCORD"

    local config_file="$HOME/.openclaw/openclaw.json"

    # Config file must exist (same path on both platforms)
    if [ ! -f "$config_file" ]; then
        report_result "discord.config" "fail" "openclaw.json not found at $config_file" \
            "Run: openclaw onboard"
        return
    fi

    if ! has_cmd jq; then
        local jq_remedy="brew install jq"
        $IS_LINUX && jq_remedy="dnf install -y jq  # or: apt install jq"
        report_result "discord.config" "fail" "jq not installed (required for config checks)" \
            "$jq_remedy"
        return
    fi

    # Discord section at .channels.discord (not top-level .discord)
    local discord_section
    discord_section=$(jq -r '.channels.discord // empty' "$config_file" 2>/dev/null)

    if [ -z "$discord_section" ] || [ "$discord_section" = "null" ]; then
        report_result "discord.config" "fail" "No .channels.discord section in openclaw.json" \
            "Add discord config under .channels.discord in ~/.openclaw/openclaw.json"
        return
    fi

    report_result "discord.config" "pass" "Discord config found at .channels.discord"

    # Bot token set (don't print it)
    local token
    token=$(jq -r '.channels.discord.token // empty' "$config_file" 2>/dev/null)

    if [ -n "$token" ] && [ "$token" != "null" ]; then
        report_result "discord.token" "pass" "Discord bot token is set"
    else
        report_result "discord.token" "fail" "Discord bot token not set" \
            "Set .channels.discord.token in ~/.openclaw/openclaw.json"
    fi

    # ── Recent connection in gateway logs (OS-aware) ──────────────────────────

    if $IS_LINUX && has_cmd journalctl; then
        local log_hits
        log_hits=$(journalctl --user -u openclaw-gateway --since "1 hour ago" 2>/dev/null \
            | grep -ci 'discord.*connect\|ready.*discord\|discord.*ready\|gateway.*discord' \
            || echo "0")

        if [ "$log_hits" -gt 0 ]; then
            report_result "discord.connection" "pass" "Discord connection seen in gateway logs (last hour)"
        else
            report_result "discord.connection" "warn" "No Discord connection entries in journal (last hour)" \
                "journalctl --user -u openclaw-gateway -n 100"
        fi

    elif $IS_MACOS; then
        local log_file="$HOME/.openclaw/logs/gateway.log"
        if [ -f "$log_file" ]; then
            local log_hits
            log_hits=$(tail -n 500 "$log_file" 2>/dev/null \
                | grep -ci 'discord.*connect\|ready.*discord\|discord.*ready\|gateway.*discord' \
                || echo "0")

            if [ "$log_hits" -gt 0 ]; then
                report_result "discord.connection" "pass" "Discord connection seen in gateway log (last 500 lines)"
            else
                report_result "discord.connection" "warn" "No Discord connection entries in gateway log" \
                    "tail -f ~/.openclaw/logs/gateway.log  # check live logs"
            fi
        else
            report_result "discord.connection" "skip" "Gateway log not found — skipping connection check" \
                "Start gateway: openclaw gateway start"
        fi

    else
        report_result "discord.connection" "skip" "Log check not supported on $OS_TYPE"
    fi
}
