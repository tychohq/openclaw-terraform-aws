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

    # npm — uses $NPM_CMD (set via NPM_CMD in checklist.conf, default: npm)
    if has_cmd "$NPM_CMD"; then
        local npm_ver
        npm_ver=$($NPM_CMD --version 2>/dev/null || echo "unknown")
        report_result "node.npm" "pass" "$NPM_CMD $npm_ver available"
    else
        report_result "node.npm" "warn" "$NPM_CMD not found" \
            "Set NPM_CMD in checklist.conf to point to your npm binary"
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
