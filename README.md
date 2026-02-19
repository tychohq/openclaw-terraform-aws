# OpenClaw on AWS

One command to deploy OpenClaw on AWS — either as a blank instance you configure manually, or fully pre-configured at boot using the same config artifacts as [mac-mini-setup](https://github.com/openclaw/mac-mini-setup).

## Cost (On-Demand, eu-central-1)

- EC2 t4g.small (Linux, Shared): $0.0192 per hour
	- 730 hours/month: $0.0192 x 730 = ~$14.02
- EBS gp3 storage (30 GB): $0.0952 per GB-month
	- 30 GB: $0.0952 x 30 = ~$2.86

Estimated monthly total: ~$16.88 (~$17/month)

Excludes data transfer, snapshots, and any optional add-ons. Always review the latest AWS pricing for your region.
Pricing varies by region and instance size; adjust `instance_type` and `ebs_volume_size` in [terraform/variables.tf](terraform/variables.tf).

## Quick Start

```bash
git clone https://github.com/janobarnard/openclaw-aws.git
cd openclaw-aws
./setup.sh
```

## What the Wizard Does

The interactive wizard walks through the deployment flow:

1. **Checks prerequisites** — Terraform, AWS CLI
2. **Verifies AWS access** — Current account, profile, or assume-role
3. **Selects region** — Frankfurt, N. Virginia, or Oregon
4. **Scans for existing resources** — OpenClaw tags and local state
5. **Summarizes the plan** — Shows resources to create and asks for confirmation
6. **Deploys infrastructure** — VPC, subnet, IGW, SG, IAM, EC2
7. **Waits for instance readiness** — Confirms EC2 is ready and OpenClaw is installed

After the wizard finishes, connect over SSM and run onboarding as the `openclaw` user. The subnet is pinned to an availability zone that supports the selected instance type.

## Prerequisites

```bash
# Install Terraform (https://terraform.io/downloads)
# Install AWS CLI (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
# Install SSM Session Manager plugin if missing (https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
# Configure AWS credentials
aws configure
```

## What You Need

- AWS account with admin access
- At least one chat channel token (Telegram, Slack, Discord, WhatsApp, etc.)
- At least one LLM provider API key (OpenAI, Anthropic, etc.)

---

## Pre-Configured Deployment

Deploy OpenClaw fully configured at boot — no manual `openclaw onboard` needed. All config, workspace files, and skills come from the companion [mac-mini-setup](https://github.com/openclaw/mac-mini-setup) repo. This repo contains only Terraform infrastructure files.

### Two Ways to Source Content

**Option A: Local clone (recommended for customization)**
Clone mac-mini-setup locally, fill in secrets, reference with `file()`.

**Option B: Fetch from GitHub (no clone needed)**
Since mac-mini-setup is public, Terraform can read files directly from GitHub raw URLs. You only need to clone *this* repo — workspace files, skills, and cron jobs are fetched at plan time:

```hcl
# terraform.tfvars — pull non-secret files straight from GitHub
workspace_files = {
  "SOUL.md"  = "https://raw.githubusercontent.com/BrennerSpear/mac-mini-setup/main/openclaw-workspace/SOUL.md"
  "USER.md"  = "https://raw.githubusercontent.com/BrennerSpear/mac-mini-setup/main/openclaw-workspace/USER.md"
}
```

> **Note:** This requires adding an `http` data source in Terraform to fetch each URL — or you can use the simpler approach of just curling the files into local copies and using `file()`. See the tfvars example for both patterns.

Secrets (API keys, tokens) should never come from GitHub — always pass those via local `file()` references or environment variables.

### Sibling Repo Layout (Option A)

Both repos cloned as siblings under `~/projects/`:

```
~/projects/
├── mac-mini-setup/                       # Source of truth for all OpenClaw content
│   ├── openclaw-secrets.json             # ← fill in (from config/openclaw-config.template.json)
│   ├── openclaw-secrets.env              # ← fill in (from config/openclaw-env.template)
│   ├── openclaw-auth-profiles.json       # ← fill in (from config/openclaw-auth-profiles.template.json)
│   ├── openclaw-workspace/               # workspace files (SOUL.md, USER.md, docs/, tools/, ...)
│   ├── openclaw-skills/                  # custom skills (email/, clawdstrike/, ...)
│   └── cron-jobs/                        # cron job JSON specs
└── openclaw-terraform-aws/               # this repo (Terraform only — no content)
    └── terraform/
        └── terraform.tfvars              # all file() paths point into ../../mac-mini-setup/
```

`mac-mini-setup` is the single source of truth. The `terraform.tfvars` wires it to the instance using `file()` references — no content lives in this repo.

### Workflow

**1. Clone both repos:**

```bash
cd ~/projects
git clone https://github.com/openclaw/mac-mini-setup.git
git clone https://github.com/janobarnard/openclaw-aws.git openclaw-terraform-aws
```

**2. Fill in your secrets (in mac-mini-setup):**

```bash
cd ~/projects/mac-mini-setup
# Start from the templates, then fill in your tokens and API keys:
cp config/openclaw-config.template.json openclaw-secrets.json
cp config/openclaw-env.template          openclaw-secrets.env
cp config/openclaw-auth-profiles.template.json openclaw-auth-profiles.json

# Edit each file:
#   openclaw-secrets.json       — channels, models, agent settings, gateway config
#   openclaw-secrets.env        — API keys (ANTHROPIC_API_KEY, TELEGRAM_TOKEN, ...)
#   openclaw-auth-profiles.json — provider auth profiles
```

These three files are gitignored in mac-mini-setup and never committed.

**3. Configure Terraform:**

```bash
cd ~/projects/openclaw-terraform-aws/terraform
cp terraform.tfvars.example terraform.tfvars
# All file() paths already point to ../../mac-mini-setup/
# Edit owner_name, timezone, region, or skill lists as needed.
```

**4. Deploy:**

```bash
terraform init && terraform apply
```

Cloud-init runs automatically on first boot. After ~2 minutes, OpenClaw is running as a systemd user service.

### Updating Config and Content

**To update workspace files, skills, cron jobs, or config:**

1. Edit the relevant files in `mac-mini-setup/`
2. Re-run `terraform apply` from `openclaw-terraform-aws/terraform/`

When `workspace_files`, `custom_skills`, `cron_jobs`, or the config variables change, Terraform detects a `user_data` change and **replaces the instance**. Your updated content is baked in at boot on the new instance.

**For config-only changes without instance replacement** (secrets rotation, small tweaks):

SSM in and update the files directly:

```bash
aws ssm start-session --target <instance-id> --region <region>

# Edit config:
sudo -u openclaw vi ~/.openclaw/openclaw.json

# Update .env (API keys):
sudo -u openclaw vi ~/.openclaw/.env
sudo -u openclaw systemctl --user restart openclaw-gateway
```

Use `terraform apply` (instance replacement) for any change you want to survive a full rebuild. Use SSM for quick, ephemeral edits.

### Config Files

| File | Template in mac-mini-setup | Destination on instance |
|------|---------------------------|------------------------|
| `openclaw-secrets.json` | `config/openclaw-config.template.json` | `~/.openclaw/openclaw.json` |
| `openclaw-secrets.env` | `config/openclaw-env.template` | `~/.openclaw/.env` (chmod 600) |
| `openclaw-auth-profiles.json` | `config/openclaw-auth-profiles.template.json` | `~/.openclaw/agents/main/agent/auth-profiles.json` (chmod 600) |

### Workspace Files

Pre-populate the OpenClaw workspace with your identity and soul files. Supports nested paths — parent directories are created automatically:

```hcl
workspace_files = {
  "SOUL.md"                      = file("../../mac-mini-setup/openclaw-workspace/SOUL.md")
  "USER.md"                      = file("../../mac-mini-setup/openclaw-workspace/USER.md")
  "docs/openclaw-playbook.md"    = file("../../mac-mini-setup/openclaw-workspace/docs/openclaw-playbook.md")
  "tools/browser.md"             = file("../../mac-mini-setup/openclaw-workspace/tools/browser.md")
  "scripts/pre-commit-secrets.sh" = file("../../mac-mini-setup/openclaw-workspace/scripts/pre-commit-secrets.sh")
  "bootstrap/README.md"          = file("../../mac-mini-setup/openclaw-workspace/bootstrap/README.md")
}
```

Files are written to `/home/openclaw/.openclaw/workspace/` on the instance. See `terraform.tfvars.example` for the complete list.

If `scripts/pre-commit-secrets.sh` is included, it is automatically installed as the git pre-commit hook for the `~/.openclaw` repo (see [Pre-commit Hook](#pre-commit-hook) below).

### Custom Skills

Deploy custom skill directories to `~/.openclaw/skills/`. Each skill is a map of file paths to contents, supporting nested paths (e.g. `scripts/check.sh`, `references/response-playbook.md`):

```hcl
custom_skills = {
  "email" = {
    "SKILL.md" = file("../../mac-mini-setup/openclaw-skills/email/SKILL.md")
  }
  "clawdstrike" = {
    "SKILL.md"                    = file("../../mac-mini-setup/openclaw-skills/clawdstrike/SKILL.md")
    "references/threat-model.md"  = file("../../mac-mini-setup/openclaw-skills/clawdstrike/references/threat-model.md")
    "scripts/collect_verified.sh" = file("../../mac-mini-setup/openclaw-skills/clawdstrike/scripts/collect_verified.sh")
  }
}
```

Skills land at `/home/openclaw/.openclaw/skills/<skill-name>/` on the instance. See `terraform.tfvars.example` for all skills.

### Cron Jobs

Write cron job JSON specs to `~/.openclaw/workspace/cron-jobs/`. After the instance is up, ask OpenClaw to register them:

```hcl
cron_jobs = {
  "daily-digest"   = file("../../mac-mini-setup/cron-jobs/daily-digest.json")
  "weekly-report"  = file("../../mac-mini-setup/cron-jobs/weekly-report.json")
}
```

To register after deploy:

```
"Please register the cron jobs in ~/.openclaw/workspace/cron-jobs/"
```

### Pre-commit Hook

If `workspace_files` includes `scripts/pre-commit-secrets.sh`, cloud-init will:

1. Initialize `~/.openclaw` as a git repo (if not already)
2. Install the script as `.git/hooks/pre-commit`

This mirrors the mac-mini-setup pre-commit secrets guard on the cloud instance.

### Skills

Pre-install clawhub skills at boot (match this to `bootstrap-openclaw-workspace.sh` in mac-mini-setup):

```hcl
clawhub_skills = [
  "agent-browser",
  "research",
  "commit",
  "diagrams",
  "github",
]
```

### Extra Packages

Install additional system packages via dnf:

```hcl
extra_packages = ["golang", "python3-pip", "chromium"]
```

---

## Security

**Secrets in Terraform state**: All three config variables are marked `sensitive = true`, which prevents them from appearing in plan/apply output. However, Terraform state files contain all variable values. Ensure your state backend is encrypted (S3 with SSE, Terraform Cloud, etc.).

**Recommended approach**: Store your config files in `mac-mini-setup` and reference them with `file()`:
```hcl
openclaw_config_json = file("../../mac-mini-setup/openclaw-secrets.json")
```

The secrets files (`openclaw-secrets.*`, `openclaw-auth-profiles.json`) are gitignored in mac-mini-setup and never committed to either repo.

**Alternative**: Use AWS Secrets Manager to store config values and inject them via IAM at runtime. This avoids secrets ever touching Terraform state.

---

## Commands

```bash
# Connect to the instance (SSM shell)
aws ssm start-session --target <instance-id> --region <region>

# Run onboarding as the openclaw user (if not pre-configured)
sudo -u openclaw openclaw onboard --install-daemon

# View install log
tail -f /var/log/openclaw-install.log

# View gateway logs (user service)
sudo -u openclaw journalctl --user -u openclaw-gateway -f

# Restart gateway (user service)
sudo -u openclaw systemctl --user restart openclaw-gateway

# If a skill install fails due to missing Go (example: blogwatcher)
sudo dnf install -y golang

# Access dashboard locally via SSM port-forwarding (run from your machine)
aws ssm start-session \
	--target <instance-id> \
	--region <region> \
	--document-name AWS-StartPortForwardingSession \
	--parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

# Then open
# http://localhost:18789/
# If you see "gateway token mismatch", fetch the token with:
# sudo -u openclaw openclaw config get gateway.auth.token

# Destroy everything
cd terraform && terraform destroy
```

## License

MIT
