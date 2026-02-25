#!/bin/bash
# Check: Node.js version and package managers

check_node() {
    section "NODE.JS"

    # Node.js version >= 20
    local node_install_remedy="curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf install -y nodejs"
    $IS_MACOS && node_install_remedy="brew install node@22  # or: https://nodejs.org"

    if has_cmd node; then
        local version major
        version=$(node --version 2>/dev/null | tr -d 'v')
        major=$(echo "$version" | cut -d. -f1)
        if [ "${major:-0}" -ge 20 ]; then
            report_result "node.version" "pass" "Node.js v$version (>= 20 required)"
        else
            report_result "node.version" "fail" "Node.js v$version is too old (need >= 20)" \
                "$node_install_remedy"
        fi
    else
        report_result "node.version" "fail" "Node.js not installed" \
            "$node_install_remedy"
    fi

    # npm — detect macOS homebrew bun-redirect wrapper
    if has_cmd npm; then
        local npm_ver_out
        npm_ver_out=$(npm --version 2>&1)
        if echo "$npm_ver_out" | grep -qE '^[0-9]+\.[0-9]'; then
            # Real npm — version looks like a semver
            report_result "node.npm" "pass" "npm $npm_ver_out available"
        elif $IS_MACOS && has_cmd npm-real; then
            local real_ver
            real_ver=$(npm-real --version 2>/dev/null || echo "unknown")
            report_result "node.npm" "pass" "npm-real $real_ver available (homebrew npm is a bun redirect)"
        else
            report_result "node.npm" "skip" "npm is a bun redirect wrapper — use bun for package management"
        fi
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
