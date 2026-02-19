# PRD: Pre-Configured OpenClaw AWS Terraform Deployment

## Goal
Extend this existing Terraform project (forked from janobarnard/openclaw-aws) so the instance boots FULLY CONFIGURED — no manual `openclaw onboard` step. The approach should reuse the same config artifacts as our mac-mini-setup repo (JSON config, env file, auth profiles, workspace files, skills).

## Context: Shared Config with mac-mini-setup

We have a companion repo at `~/projects/mac-mini-setup` that already defines:
- **`config/openclaw-config.template.json`** — Full openclaw.json config (channels, models, agents, gateway, skills, plugins, etc.)
- **`config/openclaw-env.template`** — API keys and channel tokens as env vars
- **`config/openclaw-auth-profiles.template.json`** — Provider auth profiles with actual API keys
- **`scripts/setup-openclaw.sh`** — Non-interactive OpenClaw setup script (places config, env, auth profiles, generates gateway token, starts daemon)
- **`scripts/bootstrap-openclaw-workspace.sh`** — Workspace files, clawhub skills, custom skills, cron jobs
- **`openclaw-workspace/`** — Seed workspace files (AGENTS.md, SOUL.md, IDENTITY.md, USER.md, TOOLS.md, MEMORY.md, HEARTBEAT.md, docs/, tools/, scripts/, bootstrap/)
- **`openclaw-skills/`** — Custom skills to install
- **`cron-jobs/`** — Cron job JSON templates

The Terraform project should consume these SAME config artifacts. Users fill in their `openclaw-secrets.json`, `openclaw-secrets.env`, `openclaw-auth-profiles.json`, and the Terraform cloud-init uploads them to the instance and runs the setup scripts.

## Current State
- `terraform/` has: main.tf, ec2.tf, variables.tf, vpc.tf, security.tf, iam.tf, outputs.tf
- `setup.sh` is an interactive wizard for the Terraform deployment
- cloud-init in ec2.tf installs Node.js, creates openclaw user, installs openclaw globally, creates a systemd service, but does NOT configure openclaw (requires manual `openclaw onboard`)

## What to Build

### 1. New Terraform Variables (in variables.tf)

Add these optional variables so existing behavior is preserved when not set:

```hcl
# ── OpenClaw Config Files ─────────────────────────────────────────
# Pass the CONTENT of your filled-in config files.
# These match the mac-mini-setup config format exactly.

variable "openclaw_config_json" {
  description = "Content of your openclaw config JSON (from openclaw-secrets.json). Leave empty to configure manually via SSH."
  type        = string
  default     = ""
  sensitive   = true
}

variable "openclaw_env" {
  description = "Content of your openclaw .env file (API keys, tokens). Leave empty to configure manually."
  type        = string
  default     = ""
  sensitive   = true
}

variable "openclaw_auth_profiles_json" {
  description = "Content of your auth-profiles.json (provider API keys). Leave empty to skip."
  type        = string
  default     = ""
  sensitive   = true
}

# ── Workspace Seed Files ──────────────────────────────────────────
# Map of filename → content for workspace root files
variable "workspace_files" {
  description = "Map of workspace files to create (e.g. {\"SOUL.md\" = \"...\", \"USER.md\" = \"...\"})"
  type        = map(string)
  default     = {}
}

# ── Skills ────────────────────────────────────────────────────────
variable "clawhub_skills" {
  description = "List of clawhub skills to pre-install"
  type        = list(string)
  default     = []
}

variable "extra_packages" {
  description = "Extra system packages to install via dnf (e.g. [\"golang\", \"python3-pip\"])"
  type        = list(string)
  default     = []
}

# ── Owner Info (written to USER.md if no workspace_files provided) ─
variable "owner_name" {
  description = "Owner name for OpenClaw"
  type        = string
  default     = ""
}

variable "timezone" {
  description = "Timezone (e.g. America/New_York)"
  type        = string
  default     = "UTC"
}
```

### 2. Updated cloud-init in ec2.tf

The user_data script should:

1. **Install system deps** (already done: Node.js, git)
2. **Install extra packages** if `extra_packages` is set
3. **Create openclaw user** (already done)
4. **Install OpenClaw + tools** globally (openclaw, clawhub, agent-browser, mcporter)
5. **If `openclaw_config_json` is provided:**
   - Write it to `/home/openclaw/.openclaw/openclaw.json`
   - Strip empty sensitive values (the same cleanup that setup-openclaw.sh does)
6. **If `openclaw_env` is provided:**
   - Write it to `/home/openclaw/.openclaw/.env`
   - Generate gateway token if not set
   - `chmod 600`
7. **If `openclaw_auth_profiles_json` is provided:**
   - Write to `/home/openclaw/.openclaw/agents/main/agent/auth-profiles.json`
   - `chmod 600`
