# OpenClaw on AWS

One command to deploy OpenClaw on AWS.

## Cost: ~$10/month

## Quick Start

```bash
git clone https://github.com/rimaslogic/openclawonaws.git
cd openclawonaws
./setup.sh
```

## What the Wizard Does

The interactive wizard guides you through everything:

1. **Checks prerequisites** — Terraform, AWS CLI
2. **Verifies AWS access** — Shows account ID, asks for confirmation
3. **Selects region** — Frankfurt, N. Virginia, or Oregon
4. **Checks existing resources** — Warns if OpenClaw already deployed
5. **Collects credentials** — Telegram token, Anthropic API key
6. **Deploys infrastructure** — VPC, EC2, security groups
7. **Configures OpenClaw** — Installs and starts the service

**Then just message your Telegram bot!**

## Prerequisites

```bash
# macOS
brew install terraform awscli

# Ubuntu
apt install terraform awscli

# Configure AWS credentials
aws configure
```

## What You Need

- AWS account with admin access
- Telegram bot token (from @BotFather)
- Anthropic API key (from console.anthropic.com)

## Commands

```bash
# Connect to instance
aws ssm start-session --target <instance-id>

# View logs
sudo journalctl -u openclaw -f

# Restart
sudo systemctl restart openclaw

# Destroy everything
cd terraform && terraform destroy
```

## License

MIT
