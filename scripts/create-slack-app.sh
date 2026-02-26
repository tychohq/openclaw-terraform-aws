#!/usr/bin/env bash
# create-slack-app.sh — Automate Slack app creation via agent-browser
#
# Prerequisites:
#   1. Chrome open with remote debugging: ~/.agents/browser/launch-chrome.sh
#   2. Logged into slack.com/api in that Chrome session
#   3. agent-browser installed
#
# Usage:
#   ./scripts/create-slack-app.sh [--workspace WORKSPACE_NAME] [--app-name APP_NAME] [--manifest PATH]
#
# Output:
#   Prints SLACK_APP_TOKEN and SLACK_BOT_TOKEN to stdout (and optionally writes to .env)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CDP_PORT=9222
MANIFEST="${REPO_DIR}/templates/slack-app-manifest.json"
APP_NAME=""
WORKSPACE=""
WRITE_ENV=false
ENV_FILE="${REPO_DIR}/.env"

# Source .env for defaults (ASSISTANT_NAME, etc.)
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi
# Default app name from ASSISTANT_NAME env var
APP_NAME="${ASSISTANT_NAME:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --workspace NAME    Slack workspace name to select (partial match OK)"
    echo "  --app-name NAME     Override app display name (default: from manifest)"
    echo "  --manifest PATH     Path to manifest JSON (default: templates/slack-app-manifest.json)"
    echo "  --write-env         Append tokens to .env file"
    echo "  --env-file PATH     Path to .env file (default: .env in repo root)"
    echo "  --cdp PORT          Chrome DevTools Protocol port (default: 9222)"
    echo "  -h, --help          Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --workspace)  WORKSPACE="$2"; shift 2 ;;
        --app-name)   APP_NAME="$2"; shift 2 ;;
        --manifest)   MANIFEST="$2"; shift 2 ;;
        --write-env)  WRITE_ENV=true; shift ;;
        --env-file)   ENV_FILE="$2"; shift 2 ;;
        --cdp)        CDP_PORT="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *)            echo -e "${RED}Unknown option: $1${NC}"; usage ;;
    esac
done

# Validate
if [ ! -f "$MANIFEST" ]; then
    echo -e "${RED}Error: Manifest not found at: $MANIFEST${NC}"
    exit 1
fi

if ! command -v agent-browser &>/dev/null; then
    echo -e "${RED}Error: agent-browser not found. Install with: bun install -g agent-browser${NC}"
    exit 1
fi

ab() {
    agent-browser --cdp "$CDP_PORT" "$@"
}

# Helper: snapshot interactive elements, return output
snap() {
    ab snapshot -i -c 2>/dev/null
}

# Helper: wait for navigation/load
wait_load() {
    ab wait --load networkidle 2>/dev/null || true
    sleep 1
}

# Helper: find ref by text in snapshot
find_ref() {
    local text="$1"
    snap | grep -i "$text" | head -1 | grep -oP '@e\d+' | head -1
}

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Slack App Creator (agent-browser)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# ─── Step 0: Connect to Chrome ───────────────────────────────────────────────
echo -e "${BLUE}[0/6] Connecting to Chrome on CDP port $CDP_PORT...${NC}"
if ! ab get url &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to Chrome on port $CDP_PORT${NC}"
    echo "Start Chrome with: ~/.agents/browser/launch-chrome.sh"
    exit 1
fi
echo -e "${GREEN}  ✓ Connected${NC}"

# ─── Step 1: Navigate to app creation ────────────────────────────────────────
echo -e "${BLUE}[1/6] Navigating to Slack app creation...${NC}"
ab open "https://api.slack.com/apps" 2>/dev/null
wait_load

# Check if logged in by looking for "Create New App" or "Your Apps"
SNAP=$(snap)
if echo "$SNAP" | grep -qi "sign in\|log in\|email.*password"; then
    echo -e "${RED}Error: Not logged into Slack.${NC}"
    echo "Please log in at https://api.slack.com in the Chrome window, then re-run."
    exit 1
fi
echo -e "${GREEN}  ✓ Logged in, on Your Apps page${NC}"

