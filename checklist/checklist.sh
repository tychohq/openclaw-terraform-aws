#!/bin/bash
# OpenClaw Deployment Health Check — Main Runner

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# ── Parse Arguments ──────────────────────────────────────────────────────────

JSON_OUTPUT=false
SINGLE_CHECK=""
CONF_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            JSON_OUTPUT=true
            CHECKLIST_JSON=true
            ;;
        --config)
            shift
            CONF_PATH="$1"
            ;;
        --check)
            shift
            SINGLE_CHECK="$1"
            ;;
        -h|--help)
            echo "Usage: $0 [--json] [--config <path>] [--check <id>]"
            echo ""
            echo "  --json            Output results as JSON"
            echo "  --config <path>   Path to checklist.conf (default: same dir or ~/.openclaw/)"
            echo "  --check <id>      Run a single check (e.g. gateway, disk, github)"
            echo ""
            echo "Available check IDs: gateway node disk discord slack google memory"
            echo "                     image-gen whisper skills cli-versions cron github"
            echo "                     keyring context slack"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# ── Find Config ───────────────────────────────────────────────────────────────

if [ -z "$CONF_PATH" ]; then
    if [ -f "$SCRIPT_DIR/checklist.conf" ]; then
        CONF_PATH="$SCRIPT_DIR/checklist.conf"
    elif [ -f "$HOME/.openclaw/checklist.conf" ]; then
        CONF_PATH="$HOME/.openclaw/checklist.conf"
    fi
fi

# ── Load Config ───────────────────────────────────────────────────────────────

declare -A CHECKLIST_CONF

if [ -n "$CONF_PATH" ] && [ -f "$CONF_PATH" ]; then
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// /}" ]] && continue
        key="${key// /}"
        value="${value//[[:space:]]/}"
        CHECKLIST_CONF["$key"]="$value"
    done < "$CONF_PATH"
    # Apply config overrides that affect lib.sh globals
    NPM_CMD="${CHECKLIST_CONF[NPM_CMD]:-npm}"
elif [ -z "$SINGLE_CHECK" ]; then
    if [ "$CHECKLIST_JSON" != "true" ]; then
        echo ""
        echo "  No checklist.conf found. Run with --check <id> to test a single check."
        echo "  Config search paths:"
        echo "    $SCRIPT_DIR/checklist.conf"
        echo "    $HOME/.openclaw/checklist.conf"
        echo ""
        echo "  Copy checklist.conf.example to checklist.conf to get started."
    fi
fi

# ── Banner ────────────────────────────────────────────────────────────────────

if [ "$CHECKLIST_JSON" != "true" ]; then
    echo ""
    echo "═══ OpenClaw Health Check ═══"
    echo "$(date -u '+%Y-%m-%d %H:%M') UTC"
fi

# ── Run Checks ────────────────────────────────────────────────────────────────

CHECKS_DIR="$SCRIPT_DIR/checks"

if [ ! -d "$CHECKS_DIR" ]; then
    echo "Error: checks directory not found: $CHECKS_DIR" >&2
    exit 1
fi

if [ -n "$SINGLE_CHECK" ]; then
    # Run a single check by ID (hyphen and underscore both accepted)
    check_id_normalized="${SINGLE_CHECK//-/_}"

    # Try both forms when searching
    check_file=""
    for candidate in "$CHECKS_DIR"/*-"${SINGLE_CHECK}".sh "$CHECKS_DIR"/*-"${check_id_normalized}".sh; do
        if [ -f "$candidate" ]; then
            check_file="$candidate"
            break
        fi
    done

    if [ -z "$check_file" ]; then
        echo "Error: No check found for '$SINGLE_CHECK'" >&2
        echo "" >&2
        echo "Available checks:" >&2
        for f in "$CHECKS_DIR"/[0-9][0-9]-*.sh; do
            [ -f "$f" ] || continue
            fname=$(basename "$f" .sh)
            echo "  ${fname#*-}" >&2
        done
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$check_file"
    check_func="check_${check_id_normalized}"
    if declare -f "$check_func" > /dev/null 2>&1; then
        "$check_func"
    else
        echo "Error: Function '$check_func' not found in $check_file" >&2
        exit 1
    fi

else
    # Run all enabled checks in order
    for check_file in "$CHECKS_DIR"/[0-9][0-9]-*.sh; do
        [ -f "$check_file" ] || continue

        fname=$(basename "$check_file" .sh)
        check_id="${fname#*-}"
        check_func="check_${check_id//-/_}"

        # Build config key: hyphen → underscore, then uppercase
        config_key="CHECK_$(echo "${check_id}" | tr '[:lower:]-' '[:upper:]_')"

        if [ "${CHECKLIST_CONF[$config_key]:-false}" != "true" ]; then
            continue
        fi

        # shellcheck source=/dev/null
        source "$check_file"
        if declare -f "$check_func" > /dev/null 2>&1; then
            "$check_func"
        else
            echo "  Warning: $check_file does not define $check_func" >&2
        fi
    done
fi

# ── Summary ───────────────────────────────────────────────────────────────────

if [ "$CHECKLIST_JSON" != "true" ]; then
    echo ""
    echo "═══════════════════════════════"
    echo "SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed, $WARN_COUNT warning, $SKIP_COUNT skipped"
    echo "═══════════════════════════════"
fi

if $JSON_OUTPUT; then
    echo "$JSON_RESULTS"
fi

# ── Exit Code ─────────────────────────────────────────────────────────────────

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    exit 2
fi
exit 0