8. **Create workspace directory structure** (docs, tools, memory, memory/daily, scripts, etc.)
9. **If `workspace_files` is provided:**
   - Write each file to `/home/openclaw/.openclaw/workspace/`
10. **If `clawhub_skills` is provided:**
    - Install each via `su - openclaw -c "clawhub install <skill>"`
11. **Set ownership** of everything to openclaw:openclaw
12. **Create systemd user service** (not system service — openclaw should run as user)
    - Enable lingering for the openclaw user so user services start at boot
13. **If config was provided, start the gateway** automatically
14. **If config was NOT provided**, leave the "run openclaw onboard" message

Use `templatefile()` or heredoc with conditional blocks to keep it clean.

### 3. Config Format Notes

The openclaw config JSON is placed at `~/.openclaw/openclaw.json`. It's the same format as the `config/openclaw-config.template.json` in mac-mini-setup. The env file goes at `~/.openclaw/.env`. Auth profiles go at `~/.openclaw/agents/main/agent/auth-profiles.json`.

The cloud-init should also handle the empty-string cleanup that setup-openclaw.sh does — empty string values in env.vars or channel tokens cause a RangeError crash in OpenClaw's config redaction. If jq is available, strip them. Install jq as part of the base packages.

### 4. terraform.tfvars.example

Update to show the new variables with extensive comments:

```hcl
aws_region  = "us-east-1"
environment = "prod"

# ── Instance ──────────────────────────────────────────────────────
# instance_type   = "t4g.small"
# ebs_volume_size = 30

# ── OpenClaw Config ───────────────────────────────────────────────
# Option 1: Pass config file content directly
# Use: terraform plan -var-file=terraform.tfvars -var 'openclaw_config_json=...'
# Or use file(): openclaw_config_json = file("../openclaw-secrets.json")

# Option 2: Leave empty and configure manually via SSM
# openclaw_config_json = ""

# Example with file references:
# openclaw_config_json         = file("../openclaw-secrets.json")
# openclaw_env                 = file("../openclaw-secrets.env")
# openclaw_auth_profiles_json  = file("../openclaw-auth-profiles.json")

# ── Workspace Files ───────────────────────────────────────────────
# workspace_files = {
#   "SOUL.md"     = file("../openclaw-workspace/SOUL.md")
#   "USER.md"     = file("../openclaw-workspace/USER.md")
#   "AGENTS.md"   = file("../openclaw-workspace/AGENTS.md")
#   "IDENTITY.md" = file("../openclaw-workspace/IDENTITY.md")
#   "TOOLS.md"    = file("../openclaw-workspace/TOOLS.md")
# }

# ── Skills ────────────────────────────────────────────────────────
# clawhub_skills = [
#   "agent-browser",
#   "research",
#   "commit",
#   "diagrams",
#   "github",
# ]

# extra_packages = ["golang", "python3-pip"]

# ── Owner ─────────────────────────────────────────────────────────
# owner_name = "Your Name"
# timezone   = "America/New_York"
```

### 5. Updated outputs.tf

Make the "next steps" output conditional:
- If config was provided → show "OpenClaw is running! Here's how to check logs and access dashboard"
- If not → show existing manual onboard instructions

### 6. Updated README.md

Add sections:
- **Pre-Configured Deployment** — how to use with mac-mini-setup config files
- **Config Files** — explain the three config artifacts (JSON, env, auth profiles) and link to mac-mini-setup templates
- **Workspace Files** — how to seed workspace
- **Skills** — how to pre-install clawhub skills
- **Security** — note about secrets in tfvars, recommend `file()` references to gitignored files, mention AWS Secrets Manager as alternative
- **Shared Config with mac-mini-setup** — explain that both repos consume the same config format

### 7. .gitignore

Ensure these are gitignored:
- `terraform.tfvars`
- `*.tfstate*`
- `.terraform/`
- `openclaw-secrets.*`
- `openclaw-auth-profiles.json`

## Constraints
- Keep backward compatibility: if no new variables are set, behavior identical to original
- All secret variables marked `sensitive = true`
- Cloud-init must be idempotent
- Use `set -e` in bash scripts
- Generate random gateway auth token via `openssl rand -hex 24`
- Install jq in cloud-init for config cleanup
- The openclaw user should use systemd user services with lingering (not system-level service)

## Testing
After making changes:
- `cd terraform && terraform init && terraform validate` should pass
- `terraform plan` with no variables should show same resources as before
- `terraform plan` with sample variables should show the instance being created with updated user_data

## Files to Create/Modify
- MODIFY: terraform/variables.tf
- MODIFY: terraform/ec2.tf (cloud-init user_data)
- MODIFY: terraform/outputs.tf
- MODIFY: terraform/terraform.tfvars.example
- MODIFY: README.md
- MODIFY: .gitignore
