#!/bin/bash
# Check: Voice transcription via Whisper skill

check_whisper() {
    section "VOICE TRANSCRIPTION (Whisper)"

    # ── Skill readiness via openclaw skills check ──────────────────────────────
    # Skills in "Ready to use" have no parenthetical; missing ones show (bins: X) etc.

    if has_cmd openclaw; then
        local skills_output skill_line skill_name_found=""
        skills_output=$(safe_timeout 30 openclaw skills check 2>&1)

        # Try each known whisper skill name in order of preference
        for skill_name in openai-whisper-api openai-whisper whisper; do
            skill_line=$(echo "$skills_output" | grep "$skill_name")
            if [ -n "$skill_line" ]; then
                skill_name_found="$skill_name"
                break
            fi
        done

        if [ -z "$skill_name_found" ]; then
            report_result "whisper.skill" "fail" \
                "Whisper skill not found in openclaw skills check" \
                "clawhub install openai-whisper-api"
        elif echo "$skill_line" | grep -qE '\(bins:|\(env:|\(config:'; then
            local requirement
            requirement=$(echo "$skill_line" | grep -oE '\(.*\)')
            report_result "whisper.skill" "fail" \
                "$skill_name_found has unmet requirements: $requirement" \
                "clawhub install openai-whisper-api  # or install required binaries/env vars"
        else
            report_result "whisper.skill" "pass" "Whisper skill ready to use ($skill_name_found)"
        fi
    else
        report_result "whisper.skill" "skip" \
            "openclaw CLI not found — cannot check skill status"
    fi

    # ── OPENAI_API_KEY (env or .env file) ─────────────────────────────────────
    local env_file="$HOME/.openclaw/.env"
    local key_set=false

    local key_val="${OPENAI_API_KEY:-}"
    if [ -n "$key_val" ]; then
        key_set=true
    elif [ -f "$env_file" ] && grep -q "^OPENAI_API_KEY=." "$env_file" 2>/dev/null; then
        key_set=true
    fi

    if $key_set; then
        report_result "whisper.api_key" "pass" "OPENAI_API_KEY is set"
    else
        report_result "whisper.api_key" "fail" "OPENAI_API_KEY not set" \
            "Add OPENAI_API_KEY=sk-... to ~/.openclaw/.env"
    fi
}