# Click "Create New App"
echo -e "${BLUE}[2/6] Creating app from manifest...${NC}"

# Click "Create New App" button
CREATE_REF=$(echo "$SNAP" | grep -i "create.*new.*app\|create.*app" | grep -oP '@e\d+' | head -1)
if [ -z "$CREATE_REF" ]; then
    # Try finding by button role
    CREATE_REF=$(echo "$SNAP" | grep -i "create" | grep -oP '@e\d+' | head -1)
fi

if [ -z "$CREATE_REF" ]; then
    echo -e "${RED}Error: Could not find 'Create New App' button${NC}"
    echo "Snapshot:"
    echo "$SNAP"
    exit 1
fi

ab click "$CREATE_REF" 2>/dev/null
sleep 2

# Should see modal: "From scratch" vs "From an app manifest"
SNAP=$(snap)
MANIFEST_REF=$(echo "$SNAP" | grep -i "manifest" | grep -oP '@e\d+' | head -1)
if [ -z "$MANIFEST_REF" ]; then
    echo -e "${YELLOW}  Looking for manifest option...${NC}"
    sleep 2
    SNAP=$(snap)
    MANIFEST_REF=$(echo "$SNAP" | grep -i "manifest" | grep -oP '@e\d+' | head -1)
fi

if [ -z "$MANIFEST_REF" ]; then
    echo -e "${RED}Error: Could not find 'From an app manifest' option${NC}"
    echo "Snapshot:"
    echo "$SNAP"
    exit 1
fi

ab click "$MANIFEST_REF" 2>/dev/null
sleep 2

# ─── Step 2: Select workspace ────────────────────────────────────────────────
SNAP=$(snap)

if [ -n "$WORKSPACE" ]; then
    echo -e "${BLUE}  Selecting workspace: $WORKSPACE${NC}"
    WS_REF=$(echo "$SNAP" | grep -i "$WORKSPACE" | grep -oP '@e\d+' | head -1)
    if [ -n "$WS_REF" ]; then
        ab click "$WS_REF" 2>/dev/null
        sleep 1
    fi
fi

# Click Next
NEXT_REF=$(echo "$SNAP" | grep -i "next" | grep -oP '@e\d+' | head -1)
if [ -z "$NEXT_REF" ]; then
    sleep 1
    SNAP=$(snap)
    NEXT_REF=$(echo "$SNAP" | grep -i "next" | grep -oP '@e\d+' | head -1)
fi
if [ -n "$NEXT_REF" ]; then
    ab click "$NEXT_REF" 2>/dev/null
    sleep 2
fi

# ─── Step 3: Paste manifest ──────────────────────────────────────────────────
echo -e "${BLUE}[3/6] Pasting manifest JSON...${NC}"

SNAP=$(snap)

# Check if we need to switch to JSON tab (there might be YAML/JSON tabs)
JSON_TAB=$(echo "$SNAP" | grep -i '"json"' | grep -oP '@e\d+' | head -1)
if [ -n "$JSON_TAB" ]; then
    ab click "$JSON_TAB" 2>/dev/null
    sleep 1
fi

# The manifest editor is usually a textarea or code editor
# Try to select all text in the editor and replace with our manifest
MANIFEST_CONTENT=$(cat "$MANIFEST")

# Override app name if specified
if [ -n "$APP_NAME" ]; then
    MANIFEST_CONTENT=$(echo "$MANIFEST_CONTENT" | jq --arg name "$APP_NAME" '.display_information.name = $name | .features.bot_user.display_name = $name')
fi

