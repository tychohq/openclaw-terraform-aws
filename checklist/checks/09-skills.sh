#!/bin/bash
# Check: Skill inventory via openclaw skills check

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

    # Parse summary counts from the header block:
    #   Total: 97
    #   ✓ Eligible: 68
    #   ⏸ Disabled: 0
    #   🚫 Blocked by allowlist: 0
    #   ✗ Missing requirements: 29
    local total eligible disabled missing blocked
    total=$(echo "$skills_output" | awk '/Total:/{print $NF}' | head -1)
    eligible=$(echo "$skills_output" | awk '/Eligible:/{print $NF}' | head -1)
    disabled=$(echo "$skills_output" | awk '/Disabled:/{print $NF}' | head -1)
    # Missing requirements appears both as a count line ("✗ Missing requirements: 29")
    # and as a section header ("Missing requirements:"). Match only lines ending in digits.
    missing=$(echo "$skills_output" | awk '/Missing requirements: [0-9]/{print $NF}' | head -1)
    blocked=$(echo "$skills_output" | awk '/Blocked by allowlist:/{print $NF}' | head -1)

    if [ -z "$total" ]; then
        report_result "skills.status" "warn" \
            "Could not parse skill counts from openclaw skills check" \
            "openclaw skills check  # check manually"
        return
    fi

    report_result "skills.summary" "pass" \
        "Skills: $total total · $eligible eligible · ${missing:-0} missing requirements"

    [ "${disabled:-0}" -gt 0 ] && \
        report_result "skills.disabled" "skip" "$disabled skills disabled"

    [ "${blocked:-0}" -gt 0 ] && \
        report_result "skills.blocked" "skip" "$blocked skills blocked by allowlist"

    if [ "${missing:-0}" -gt 0 ]; then
        report_result "skills.missing" "skip" \
            "$missing skills have unmet requirements (bins/env/config)" \
            "openclaw skills check  # see full list of missing requirements"
    fi
}
