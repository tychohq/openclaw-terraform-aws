#!/bin/bash
# Check: Image generation via Nano Banana Pro skill

check_image_gen() {
    section "IMAGE GENERATION (Nano Banana Pro)"

    # ── Skill readiness via openclaw skills check ──────────────────────────────
    # Skills in "Ready to use" have no parenthetical; missing ones show (bins: X) etc.

    if has_cmd openclaw; then
        local skills_output skill_line
        skills_output=$(safe_timeout 30 openclaw skills check 2>&1)
        skill_line=$(echo "$skills_output" | grep 'nano-banana-pro')

        if [ -z "$skill_line" ]; then
            report_result "image_gen.skill" "fail" \
                "nano-banana-pro skill not found" \
                "clawhub install nano-banana-pro"
        elif echo "$skill_line" | grep -qE '\(bins:|\(env:|\(config:'; then
            local requirement
            requirement=$(echo "$skill_line" | grep -oE '\(.*\)')
            report_result "image_gen.skill" "fail" \
                "nano-banana-pro has unmet requirements: $requirement" \
                "clawhub install nano-banana-pro  # or install required binaries/env vars"
        else
            report_result "image_gen.skill" "pass" "nano-banana-pro skill: ready to use"
        fi
    else
        report_result "image_gen.skill" "skip" \
            "openclaw CLI not found — cannot check skill status"
    fi

    # ── Gemini API key (env or .env file) ─────────────────────────────────────
    local env_file="$HOME/.openclaw/.env"
    local key_set=false

    for key_name in GEMINI_API_KEY GOOGLE_AI_API_KEY; do
        local key_val="${!key_name:-}"
        if [ -n "$key_val" ]; then
            key_set=true
            break
        fi
        if [ -f "$env_file" ] && grep -q "^${key_name}=." "$env_file" 2>/dev/null; then
            key_set=true
            break
        fi
    done

    if $key_set; then
        report_result "image_gen.api_key" "pass" "Gemini API key is set"
    else
        report_result "image_gen.api_key" "fail" \
            "Gemini API key not set (GEMINI_API_KEY or GOOGLE_AI_API_KEY)" \
            "Add GEMINI_API_KEY=... to ~/.openclaw/.env"
    fi
}
