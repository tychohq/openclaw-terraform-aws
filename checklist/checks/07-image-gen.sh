#!/bin/bash
# Check: Image generation via Nano Banana Pro skill

check_image_gen() {
    section "IMAGE GENERATION (Nano Banana Pro)"

    # Look for nano-banana-pro skill — check npm global, bun global, and user dirs
    local skill_found=false
    local skill_path_found=""

    local npm_root=""
    npm_root=$($NPM_CMD root -g 2>/dev/null || echo "")

    for skill_dir in \
        "$npm_root/openclaw/skills" \
        "$HOME/.bun/install/global/node_modules/openclaw/skills" \
        "$HOME/.openclaw/skills" \
        "$HOME/.agents/skills" \
        "$HOME/.openclaw/workspace/skills"; do
        if [ -d "$skill_dir/nano-banana-pro" ]; then
            skill_found=true
            skill_path_found="$skill_dir/nano-banana-pro"
            break
        fi
    done

    if $skill_found; then
        report_result "image_gen.skill" "pass" "nano-banana-pro skill found ($skill_path_found)"
    else
        report_result "image_gen.skill" "fail" "nano-banana-pro skill not found" \
            "clawhub install nano-banana-pro"
    fi

    # Check Gemini API key (env or .env file)
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
        report_result "image_gen.api_key" "fail" "Gemini API key not set (GEMINI_API_KEY or GOOGLE_AI_API_KEY)" \
            "Add GEMINI_API_KEY=... to ~/.openclaw/.env"
    fi
}
