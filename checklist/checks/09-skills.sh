#!/bin/bash
# Check: Skill inventory via openclaw skills check + source directory counts

check_skills() {
    section "SKILLS"

    if ! has_cmd openclaw; then
        report_result "skills.status" "fail" "openclaw CLI not found" \
            "Install openclaw to check skills"
        return
    fi

    local skills_output
    skills_output=$(safe_timeout 30 openclaw skills check 2>&1)

    if [ -z "$skills_output" ]; then
        report_result "skills.status" "fail" \
            "openclaw skills check returned no output"
        return
    fi

    # ── Summary counts ─────────────────────────────────────────────────────────
    # Lines: "Total: 97", "✓ Eligible: 68", "⏸ Disabled: 0", etc.
    # "Missing requirements:" appears both as count line and section header;
    # use the version ending in a digit to avoid double-matching.
    local total eligible disabled missing blocked
    total=$(echo "$skills_output"   | awk '/Total:/{print $NF}'   | head -1)
    eligible=$(echo "$skills_output" | awk '/Eligible:/{print $NF}' | head -1)
    disabled=$(echo "$skills_output" | awk '/Disabled:/{print $NF}' | head -1)
    missing=$(echo "$skills_output"  | awk '/Missing requirements: [0-9]/{print $NF}' | head -1)
    blocked=$(echo "$skills_output"  | awk '/Blocked by allowlist:/{print $NF}' | head -1)

    if [ -z "$total" ]; then
        report_result "skills.status" "warn" \
            "Could not parse skill counts from openclaw skills check" \
            "openclaw skills check  # check manually"
        return
    fi

    report_result "skills.summary" "pass" \
        "${eligible:-0} ready to use · ${missing:-0} available but need setup · ${total} total"

    [ "${disabled:-0}" -gt 0 ] && \
        report_result "skills.disabled" "skip" "$disabled skills disabled"

    [ "${blocked:-0}" -gt 0 ] && \
        report_result "skills.blocked" "skip" "$blocked skills blocked by allowlist"

    # ── Source directories ─────────────────────────────────────────────────────
    local npm_root=""
    npm_root=$($NPM_CMD root -g 2>/dev/null || echo "")
    local bundled_dir=""
    [ -d "$npm_root/openclaw/skills" ] && bundled_dir="$npm_root/openclaw/skills"
    local bun_skills="$HOME/.bun/install/global/node_modules/openclaw/skills"
    [ -d "$bun_skills" ] && bundled_dir="$bun_skills"

    local count_bundled=0 count_clawhub=0 count_personal=0 count_workspace=0
    [ -n "$bundled_dir" ] && \
        count_bundled=$(find "$bundled_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
            wc -l | tr -d ' ')
    [ -d "$HOME/.openclaw/skills" ] && \
        count_clawhub=$(find "$HOME/.openclaw/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
            wc -l | tr -d ' ')
    [ -d "$HOME/.agents/skills" ] && \
        count_personal=$(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
            wc -l | tr -d ' ')
    [ -d "$HOME/.openclaw/workspace/skills" ] && \
        count_workspace=$(find "$HOME/.openclaw/workspace/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | \
            wc -l | tr -d ' ')

    local total_from_dirs=$(( count_bundled + count_clawhub + count_personal + count_workspace ))
    report_result "skills.sources" "pass" \
        "Sources ($total_from_dirs skills): Bundled $count_bundled · ClawHub $count_clawhub · Personal $count_personal · Workspace $count_workspace"

    # ── Missing requirements detail (info, not warning) ────────────────────────
    if [ "${missing:-0}" -gt 0 ]; then
        # Extract "skillname (requirement)" from the Missing requirements section,
        # normalise (bins:/env:/config:/anyBins:) → "needs:"
        local missing_detail
        missing_detail=$(echo "$skills_output" | \
            awk '/Missing requirements:/{found=1; next} found && /^  /{print} found && !/^  /{found=0}' | \
            grep -oE '[a-zA-Z0-9_-]+ \(.*\)' | \
            sed 's/(bins: /(needs: /; s/(env: /(needs: /; s/(config: /(needs: /; s/(anyBins: /(needs: /' | \
            head -5 | tr '\n' ',' | sed 's/,$//')

        local more_count=$(( missing - 5 ))
        local suffix=""
        [ "$more_count" -gt 0 ] && suffix=" +$more_count more"

        report_result "skills.missing" "skip" \
            "${missing} available, need setup: ${missing_detail}${suffix}" \
            "openclaw skills check  # see full list of missing requirements"
    fi
}
