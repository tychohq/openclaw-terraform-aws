# PRD: Deployment Health Check System

## Overview

A modular, configurable health check system for OpenClaw AWS deployments. Runs on the EC2 instance to verify everything is working. Designed to run post-deploy, on-demand, or on a daily cron.

## File Structure

All checklist files live in the repo under `checklist/`:

```
checklist/
├── checklist.sh              # Main runner script
├── checklist.conf.example    # Example config (which checks are enabled)
├── lib.sh                    # Shared helpers (colors, reporting, result tracking)
├── checks/                   # Individual check scripts (modular)
│   ├── 01-gateway.sh         # Gateway service + health
│   ├── 02-node.sh            # Node.js version check
│   ├── 03-disk.sh            # Disk space + memory
│   ├── 04-discord.sh         # Discord channel connectivity
│   ├── 05-google.sh          # Google auth (gog CLI)
│   ├── 06-memory.sh          # Workspace + embeddings
│   ├── 07-image-gen.sh       # Nano Banana Pro
│   ├── 08-whisper.sh         # Voice transcription
│   ├── 09-skills.sh          # Skill inventory + validation
│   ├── 10-cli-versions.sh    # CLI version audit
│   ├── 11-cron.sh            # Cron scheduler
│   └── 12-github.sh          # GitHub CLI auth
└── README.md                 # Documentation
```

## Task Checklist

### Task 1: Create `checklist/lib.sh` — shared helpers

Shared functions used by all check scripts. Source this at the top of every check.

```bash
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

# Report a check result
# Usage: report_result "check_id" "status" "message" ["remediation"]
# status: pass | fail | warn | skip
report_result() {
    local id="$1" status="$2" msg="$3" remedy="${4:-}"
    
    case "$status" in
        pass) echo -e "  ${GREEN}✅${NC} $msg"; ((PASS_COUNT++)) ;;
        fail) echo -e "  ${RED}❌${NC} $msg"; ((FAIL_COUNT++))
              [ -n "$remedy" ] && echo -e "     ${DIM}→ $remedy${NC}" ;;
        warn) echo -e "  ${YELLOW}⚠️${NC}  $msg"; ((WARN_COUNT++))
              [ -n "$remedy" ] && echo -e "     ${DIM}→ $remedy${NC}" ;;
        skip) echo -e "  ${DIM}⏭️  $msg (skipped)${NC}"; ((SKIP_COUNT++)) ;;
    esac

    # Append to JSON
    local json_entry
    json_entry=$(jq -n \
        --arg id "$id" \
        --arg status "$status" \
        --arg message "$msg" \
        --arg remedy "$remedy" \
        '{id: $id, status: $status, message: $message, remedy: $remedy}')
    JSON_RESULTS=$(echo "$JSON_RESULTS" | jq --argjson entry "$json_entry" '. + [$entry]')
}

# Print section header
# Usage: section "CORE INFRASTRUCTURE"
section() {
    echo ""
    echo -e "  ${CYAN}$1${NC}"
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
```

**Validation:** `bash -n checklist/lib.sh` passes. Sourcing it doesn't produce output.

### Task 2: Create `checklist/checklist.sh` — main runner

The main entry point. Reads config, runs enabled checks, prints summary.

**Requirements:**
- Parse `checklist.conf` into an associative array
- Accept `--json` flag for machine-readable output
- Accept `--config <path>` to override default config location
- Accept `--check <id>` to run a single check (e.g. `--check gateway`)
- Source `lib.sh` then source each enabled check script in order
- Print a banner with timestamp at the top
- Print summary at the bottom (X passed, Y failed, Z warnings, W skipped)
- Exit code: 0 if all pass, 1 if any fail, 2 if warnings only
- If `--json` flag, output the JSON_RESULTS array at the end instead of pretty output
- Config location default: look for `checklist.conf` in same dir as `checklist.sh`, then `~/.openclaw/checklist.conf`

**Banner format (plain text, no box-drawing — must work in Discord):**
```
═══ OpenClaw Health Check ═══
2026-02-25 14:30 UTC
```

