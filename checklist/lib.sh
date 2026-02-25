#!/bin/bash
# Shared helpers for checklist checks

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# Result counters (global)
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

# JSON results array (for --json output)
JSON_RESULTS="[]"

# JSON mode flag — set to true by runner when --json is passed
CHECKLIST_JSON=${CHECKLIST_JSON:-false}

# Report a check result
# Usage: report_result "check_id" "status" "message" ["remediation"]
# status: pass | fail | warn | skip
report_result() {
    local id="$1" status="$2" msg="$3" remedy="${4:-}"

    # Increment counter
    case "$status" in
        pass) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        fail) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        warn) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        skip) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    esac

    # Print colored output (suppressed in JSON mode)
    if [ "$CHECKLIST_JSON" != "true" ]; then
        case "$status" in
            pass) echo -e "  ${GREEN}✅${NC} $msg" ;;
            fail) echo -e "  ${RED}❌${NC} $msg"
                  [ -n "$remedy" ] && echo -e "     ${DIM}→ $remedy${NC}" ;;
            warn) echo -e "  ${YELLOW}⚠️${NC}  $msg"
                  [ -n "$remedy" ] && echo -e "     ${DIM}→ $remedy${NC}" ;;
            skip) echo -e "  ${DIM}⏭️  $msg (skipped)${NC}" ;;
        esac
    fi

    # Append to JSON (requires jq)
    if command -v jq &>/dev/null; then
        local json_entry
        json_entry=$(jq -n \
            --arg id "$id" \
            --arg status "$status" \
            --arg message "$msg" \
            --arg remedy "$remedy" \
            '{id: $id, status: $status, message: $message, remedy: $remedy}')
        JSON_RESULTS=$(echo "$JSON_RESULTS" | jq --argjson entry "$json_entry" '. + [$entry]')
    fi
}

# Print section header
# Usage: section "CORE INFRASTRUCTURE"
section() {
    if [ "$CHECKLIST_JSON" != "true" ]; then
        echo ""
        echo -e "  ${CYAN}$1${NC}"
    fi
}

# Check if a config key is enabled
# Usage: is_enabled "gateway"
# Reads from CHECKLIST_CONF associative array (set by runner)
is_enabled() {
    local key="CHECK_${1^^}"
    [ "${CHECKLIST_CONF[$key]:-false}" = "true" ]
}

# Check if a command exists
# Usage: has_cmd "gog"
has_cmd() {
    command -v "$1" &>/dev/null
}

# Get installed npm package version
# Usage: get_npm_version "openclaw"
get_npm_version() {
    local pkg="$1"
    local version
    version=$("$pkg" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "${version:-unknown}"
}

# Get latest npm registry version
# Usage: get_npm_latest "openclaw"
get_npm_latest() {
    local pkg="$1"
    npm view "$pkg" version 2>/dev/null || echo "unknown"
}