# Find the editor/textarea — usually the largest text input on the page
EDITOR_REF=$(echo "$SNAP" | grep -iP 'textbox|textarea|editor|code' | grep -oP '@e\d+' | head -1)
if [ -n "$EDITOR_REF" ]; then
    ab click "$EDITOR_REF" 2>/dev/null
    sleep 0.5
    ab press "Control+a" 2>/dev/null
    sleep 0.5
    # Use eval to set the value directly — more reliable than typing JSON
    ab eval "
        const editor = document.querySelector('textarea, [role=\"textbox\"], .CodeMirror, .monaco-editor');
        if (editor) {
            if (editor.CodeMirror) {
                editor.CodeMirror.setValue(JSON.stringify(${MANIFEST_CONTENT}, null, 2));
            } else if (editor.tagName === 'TEXTAREA') {
                const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
                nativeInputValueSetter.call(editor, JSON.stringify(${MANIFEST_CONTENT}, null, 2));
                editor.dispatchEvent(new Event('input', { bubbles: true }));
                editor.dispatchEvent(new Event('change', { bubbles: true }));
            } else {
                editor.textContent = JSON.stringify(${MANIFEST_CONTENT}, null, 2);
                editor.dispatchEvent(new Event('input', { bubbles: true }));
            }
            'Manifest pasted';
        } else {
            'No editor found';
        }
    " 2>/dev/null
else
    echo -e "${YELLOW}  No editor ref found, trying JS injection...${NC}"
    ab eval "
        const ta = document.querySelector('textarea');
        if (ta) {
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
            nativeInputValueSetter.call(ta, $(echo "$MANIFEST_CONTENT" | jq -Rs .));
            ta.dispatchEvent(new Event('input', { bubbles: true }));
            ta.dispatchEvent(new Event('change', { bubbles: true }));
            'OK';
        } else { 'No textarea'; }
    " 2>/dev/null
fi

sleep 1

# Click Next
SNAP=$(snap)
NEXT_REF=$(echo "$SNAP" | grep -i "next" | grep -oP '@e\d+' | head -1)
if [ -n "$NEXT_REF" ]; then
    ab click "$NEXT_REF" 2>/dev/null
    sleep 2
fi

# ─── Step 4: Review and Create ───────────────────────────────────────────────
echo -e "${BLUE}[4/6] Confirming app creation...${NC}"

SNAP=$(snap)
CREATE_REF=$(echo "$SNAP" | grep -i "create" | grep -oP '@e\d+' | tail -1)
if [ -n "$CREATE_REF" ]; then
    ab click "$CREATE_REF" 2>/dev/null
    sleep 3
    wait_load
fi

echo -e "${GREEN}  ✓ App created${NC}"

# ─── Step 5: Get App ID from URL ─────────────────────────────────────────────
CURRENT_URL=$(ab get url 2>/dev/null)
APP_ID=$(echo "$CURRENT_URL" | grep -oP 'apps/\K[A-Z0-9]+' || true)

if [ -z "$APP_ID" ]; then
    echo -e "${YELLOW}  Could not extract App ID from URL: $CURRENT_URL${NC}"
    echo -e "${YELLOW}  Trying to find it from page content...${NC}"
    SNAP=$(snap)
    APP_ID=$(echo "$SNAP" | grep -oP 'A[A-Z0-9]{8,12}' | head -1 || true)
fi

if [ -n "$APP_ID" ]; then
    echo -e "${GREEN}  ✓ App ID: $APP_ID${NC}"
else
    echo -e "${RED}  ✗ Could not determine App ID — you may need to find it manually${NC}"
fi

# ─── Step 6: Generate App-Level Token (Socket Mode) ──────────────────────────
echo -e "${BLUE}[5/6] Generating App-Level Token for Socket Mode...${NC}"

# Navigate to Basic Information page (where app-level tokens live)
if [ -n "$APP_ID" ]; then
    ab open "https://api.slack.com/apps/${APP_ID}/general" 2>/dev/null
    wait_load
fi

# Scroll down to "App-Level Tokens" section and click "Generate Token and Scopes"
sleep 2
SNAP=$(snap)
GEN_TOKEN_REF=$(echo "$SNAP" | grep -i "generate.*token" | grep -oP '@e\d+' | head -1)

if [ -z "$GEN_TOKEN_REF" ]; then
    # Try scrolling down
    ab scroll down 1000 2>/dev/null
    sleep 1
    SNAP=$(snap)
    GEN_TOKEN_REF=$(echo "$SNAP" | grep -i "generate.*token" | grep -oP '@e\d+' | head -1)
fi