**Summary format:**
```
═══════════════════════════════
SUMMARY: 14 passed, 1 failed, 1 warning, 2 skipped
═══════════════════════════════
```

**Important:** Each check script defines a function (e.g. `check_gateway()`) that the runner calls. The runner sources the file then calls the function. This way checks can share lib.sh context.

### Task 3: Create `checklist/checklist.conf.example`

Example config with comments. All checks default to false (user enables what they want):

```bash
# OpenClaw Deployment Health Check Configuration
# Copy to checklist.conf and enable the checks you want.
# true = run this check, false = skip it

# ── Core (recommended: always on) ──
CHECK_GATEWAY=true
CHECK_NODE=true
CHECK_DISK=true

# ── Channels (enable what you use) ──
CHECK_DISCORD=false
# CHECK_SLACK=false       # not yet implemented
# CHECK_TELEGRAM=false    # not yet implemented

# ── Integrations ──
CHECK_GOOGLE=false
CHECK_GITHUB=false
# CHECK_1PASSWORD=false   # not yet implemented

# ── AI Features ──
CHECK_IMAGE_GEN=false
CHECK_WHISPER=false

# ── Memory & Workspace ──
CHECK_MEMORY=true

# ── Skills ──
CHECK_SKILLS=true

# ── CLI Versions ──
CHECK_CLI_VERSIONS=true

# ── Cron ──
CHECK_CRON=false
```

### Task 4: Create check scripts

Each check script follows this pattern:
1. A function named `check_<id>()` 
2. Uses `report_result` from lib.sh for each sub-check
3. Provides remediation strings for failures

#### `checks/01-gateway.sh`
- `check_gateway()`
- Sub-checks:
  - Is `openclaw-gateway` systemd service active? (`systemctl --user is-active openclaw-gateway`)
  - Is gateway responding on HTTP? (`curl -sf http://localhost:3033/health` — try common ports 3033, 3000, 4433)
  - Get openclaw version from `openclaw --version`
- Remediation: `systemctl --user start openclaw-gateway` / `openclaw gateway start`

#### `checks/02-node.sh`
- `check_node()`
- Sub-checks:
  - Node.js installed and version >= 20
  - npm/bun available
- Remediation: install instructions

#### `checks/03-disk.sh`  
- `check_disk()`
- Sub-checks:
  - Root volume >20% free (warn) or >10% free (fail)
  - RAM usage (warn if >90%)
  - Log file size check (`du -sh /var/log/openclaw-install.log` + journal size)
- Remediation: cleanup commands

