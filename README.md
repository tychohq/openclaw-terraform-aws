# OpenClaw on AWS

One command to deploy OpenClaw on AWS.

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

After the wizard finishes, connect over SSM and run onboarding as the `openclaw` user.

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

## Commands

```bash
# Connect to the instance (SSM shell)
aws ssm start-session --target <instance-id> --region <region>

# Run onboarding as the openclaw user (this writes config to /home/openclaw)
# This installs and starts the gateway service.
sudo -u openclaw openclaw onboard --install-daemon

# Access dashboard locally via SSM port-forwarding (run from your machine)
aws ssm start-session \
	--target <instance-id> \
	--region <region> \
	--document-name AWS-StartPortForwardingSession \
	--parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'

# Then open
# http://localhost:18789/#token=<INSERT_TOKEN_HERE>
# If you see "gateway token mismatch", use the tokenized URL printed by onboarding
# or fetch it with: sudo -u openclaw openclaw config get gateway.auth.token

# View logs (user service)
sudo -u openclaw journalctl --user -u openclaw-gateway -f

# Restart (user service)
sudo -u openclaw systemctl --user restart openclaw-gateway

# Destroy everything
cd terraform && terraform destroy
```

## License

MIT
