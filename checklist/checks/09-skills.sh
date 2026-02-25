#!/bin/bash
# Check: Skill inventory across all skill directories

check_skills() {
    section "SKILLS"

    local total_skills=0
    local broken_skills=0

    # Find bundled skills — check npm global then bun global (bun takes precedence)
    local bundled_dir=""
    local npm_root
    npm_root=$($NPM_CMD root -g 2>/dev/null || echo "")
    [ -d "$npm_root/openclaw/skills" ] && bundled_dir="$npm_root/openclaw/skills"
    local bun_skills="$HOME/.bun/install/global/node_modules/openclaw/skills"
    [ -d "$bun_skills" ] && bundled_dir="$bun_skills"

    # Build list of skill directories with labels
    local skill_dirs=()
    [ -n "$bundled_dir" ] && skill_dirs+=("$bundled_dir:bundled")
    [ -d "$HOME/.openclaw/skills" ] && \
        skill_dirs+=("$HOME/.openclaw/skills:clawhub")
    [ -d "$HOME/.agents/skills" ] && \
        skill_dirs+=("$HOME/.agents/skills:personal")
    [ -d "$HOME/.openclaw/workspace/skills" ] && \
        skill_dirs+=("$HOME/.openclaw/workspace/skills:workspace")

    if [ "${#skill_dirs[@]}" -eq 0 ]; then
        report_result "skills.dirs" "warn" "No skill directories found" \
            "Install skills with: clawhub install <skill-name>"
        return
    fi

    for dir_entry in "${skill_dirs[@]}"; do
        local dir="${dir_entry%%:*}"
        local label="${dir_entry##*:}"
        local count=0
        local broken=0
        local names=()

        while IFS= read -r -d '' skill_dir; do
            local skill_name
            skill_name=$(basename "$skill_dir")
            count=$((count + 1))
            names+=("$skill_name")

            if [ ! -f "$skill_dir/SKILL.md" ]; then
                broken=$((broken + 1))
                report_result "skills.broken.$skill_name" "warn" \
                    "Skill '$skill_name' ($label) is missing SKILL.md" \
                    "Fix or remove: $skill_dir"
            fi
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

        total_skills=$((total_skills + count))
        broken_skills=$((broken_skills + broken))

        if [ "$count" -gt 0 ]; then
            report_result "skills.$label" "pass" "$label ($count): ${names[*]}"
        else
            report_result "skills.$label" "skip" "No $label skills installed"
        fi
    done

    # Overall summary
    if [ "$total_skills" -eq 0 ]; then
        report_result "skills.total" "warn" "No skills installed in any directory" \
            "Browse available skills: clawhub search"
    elif [ "$broken_skills" -eq 0 ]; then
        report_result "skills.total" "pass" "Total: $total_skills skills, all have SKILL.md"
    else
        report_result "skills.total" "warn" \
            "Total: $total_skills skills, $broken_skills missing SKILL.md" \
            "Review and fix broken skills listed above"
    fi
}
