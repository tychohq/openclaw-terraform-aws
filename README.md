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

Deploy OpenClaw fully configured at boot — no manual `openclaw onboard` needed. This uses the same config artifacts as the mac-mini-setup repo, so you can share a single set of config files across both deployments.

### Shared Config with mac-mini-setup

Both this repo and mac-mini-setup consume the **same three config files**:

| File | Purpose | Destination on instance |
|------|---------|------------------------|
| `openclaw-secrets.json` | Full OpenClaw config (channels, models, agents, gateway, skills) | `~/.openclaw/openclaw.json` |
| `openclaw-secrets.env` | API keys and channel tokens as env vars | `~/.openclaw/.env` |
| `openclaw-auth-profiles.json` | Provider auth profiles with API keys | `~/.openclaw/agents/main/agent/auth-profiles.json` |

Fill in your copies of these files once and reference them from both repos.

### Setup

1. Copy the example tfvars:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```

2. Edit `terraform/terraform.tfvars` to reference your filled-in config files:
   ```hcl
   openclaw_config_json        = file("../openclaw-secrets.json")
   openclaw_env                = file("../openclaw-secrets.env")
   openclaw_auth_profiles_json = file("../openclaw-auth-profiles.json")
   ```

3. Deploy:
   ```bash
   cd terraform && terraform init && terraform apply
   ```

Cloud-init runs automatically on first boot. After ~2 minutes, OpenClaw is running as a systemd user service.

### Config Files

**`openclaw-secrets.json`** — The main OpenClaw config. Use `config/openclaw-config.template.json` from mac-mini-setup as your starting point. Fill in your channel tokens, model preferences, agent settings, and gateway config.

**`openclaw-secrets.env`** — API keys and tokens as shell environment variables. Use `config/openclaw-env.template` from mac-mini-setup. This file gets `chmod 600` on the instance.

**`openclaw-auth-profiles.json`** — Provider auth profiles used by OpenClaw's agent subsystem. Use `config/openclaw-auth-profiles.template.json` from mac-mini-setup. Also `chmod 600` on the instance.

### Workspace Files

Pre-populate the OpenClaw workspace with your identity and soul files:

```hcl
workspace_files = {
  "SOUL.md"     = file("../openclaw-workspace/SOUL.md")
  "USER.md"     = file("../openclaw-workspace/USER.md")
  "AGENTS.md"   = file("../openclaw-workspace/AGENTS.md")
  "IDENTITY.md" = file("../openclaw-workspace/IDENTITY.md")
  "TOOLS.md"    = file("../openclaw-workspace/TOOLS.md")
  "MEMORY.md"   = file("../openclaw-workspace/MEMORY.md")
}
```

Files are written to `/home/openclaw/.openclaw/workspace/` on the instance.

### Skills

Pre-install clawhub skills at boot:

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
extra_packages = ["golang", "python3-pip"]
```

---

## Security

**Secrets in Terraform state**: All three config variables are marked `sensitive = true`, which prevents them from appearing in plan/apply output. However, Terraform state files contain all variable values. Ensure your state backend is encrypted (S3 with SSE, Terraform Cloud, etc.).

**Recommended approach**: Store your config files outside the repo and reference them with `file()`:
```hcl
openclaw_config_json = file("../openclaw-secrets.json")
```

Add `openclaw-secrets.*` and `openclaw-auth-profiles.json` to your global `.gitignore` to prevent accidental commits.

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
