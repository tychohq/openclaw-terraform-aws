## Project Structure
- `setup.sh` — Interactive CLI wizard (bash), sources `.env` for defaults
- `.env` — Local secrets (gitignored), see `.env.example`
- `.env.example` — Template with all configurable values
- `terraform/` — All Terraform files
  - `main.tf` — Provider config
  - `variables.tf` — Input variables
  - `vpc.tf` — VPC, subnet, IGW
  - `security.tf` — Security group
  - `iam.tf` — IAM role + instance profile
  - `ec2.tf` — EC2 instance + cloud-init template
  - `cloud-init.sh.tftpl` — Cloud-init script (Terraform template)
  - `outputs.tf` — Output values
  - `terraform.tfvars.example` — Example tfvars (simple)
  - `terraform.tfvars.advanced.example` — Full mac-mini-setup reference
- `docs/` — Setup guides
  - `discord-bot-setup.md` — Discord bot creation, intents, permissions, channel restriction

## Quick Reference
```bash
./setup.sh            # Deploy (sources .env for defaults)
./setup.sh --destroy  # Tear down everything
```

## Rules
- Shell scripts: `set -e`, bash, no external deps beyond aws cli / terraform / jq
- Terraform: `>= 1.5.0`, AWS provider `~> 5.0`
- All sensitive vars: `sensitive = true`
- Keep backward compat — no config vars set = same behavior as before
- Never write secrets to files inside the repo directory
- Test: `cd terraform && terraform init && terraform validate` must pass

## Channel Config
### Slack (recommended for teams)
- Socket Mode by default (no public URL needed)
- Needs App Token (`xapp-...`) + Bot Token (`xoxb-...`)
- Optional `SLACK_CHANNEL_ID` restricts to a single channel
- See `docs/slack-bot-setup.md` for setup guide

### Discord
- Bot must NOT be public
- All 3 privileged gateway intents enabled (Presence, Server Members, Message Content)
- `groupPolicy: "allowlist"` — bot only responds in configured guilds
- Optional `DISCORD_CHANNEL_ID` in `.env` restricts to a single channel
- See `docs/discord-bot-setup.md` for agent-browser automation of bot creation
