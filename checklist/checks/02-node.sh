#!/bin/bash
# Check: Node.js version and package managers

check_node() {
    section "NODE.JS"

    # Node.js version >= 20
    if has_cmd node; then
        local version major
        version=$(node --version 2>/dev/null | tr -d 'v')
        major=$(echo "$version" | cut -d. -f1)
        if [ "${major:-0}" -ge 20 ]; then
            report_result "node.version" "pass" "Node.js v$version (>= 20 required)"
        else
            report_result "node.version" "fail" "Node.js v$version is too old (need >= 20)" \
                "curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf install -y nodejs"
        fi
    else
        report_result "node.version" "fail" "Node.js not installed" \
            "curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf install -y nodejs"
    fi

    # npm
    if has_cmd npm; then
        local npm_ver
        npm_ver=$(npm --version 2>/dev/null || echo "unknown")
        report_result "node.npm" "pass" "npm $npm_ver available"
    else
        report_result "node.npm" "warn" "npm not found" \
            "npm is bundled with Node.js — reinstall Node.js"
    fi

    # bun (optional)
    if has_cmd bun; then
        local bun_ver
        bun_ver=$(bun --version 2>/dev/null || echo "unknown")
        report_result "node.bun" "pass" "bun $bun_ver available"
    else
        report_result "node.bun" "skip" "bun not installed (optional)"
    fi
}
