# OpenClaw Deployment Health Check

A modular health check system for OpenClaw AWS deployments. Verifies that every component — gateway, channels, integrations, AI features, CLI tools — is working correctly. Designed to run post-deploy, on-demand, or on a daily cron.

## Quick Start

```bash
# First time: copy and configure
cp checklist.conf.example checklist.conf
vi checklist.conf  # enable the checks you want

# Run all enabled checks
./checklist.sh

# Run with JSON output (for automation / cron reporting)
./checklist.sh --json

# Run a single check by ID
./checklist.sh --check gateway
./checklist.sh --check disk
./checklist.sh --check github
```

On the EC2 instance, the checklist lives at:
```
~/.openclaw/workspace/scripts/checklist/
```

## Configuration

Copy `checklist.conf.example` to `checklist.conf` in the same directory (or at `~/.openclaw/checklist.conf`) and set `true`/`false` for each check:

```bash
CHECK_GATEWAY=true
CHECK_NODE=true
CHECK_DISK=true
CHECK_DISCORD=false
CHECK_GITHUB=true
```

All checks default to `false` — enable only what your deployment uses.

### Google account setting

For the Google check, set `GOOGLE_ACCOUNT` to run per-service tests (Gmail, Calendar, Drive):

```bash
CHECK_GOOGLE=true
GOOGLE_ACCOUNT=you@gmail.com
```

If `GOOGLE_ACCOUNT` is empty, the check only verifies `gog` is installed and authenticated.

## Available Checks

| ID | Script | What It Checks |
|---|---|---|
| `gateway` | `01-gateway.sh` | Gateway systemd service, HTTP health endpoint, openclaw version |
| `node` | `02-node.sh` | Node.js >= 20, npm, bun (optional) |
| `disk` | `03-disk.sh` | Root volume free space, RAM usage, log sizes |
| `discord` | `04-discord.sh` | Discord config, bot token, recent connection in logs |
| `google` | `05-google.sh` | gog CLI install, auth, Gmail, Calendar, Drive |
| `memory` | `06-memory.sh` | Workspace dirs, MEMORY.md, git repo, embedding index |
| `image-gen` | `07-image-gen.sh` | nano-banana-pro skill, Gemini API key |
| `whisper` | `08-whisper.sh` | Whisper skill, OPENAI_API_KEY |
| `skills` | `09-skills.sh` | Skill inventory across all directories, missing SKILL.md |
| `cli-versions` | `10-cli-versions.sh` | openclaw, clawhub, agent-browser, mcporter vs npm latest |
| `cron` | `11-cron.sh` | Cron job files in workspace, gateway prerequisite |
| `github` | `12-github.sh` | gh CLI installed, gh auth status |

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | One or more checks **failed** |
| `2` | No failures, but **warnings** present |

## Adding a New Check

1. Create `checks/NN-mycheck.sh` (pick the next number):

```bash
#!/bin/bash
# Check: My new service

check_mycheck() {
    section "MY SERVICE"

    if has_cmd mytool; then
        local ver
        ver=$(mytool --version 2>/dev/null || echo "unknown")
        report_result "mycheck.tool" "pass" "mytool installed (v$ver)"
    else
        report_result "mycheck.tool" "fail" "mytool not found" \
            "npm install -g mytool"
    fi
}
```

2. Add the config key to `checklist.conf.example`:

```bash
# ── My Section ──
CHECK_MYCHECK=false
```

3. Enable in your `checklist.conf`:

```bash
CHECK_MYCHECK=true
```

The runner discovers check files automatically — no other changes needed.

## Running on a Cron

Register a daily health check with OpenClaw by placing this file in `~/.openclaw/workspace/cron-jobs/daily-health-check.json`:

```json
{
  "name": "daily-health-check",
  "schedule": "0 9 * * *",
  "command": "bash ~/.openclaw/workspace/scripts/checklist/checklist.sh --json",
  "description": "Daily deployment health check"
}
```

Then ask OpenClaw to register the cron job:
> "Please register the cron job at ~/.openclaw/workspace/cron-jobs/daily-health-check.json"

## Architecture

- `checklist.sh` — Runner: reads config, sources each enabled check, prints summary
- `lib.sh` — Shared helpers: colors, `report_result`, `section`, `has_cmd`, counters
- `checks/*.sh` — Individual checks: each defines a single `check_<id>()` function
- `checklist.conf` — Your local config (gitignored by `.openclaw`)
- `checklist.conf.example` — Template committed to the repo

Each check is fully independent — it only needs `lib.sh` sourced beforehand. The runner sources `lib.sh` once at startup, then sources and calls each check function in order, sharing the same counter state.