SLACK_APP_TOKEN=""
if [ -n "$GEN_TOKEN_REF" ]; then
    ab click "$GEN_TOKEN_REF" 2>/dev/null
    sleep 2
    SNAP=$(snap)

    # Fill token name
    NAME_REF=$(echo "$SNAP" | grep -iP 'textbox|text.*name|token.*name' | grep -oP '@e\d+' | head -1)
    if [ -n "$NAME_REF" ]; then
        ab fill "$NAME_REF" "openclaw-socket" 2>/dev/null
        sleep 0.5
    fi

    # Add scope: connections:write
    ADD_SCOPE_REF=$(echo "$SNAP" | grep -i "add.*scope" | grep -oP '@e\d+' | head -1)
    if [ -n "$ADD_SCOPE_REF" ]; then
        ab click "$ADD_SCOPE_REF" 2>/dev/null
        sleep 1
        SNAP=$(snap)
        CONN_REF=$(echo "$SNAP" | grep -i "connections:write" | grep -oP '@e\d+' | head -1)
        if [ -n "$CONN_REF" ]; then
            ab click "$CONN_REF" 2>/dev/null
            sleep 0.5
        fi
    fi

    # Click Generate
    SNAP=$(snap)
    GEN_REF=$(echo "$SNAP" | grep -iP 'button.*generate\b|"generate"' | grep -oP '@e\d+' | head -1)
    if [ -z "$GEN_REF" ]; then
        GEN_REF=$(echo "$SNAP" | grep -i "generate" | grep -oP '@e\d+' | tail -1)
    fi
    if [ -n "$GEN_REF" ]; then
        ab click "$GEN_REF" 2>/dev/null
        sleep 3
    fi

    # Extract the xapp- token
    SNAP=$(snap)
    SLACK_APP_TOKEN=$(echo "$SNAP" | grep -oP 'xapp-[A-Za-z0-9-]+' | head -1)

    if [ -z "$SLACK_APP_TOKEN" ]; then
        # Try getting it from a text element
        TOKEN_REF=$(echo "$SNAP" | grep -i "xapp\|token.*value\|copy" | grep -oP '@e\d+' | head -1)
        if [ -n "$TOKEN_REF" ]; then
            SLACK_APP_TOKEN=$(ab get text "$TOKEN_REF" 2>/dev/null | grep -oP 'xapp-[A-Za-z0-9-]+' || true)
        fi
    fi

    # Close the modal/dialog
    DONE_REF=$(echo "$SNAP" | grep -i "done\|close\|dismiss" | grep -oP '@e\d+' | head -1)
    if [ -n "$DONE_REF" ]; then
        ab click "$DONE_REF" 2>/dev/null
        sleep 1
    fi
fi

if [ -n "$SLACK_APP_TOKEN" ]; then
    echo -e "${GREEN}  ✓ App Token: ${SLACK_APP_TOKEN:0:15}...${NC}"
else
    echo -e "${YELLOW}  ⚠ Could not auto-extract App Token.${NC}"
    echo -e "${YELLOW}    Go to: https://api.slack.com/apps/${APP_ID}/general${NC}"
    echo -e "${YELLOW}    Scroll to 'App-Level Tokens' → Generate with connections:write scope${NC}"
fi

# ─── Step 7: Install to Workspace & Get Bot Token ────────────────────────────
echo -e "${BLUE}[6/6] Installing to workspace & getting Bot Token...${NC}"

SLACK_BOT_TOKEN=""
NEEDS_ADMIN_APPROVAL=false

if [ -n "$APP_ID" ]; then
    ab open "https://api.slack.com/apps/${APP_ID}/oauth" 2>/dev/null
    wait_load
fi

sleep 2
SNAP=$(snap)

# Check if already installed (has a bot token showing)
EXISTING_TOKEN=$(echo "$SNAP" | grep -oP 'xoxb-[A-Za-z0-9-]+' | head -1)

if [ -n "$EXISTING_TOKEN" ]; then
    SLACK_BOT_TOKEN="$EXISTING_TOKEN"
    echo -e "${GREEN}  ✓ Already installed, found token${NC}"
