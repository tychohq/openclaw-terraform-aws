#!/bin/bash
# Check: Speech-to-text / voice transcription backend

check_speech_to_text() {
    section "SPEECH-TO-TEXT"

    local config_file="$HOME/.openclaw/openclaw.json"

    if ! has_cmd jq; then
        report_result "voice.config" "fail" "jq not installed (required for config parsing)" \
            "brew install jq"
        return
    fi

    if [ ! -f "$config_file" ]; then
        report_result "voice.config" "fail" "openclaw.json not found at $config_file" \
            "Run: openclaw onboard"
        return
    fi

    # ── Enabled check ─────────────────────────────────────────────────────────
    local enabled
    enabled=$(jq -r '.tools.media.audio.enabled // false' "$config_file" 2>/dev/null)

    if [ "$enabled" != "true" ]; then
        report_result "voice.enabled" "warn" "Audio transcription not enabled in openclaw.json" \
            "Set .tools.media.audio.enabled=true in ~/.openclaw/openclaw.json"
        return
    fi

    report_result "voice.enabled" "pass" "Audio transcription enabled"

    # ── Backend models ─────────────────────────────────────────────────────────
    local model_count
    model_count=$(jq '.tools.media.audio.models | length' "$config_file" 2>/dev/null || echo 0)

    if [ "${model_count:-0}" -eq 0 ]; then
        report_result "voice.backend" "warn" "No transcription backends configured in .tools.media.audio.models" \
            "Add a model entry to .tools.media.audio.models in openclaw.json"
        return
    fi

    local found_cli=false found_api=false
    local i=0
    while [ "$i" -lt "$model_count" ]; do
        local type cmd bin_name
        type=$(jq -r ".tools.media.audio.models[$i].type" "$config_file" 2>/dev/null)

        if [ "$type" = "cli" ]; then
            found_cli=true
            cmd=$(jq -r ".tools.media.audio.models[$i].command" "$config_file" 2>/dev/null)
            bin_name=$(basename "$cmd")

            if [ -x "$cmd" ]; then
                report_result "voice.backend.cli" "pass" \
                    "Local transcription: $bin_name (exists at $cmd)"
            elif [ -f "$cmd" ]; then
                report_result "voice.backend.cli" "warn" \
                    "Local transcription: $bin_name (not executable at $cmd)" \
                    "chmod +x $cmd"
            else
                report_result "voice.backend.cli" "fail" \
                    "Local transcription: $bin_name (binary not found at $cmd)" \
                    "Install the binary or update .tools.media.audio.models[].command in openclaw.json"
            fi

        elif echo "$type" | grep -qiE '^(openai|whisper.?api)'; then
            found_api=true
            report_result "voice.backend.api" "pass" "Whisper API backend configured (type: $type)"

            # API key check
            local env_file="$HOME/.openclaw/.env"
            local key_set=false
            local key_val="${OPENAI_API_KEY:-}"
            if [ -n "$key_val" ]; then
                key_set=true
            elif [ -f "$env_file" ] && grep -q "^OPENAI_API_KEY=." "$env_file" 2>/dev/null; then
                key_set=true
            fi

            if $key_set; then
                report_result "voice.backend.api_key" "pass" "OPENAI_API_KEY is set"
            else
                report_result "voice.backend.api_key" "fail" "OPENAI_API_KEY not set" \
                    "Add OPENAI_API_KEY=sk-... to ~/.openclaw/.env"
            fi
        else
            report_result "voice.backend.$i" "pass" "Backend type: $type"
        fi

        i=$((i + 1))
    done

    # ── Whisper API skill (fallback / cloud option) ────────────────────────────
    if has_cmd openclaw; then
        local skills_output skill_line
        skills_output=$(safe_timeout 30 openclaw skills check 2>&1)
        skill_line=$(echo "$skills_output" | grep 'openai-whisper-api')

        if [ -z "$skill_line" ]; then
            report_result "voice.whisper_skill" "skip" \
                "Whisper API fallback skill: not installed" \
                "clawhub install openai-whisper-api"
        elif echo "$skill_line" | grep -qE '\(bins:|\(env:|\(config:'; then
            local requirement
            requirement=$(echo "$skill_line" | grep -oE '\(.*\)')
            report_result "voice.whisper_skill" "skip" \
                "Whisper API fallback skill: available but missing requirements $requirement"
        else
            report_result "voice.whisper_skill" "pass" \
                "Whisper API fallback skill: ready to use (openai-whisper-api)"
        fi
    else
        report_result "voice.whisper_skill" "skip" \
            "openclaw CLI not found — cannot check Whisper API fallback skill"
    fi
}