#### `checks/04-discord.sh`
- `check_discord()`  
- Sub-checks:
  - OpenClaw config has discord section (`jq '.discord' ~/.openclaw/openclaw.json`)
  - Bot token is set (check non-empty, DON'T print it)
  - Gateway logs show discord connection in last hour
- Remediation: config setup instructions

#### `checks/05-google.sh`
- `check_google()`
- Sub-checks:
  - `gog` CLI installed
  - `gog` authenticated (`gog auth status` or equivalent)
  - Can list 1 email (`gog gmail list --limit 1`)
  - Can list calendars (`gog calendar list`)
- Remediation: `npm install -g gog` / `gog auth login`

#### `checks/06-memory.sh`
- `check_memory()`
- Sub-checks:
  - Workspace directory structure exists (`~/.openclaw/workspace/{memory,docs,tools}`)
  - MEMORY.md exists
  - `.openclaw` is a git repo
  - Check for embedding index files (look for `.openclaw/workspace/.embeddings/` or similar vector DB files)
- Remediation: directory creation commands, `git init`

#### `checks/07-image-gen.sh`
- `check_image_gen()`
- Sub-checks:
  - Check if nano-banana-pro skill exists (scan skill directories)
  - Check GEMINI_API_KEY or relevant API key is set in environment or .env
- Remediation: `clawhub install nano-banana-pro` / set API key

#### `checks/08-whisper.sh`
- `check_whisper()`
- Sub-checks:
  - Check if openai-whisper-api skill exists
  - Check OPENAI_API_KEY is set
- Remediation: skill install + API key setup

#### `checks/09-skills.sh`
- `check_skills()`
- Sub-checks:
  - Count skills in each directory:
    - Bundled: `$(npm root -g)/openclaw/skills/` (or find it dynamically)
    - ClawHub managed: `~/.openclaw/skills/`
    - Personal: `~/.agents/skills/` (if exists)
    - Workspace: `~/.openclaw/workspace/skills/`
  - For each skill dir found, check every subdirectory has a SKILL.md
  - Report broken skills (dir exists but no SKILL.md)
  - List all skill names
- Remediation: fix or remove broken skills

#### `checks/10-cli-versions.sh`
- `check_cli_versions()`
- Check each CLI: installed version vs latest npm version
- CLIs to check: `openclaw`, `clawhub`, `agent-browser`, `mcporter`
- Optional (if installed): `gog`, `bird`
- For each: 
  - If not installed: skip (don't fail — they might not need it)
  - If installed and current: pass
  - If installed and outdated: warn with update command
- Use `npm view <pkg> version` for latest (with 5s timeout to not hang if offline)
- Remediation: `npm install -g <pkg>@latest`

#### `checks/11-cron.sh`
- `check_cron()`
- Sub-checks:
  - Gateway is running (prerequisite — skip if gateway check failed)
  - Check if any cron job files exist in `~/.openclaw/workspace/cron-jobs/`
  - If gateway has API, check cron status
- Remediation: instructions to register cron jobs

#### `checks/12-github.sh`
- `check_github()`
- Sub-checks:
  - `gh` CLI installed
  - `gh auth status` passes
- Remediation: `npm install -g gh` / `gh auth login`

### Task 5: Create `checklist/README.md`

Document:
- What this is
- How to run it (`./checklist.sh`, `./checklist.sh --json`, `./checklist.sh --check gateway`)
- How to configure (copy `checklist.conf.example` to `checklist.conf`, enable checks)
- How to add a new check (create file in `checks/`, add config key, follow the pattern)
- How to run on a cron (the OpenClaw cron job JSON)

### Task 6: Terraform integration

Add to `terraform/variables.tf`:
```hcl
variable "checklist_checks" {
  description = "Map of health check names to enabled/disabled. Controls which checks run in the deployment health check."
  type        = map(bool)
  default     = {}
}
```

Update `terraform/cloud-init.sh.tftpl` to:
1. Copy checklist files to `~/.openclaw/workspace/scripts/checklist/`
2. Generate `checklist.conf` from the `checklist_checks` variable
3. Make scripts executable

**Important:** The checklist scripts should be embedded in cloud-init via the existing `workspace_files` pattern OR as a new dedicated section. Since these are multiple files with a directory structure, add a new template section that writes them.

Actually — simpler approach: add the checklist directory to the repo and have cloud-init copy it. But since cloud-init uses templatefile and base64, the cleaner path is:

- Add a new terraform variable `deploy_checklist` (bool, default true)
- When true, cloud-init writes the checklist scripts from base64-encoded heredocs
- Generate `checklist.conf` from `checklist_checks` map

### Task 7: Validate everything

- Run `bash -n` on every .sh file (syntax check)
- Run `shellcheck` on every .sh file if available
- Verify the runner works with all checks disabled (should just print banner + summary)
- Verify the runner works with a single check (`--check gateway`)
- Verify `--json` output is valid JSON
- Verify exit codes (0 for all pass, 1 for any fail)

## Constraints

- Pure bash — no Python, no Node.js dependencies for the checker itself
- Must work on Amazon Linux 2023 (AL2023) with `jq` available
- `jq` is installed by cloud-init (it's in the dnf install line)
- Don't print secrets — redact tokens, API keys
- Each check should timeout after 10 seconds max (use `timeout` command)
- Network checks (npm view for versions) should gracefully handle offline
- The runner must be runnable standalone (no terraform dependency at runtime)