else
    # Detect: "Install to Workspace" vs "Request to Install"
    # "Request to Install" means workspace admin approval is required
    REQUEST_REF=$(echo "$SNAP" | grep -i "request.*install" | grep -oP '@e\d+' | head -1)
    INSTALL_REF=$(echo "$SNAP" | grep -i "install.*workspace\|install.*app\|install to" | grep -v -i "request\|reinstall" | grep -oP '@e\d+' | head -1)

    if [ -n "$REQUEST_REF" ] && [ -z "$INSTALL_REF" ]; then
        # ── Admin Approval Flow ──────────────────────────────────────────
        NEEDS_ADMIN_APPROVAL=true
        echo -e "${YELLOW}  ⚠ This workspace requires admin approval to install apps.${NC}"
        echo -e "${YELLOW}    Submitting install request...${NC}"

        ab click "$REQUEST_REF" 2>/dev/null
        sleep 3

        # There may be a confirmation dialog
        SNAP=$(snap)
        SUBMIT_REF=$(echo "$SNAP" | grep -iP 'submit|send.*request|request' | grep -oP '@e\d+' | tail -1)
        if [ -n "$SUBMIT_REF" ]; then
            ab click "$SUBMIT_REF" 2>/dev/null
            sleep 2
        fi

        echo -e "${YELLOW}  ✓ Install request submitted.${NC}"
        echo -e "${YELLOW}    A workspace admin must approve this before the bot token is available.${NC}"
        echo ""
        echo -e "${YELLOW}  After approval, re-run this script or get the token manually:${NC}"
        echo -e "${YELLOW}    https://api.slack.com/apps/${APP_ID}/oauth${NC}"

    elif [ -n "$INSTALL_REF" ]; then
        # ── Direct Install Flow ──────────────────────────────────────────
        ab click "$INSTALL_REF" 2>/dev/null
        sleep 3
        wait_load

        # OAuth consent page — click "Allow"
        SNAP=$(snap)
        ALLOW_REF=$(echo "$SNAP" | grep -i "allow" | grep -oP '@e\d+' | head -1)
        if [ -n "$ALLOW_REF" ]; then
            ab click "$ALLOW_REF" 2>/dev/null
            sleep 3
            wait_load
        fi

        # Should redirect back to OAuth page with the token
        SNAP=$(snap)
        SLACK_BOT_TOKEN=$(echo "$SNAP" | grep -oP 'xoxb-[A-Za-z0-9-]+' | head -1)

        # Token might be behind a Copy button — try clicking it
        if [ -z "$SLACK_BOT_TOKEN" ]; then
            COPY_REF=$(echo "$SNAP" | grep -i "copy" | grep -oP '@e\d+' | head -1)
            if [ -n "$COPY_REF" ]; then
                # Try extracting from nearby text instead of clipboard
                TOKEN_TEXT_REF=$(echo "$SNAP" | grep -i "bot.*token\|oauth.*token\|xoxb" | grep -oP '@e\d+' | head -1)
                if [ -n "$TOKEN_TEXT_REF" ]; then
                    SLACK_BOT_TOKEN=$(ab get text "$TOKEN_TEXT_REF" 2>/dev/null | grep -oP 'xoxb-[A-Za-z0-9-]+' || true)
                fi
            fi
        fi

        # Last resort: re-navigate to OAuth page
        if [ -z "$SLACK_BOT_TOKEN" ] && [ -n "$APP_ID" ]; then
            ab open "https://api.slack.com/apps/${APP_ID}/oauth" 2>/dev/null
            wait_load
            sleep 2
            SNAP=$(snap)
            SLACK_BOT_TOKEN=$(echo "$SNAP" | grep -oP 'xoxb-[A-Za-z0-9-]+' | head -1)

            # Try extracting via JS as final attempt
            if [ -z "$SLACK_BOT_TOKEN" ]; then
                SLACK_BOT_TOKEN=$(ab eval "
                    const els = [...document.querySelectorAll('*')];
                    const tokenEl = els.find(el => el.textContent.match(/^xoxb-/) && el.children.length === 0);
                    tokenEl ? tokenEl.textContent.trim() : '';
                " 2>/dev/null | grep -oP 'xoxb-[A-Za-z0-9-]+' || true)
            fi
        fi
    else
        echo -e "${YELLOW}  ⚠ Could not find Install or Request button.${NC}"
        echo -e "${YELLOW}    Page may have changed. Check: https://api.slack.com/apps/${APP_ID}/oauth${NC}"
    fi
fi

if [ -n "$SLACK_BOT_TOKEN" ]; then
    echo -e "${GREEN}  ✓ Bot Token: ${SLACK_BOT_TOKEN:0:15}...${NC}"
elif [ "$NEEDS_ADMIN_APPROVAL" = false ]; then
    echo -e "${YELLOW}  ⚠ Could not auto-extract Bot Token.${NC}"
    echo -e "${YELLOW}    Go to: https://api.slack.com/apps/${APP_ID}/oauth${NC}"
    echo -e "${YELLOW}    Copy the 'Bot User OAuth Token' (xoxb-...)${NC}"
fi

# ─── Output ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Results${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

[ -n "$APP_ID" ]          && echo "SLACK_APP_ID=$APP_ID"
[ -n "$SLACK_APP_TOKEN" ] && echo "SLACK_APP_TOKEN=$SLACK_APP_TOKEN"
[ -n "$SLACK_BOT_TOKEN" ] && echo "SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN"

if [ "$WRITE_ENV" = true ]; then
    echo ""
    if [ -n "$SLACK_APP_TOKEN" ] && [ -n "$SLACK_BOT_TOKEN" ]; then
        # Update or append to .env
        touch "$ENV_FILE"
        for VAR_NAME in SLACK_APP_TOKEN SLACK_BOT_TOKEN; do
            VAR_VAL="${!VAR_NAME}"
            if grep -q "^${VAR_NAME}=" "$ENV_FILE" 2>/dev/null; then
                # macOS-safe sed
                sed -i '' "s|^${VAR_NAME}=.*|${VAR_NAME}=\"${VAR_VAL}\"|" "$ENV_FILE"
            else
                echo "${VAR_NAME}=\"${VAR_VAL}\"" >> "$ENV_FILE"
            fi
        done
        echo -e "${GREEN}  ✓ Tokens written to $ENV_FILE${NC}"
    else
        echo -e "${YELLOW}  ⚠ Skipping .env write — missing one or both tokens${NC}"
    fi
fi

echo ""
if [ "$NEEDS_ADMIN_APPROVAL" = true ]; then
    echo -e "${YELLOW}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  ⏳ Waiting for workspace admin approval        │${NC}"
    echo -e "${YELLOW}├─────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│  The app was created and an install request     │${NC}"
    echo -e "${YELLOW}│  was submitted. A workspace admin must approve  │${NC}"
    echo -e "${YELLOW}│  it before the bot token becomes available.     │${NC}"
    echo -e "${YELLOW}│                                                 │${NC}"
    echo -e "${YELLOW}│  After approval, either:                        │${NC}"
    echo -e "${YELLOW}│   • Re-run this script (it will pick up tokens) │${NC}"
    echo -e "${YELLOW}│   • Get tokens manually from the app settings   │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────┘${NC}"
    echo ""
    [ -n "$APP_ID" ]          && echo "SLACK_APP_ID=$APP_ID"
    [ -n "$SLACK_APP_TOKEN" ] && echo "SLACK_APP_TOKEN=$SLACK_APP_TOKEN"
    echo "SLACK_BOT_TOKEN=  # pending admin approval"
    echo ""
    echo "App settings: https://api.slack.com/apps/${APP_ID}"
    exit 2  # Exit code 2 = partial success (pending approval)

elif [ -z "$SLACK_APP_TOKEN" ] || [ -z "$SLACK_BOT_TOKEN" ]; then
    echo -e "${YELLOW}Some tokens could not be auto-extracted.${NC}"
    echo -e "${YELLOW}Complete the remaining steps manually at:${NC}"
    echo -e "${YELLOW}  https://api.slack.com/apps/${APP_ID}${NC}"
    echo ""
    echo "Then add to your .env:"
    echo '  SLACK_APP_TOKEN="xapp-..."'
    echo '  SLACK_BOT_TOKEN="xoxb-..."'
    exit 1

else
    echo -e "${GREEN}All done! Add these to your .env (or use --write-env next time).${NC}"
fi
