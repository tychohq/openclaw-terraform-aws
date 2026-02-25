#!/bin/bash
# Check: Voice transcription via Whisper skill

check_whisper() {
    section "VOICE TRANSCRIPTION (Whisper)"

    # Look for whisper skill in all skill directories
    local skill_found=false
    local skill_name_found=""
    local skill_path_found=""

    local npm_root=""
    npm_root=$(npm root -g 2>/dev/null || echo "")

    for skill_dir in \
        "$npm_root/openclaw/skills" \
        "$HOME/.openclaw/skills" \
        "$HOME/.agents/skills" \
        "$HOME/.openclaw/workspace/skills"; do
        for skill_name in openai-whisper-api whisper; do
            if [ -d "$skill_dir/$skill_name" ]; then
                skill_found=true
                skill_name_found="$skill_name"
                skill_path_found="$skill_dir/$skill_name"
                break 2
            fi
        done
    done

    if $skill_found; then
        report_result "whisper.skill" "pass" "Whisper skill found: $skill_name_found ($skill_path_found)"
    else
        report_result "whisper.skill" "fail" "Whisper skill not found" \
            "clawhub install openai-whisper-api"
    fi

    # OPENAI_API_KEY (env or .env file)
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
