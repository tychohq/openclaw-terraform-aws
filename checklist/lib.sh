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

# OS detection (auto — no user config needed)
OS_TYPE="$(uname -s)"   # Darwin or Linux
IS_MACOS=false
IS_LINUX=false
[[ "$OS_TYPE" == "Darwin" ]] && IS_MACOS=true
[[ "$OS_TYPE" == "Linux" ]]  && IS_LINUX=true

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

# Print a purely informational message — no pass/fail, no counter change
# Usage: info_msg "Model: claude-opus-4-6 (200k context window)"
info_msg() {
    local msg="$1"
    if [ "$CHECKLIST_JSON" != "true" ]; then
        echo -e "  ${BLUE}ℹ️${NC}  $msg"
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

# Portable timeout — Linux has timeout(1), macOS typically does not
# Falls back to running the command without a time limit
# Usage: safe_timeout <seconds> <cmd> [args...]
safe_timeout() {
    local secs="$1"
    shift
    if has_cmd timeout; then
        timeout "$secs" "$@"
    elif has_cmd gtimeout; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
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

# npm command — configurable for systems with npm wrappers (e.g. npm-real)
# Set NPM_CMD in checklist.conf to override. Runner updates this after config loads.
NPM_CMD="npm"

# Query npm registry for the latest version of a package.
# Uses $NPM_CMD so users can set NPM_CMD=npm-real in checklist.conf if their
# system has a bun-redirect wrapper at /opt/homebrew/bin/npm.
# Usage: npm_view "openclaw"
npm_view() {
    safe_timeout 5 $NPM_CMD view "$1" version 2>/dev/null
}

# Check if the OpenClaw gateway process is running (OS-aware)
# Returns 0 if running, 1 if not
gateway_is_running() {
    if $IS_LINUX; then
        safe_timeout 5 systemctl --user is-active openclaw-gateway &>/dev/null 2>&1
    elif $IS_MACOS; then
        launchctl list ai.openclaw.gateway 2>/dev/null | grep -q '"PID"'
    else
        return 1
    fi
}

# Get the configured gateway port from openclaw.json (empty if not found)
get_gateway_port() {
    if has_cmd jq && [ -f "$HOME/.openclaw/openclaw.json" ]; then
        jq -r '.gateway.port // empty' "$HOME/.openclaw/openclaw.json" 2>/dev/null
    fi
}
