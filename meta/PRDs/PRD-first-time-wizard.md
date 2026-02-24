# PRD: First-Time Setup Wizard — Zero to Running OpenClaw

## Goal

Extend `setup.sh` so a first-time user can go from `git clone` to a fully connected OpenClaw instance with **one command** (`./setup.sh`). No mac-mini-setup repo needed. No SSM-in-and-onboard step. The wizard collects everything inline and generates the Terraform config.

Also: make tear-down and rebuild trivial so we can iterate on getting the flow smooth.

## Context

The current wizard handles AWS infra (creds, region, plan, apply) but does NOT collect OpenClaw config. After deploy, the user must SSM in and run `openclaw onboard`. We want to eliminate that manual step entirely.

The `mac-mini-setup` sibling-repo approach stays as the **advanced path** (documented in README). This PRD is about the **first-time / simple path** where you just answer prompts and go.

## What to Build

### 1. Add `deployment_name` Variable

**File: `terraform/variables.tf`**

Add a new variable at the top:

```hcl
variable "deployment_name" {
  description = "Name for this deployment (used in resource naming and tags). Lowercase alphanumeric + hyphens."
  type        = string
  default     = "openclaw"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}$", var.deployment_name))
    error_message = "deployment_name must start with a letter, be lowercase alphanumeric/hyphens, max 24 chars."
  }
}
```

**Replace `var.project_name` with `var.deployment_name` everywhere:**
- `vpc.tf` — all `Name` tags use `${var.deployment_name}-*`
- `security.tf` — SG name and tags
- `iam.tf` — role name, instance profile name, tags
- `ec2.tf` — instance tag
- `main.tf` — default tags `Project = var.deployment_name`

**Remove `var.project_name`** — it's replaced by `deployment_name`.

Also update the resource scan in `setup.sh` to search for the deployment name instead of hardcoded "openclaw".

### 2. Extend the Wizard with OpenClaw Config Collection

**File: `setup.sh`**

After the region selection (Step 3) and before infrastructure scan (Step 4), add new wizard steps to collect OpenClaw config:

#### Step: Deployment Name

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
STEP X: Name Your Deployment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Give this deployment a name. Used for AWS resource tags
and to distinguish multiple deployments.

Examples: my-openclaw, work-agent, home-assistant

Name [openclaw]: 
```

Validate: lowercase, alphanumeric + hyphens, starts with letter, max 24 chars.

#### Step: Configuration Mode

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
STEP X: Configure OpenClaw
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

How do you want to configure OpenClaw?

  1) Quick setup — enter API key + channel token (recommended for first time)
  2) Config files — point to existing openclaw config files
  3) Skip — configure manually after deploy via SSM

Choose [1-3, default 1]:
```

#### Option 1: Quick Setup (First-Time Path)

Collect the minimum viable config inline:

```
── LLM Provider ──────────────────────────────

Which LLM provider? (you need at least one)

  1) Anthropic (Claude) — recommended
  2) OpenAI (GPT)
  3) Both

Choose [1-3, default 1]:

Anthropic API key: sk-ant-...
```

Then:

```
── Chat Channel ──────────────────────────────

How will you talk to your OpenClaw?

  1) Discord bot
  2) Telegram bot
  3) Both

Choose [1-3, default 1]:
```

For **Discord**:
```
Discord bot token: 
Discord guild (server) ID (right-click server → Copy Server ID):
Your Discord user ID (right-click yourself → Copy User ID):
```

For **Telegram**:
```
Telegram bot token (from @BotFather):
Telegram owner chat ID (your numeric user ID):
```

Then:

```
── Owner Info ────────────────────────────────

Your name (for the agent to know who you are): 
Timezone [America/New_York]:
```

The wizard generates:
1. **`openclaw.json`** — minimal but complete config with the provided channel(s) and model provider(s)
2. **`.env`** — API keys + tokens + auto-generated `GATEWAY_AUTH_TOKEN`

These get passed as `openclaw_config_json` and `openclaw_env` Terraform variables.

#### Option 2: Config Files

```
Point to your config files. Leave blank to skip any.

OpenClaw config JSON (openclaw.json):
  Path [../../mac-mini-setup/openclaw-secrets.json]: 

OpenClaw .env (API keys):
  Path [../../mac-mini-setup/openclaw-secrets.env]:

Auth profiles JSON:
  Path [../../mac-mini-setup/openclaw-auth-profiles.json]:
```

Validate that files exist. Read their contents and pass to Terraform.

#### Option 3: Skip

Behaves exactly like today — deploy infra, then SSM in and onboard manually.

### 3. Config Generation (for Quick Setup)

The wizard needs to generate a minimal `openclaw.json`. Create a template at `templates/openclaw-minimal.json`:

```json
{
  "gateway": {
    "auth": {
      "token": "__GATEWAY_TOKEN__"
    },
    "port": 18789
  },
  "channels": {
    "__CHANNEL_TYPE__": {
      "enabled": true,
      "__CHANNEL_CONFIG__": "filled by wizard"
    }
  },
  "agents": {
    "main": {
      "model": "__MODEL__",
      "provider": "__PROVIDER__"
    }
  }
}
```

Actually — don't use a template file. Generate the JSON inline with `jq` in the wizard script. This keeps it self-contained:

```bash
# Generate minimal openclaw.json
GATEWAY_TOKEN=$(openssl rand -hex 24)

CONFIG_JSON=$(jq -n \
  --arg gw_token "$GATEWAY_TOKEN" \
  --arg gw_port "18789" \
  '{
    gateway: {
      auth: { token: $gw_token },
      port: ($gw_port | tonumber)
    }
  }')

# Add Discord channel if configured
# Discord config uses guilds → channels structure.
# For first-time setup, we allow all channels in the guild.
if [ -n "$DISCORD_TOKEN" ]; then
  CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
    --arg token "$DISCORD_TOKEN" \
    --arg guild_id "$DISCORD_GUILD_ID" \
    --arg owner_id "$DISCORD_OWNER_ID" \
    '.channels.discord = {
      enabled: true,
      token: $token,
      groupPolicy: "allowlist",
      dmPolicy: "pairing",
      allowFrom: [$owner_id],
      guilds: {
        ($guild_id): {
          requireMention: false
        }
      }
    }')
fi

# Add Telegram channel if configured
# Telegram uses botToken, allowFrom, groupPolicy, dmPolicy.
if [ -n "$TELEGRAM_TOKEN" ]; then
  CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
    --arg token "$TELEGRAM_TOKEN" \
    --arg owner_id "$TELEGRAM_OWNER_ID" \
    '.channels.telegram = {
      enabled: true,
      botToken: $token,
      dmPolicy: "pairing",
      groupPolicy: "allowlist",
      allowFrom: [$owner_id]
    }')
fi

# Add model config
if [ -n "$ANTHROPIC_API_KEY" ]; then
  CONFIG_JSON=$(echo "$CONFIG_JSON" | jq \
    '.agents.main.model = "claude-sonnet-4-20250514" |
     .agents.main.provider = "anthropic"')
fi
```

And generate the `.env`:

```bash
ENV_CONTENT=""
[ -n "$ANTHROPIC_API_KEY" ] && ENV_CONTENT+="ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY\n"
[ -n "$OPENAI_API_KEY" ] && ENV_CONTENT+="OPENAI_API_KEY=$OPENAI_API_KEY\n"
ENV_CONTENT+="GATEWAY_AUTH_TOKEN=$GATEWAY_TOKEN\n"
# Note: Discord token and Telegram botToken go in openclaw.json, not .env.
# The .env is for API keys and the gateway auth token.
```

### 4. Wire Config into Terraform

The wizard currently creates a minimal `terraform.tfvars` with just the region. Extend it to include config:

```bash
# Write terraform.tfvars
cat > terraform.tfvars << EOF
aws_region      = "$AWS_REGION"
deployment_name = "$DEPLOYMENT_NAME"
timezone        = "$TIMEZONE"
owner_name      = "$OWNER_NAME"
EOF

# If quick setup or config files were provided, add them as .auto.tfvars
# Use a separate file so terraform.tfvars stays clean
if [ -n "$CONFIG_JSON" ]; then
  # Write config to temp files, reference via -var flags
  echo "$CONFIG_JSON" > /tmp/openclaw-config.json
  echo -e "$ENV_CONTENT" > /tmp/openclaw-env
fi
```

Actually, the cleanest approach: write the secrets to temp files and pass them as `-var` flags to terraform plan/apply. This avoids writing secrets to disk in the repo:

```bash
terraform plan -input=false -out=tfplan \
  -var "deployment_name=$DEPLOYMENT_NAME" \
  -var "openclaw_config_json=$(cat /tmp/openclaw-config.json)" \
  -var "openclaw_env=$(cat /tmp/openclaw-env)" \
  -var "owner_name=$OWNER_NAME" \
  -var "timezone=$TIMEZONE"
```

Clean up temp files after apply completes.

### 5. Tear-Down Support

Add a `--destroy` flag to `setup.sh`:

```bash
./setup.sh --destroy
```

This should:
1. Check for existing Terraform state in `terraform/`
2. Show what will be destroyed
3. Confirm
4. Run `terraform destroy -auto-approve`
5. Clean up local state files

Also add to the completion output:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TEAR DOWN & REBUILD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # Destroy everything and start over:
  ./setup.sh --destroy

  # Then re-deploy:
  ./setup.sh
```

### 6. Update Step Numbers

After adding the new steps, renumber everything. The flow should be:

1. Check Prerequisites
2. Verify AWS Account Access  
3. Select AWS Region
4. Name Your Deployment
5. Configure OpenClaw (Quick Setup / Config Files / Skip)
6. Scan for Existing Resources (use deployment_name for tag search)
7. Deploy Infrastructure
8. Wait for Instance + Verify

### 7. Post-Deploy Verification

After the instance is ready and cloud-init has run, the wizard should verify the gateway started:

```bash
# Wait for cloud-init to complete
echo "Waiting for OpenClaw to install and start..."

# Poll SSM for cloud-init completion (up to 5 minutes)
for i in $(seq 1 30); do
  STATUS=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cloud-init status --format json"]' \
    --region "$AWS_REGION" \
    --output json 2>/dev/null | jq -r '.Command.CommandId' 2>/dev/null)
  
  if [ -n "$STATUS" ]; then
    sleep 5
    RESULT=$(aws ssm get-command-invocation \
      --command-id "$STATUS" \
      --instance-id "$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --output json 2>/dev/null | jq -r '.StandardOutputContent' 2>/dev/null)
    
    if echo "$RESULT" | grep -q '"status": "done"'; then
      break
    fi
  fi
  
  sleep 10
done
```

Actually, keep it simple — just wait a fixed time with a progress indicator. SSM command execution adds complexity. The existing 60-second wait is fine, maybe bump to 90s:

```bash
echo "  Waiting for cloud-init to complete (this takes ~2 minutes)..."
for i in $(seq 1 12); do
  sleep 10
  echo -n "."
done
echo ""
```

### 8. Minimal Config: What OpenClaw Actually Needs

Research the actual minimal `openclaw.json` structure. Based on the OpenClaw docs and existing templates, the minimum viable config needs:

- `gateway.auth.token` — auto-generated
- `gateway.port` — 18789
- At least one channel configured and enabled
- Agent model + provider (defaults work if env vars are set)

The `.env` file needs:
- At least one LLM API key (`ANTHROPIC_API_KEY` or `OPENAI_API_KEY`)
- Channel tokens (can also be in the JSON, but env is cleaner)
- `GATEWAY_AUTH_TOKEN`

**Important:** Check the OpenClaw docs to get the exact JSON structure for Discord and Telegram channels. Don't guess — read the actual config format. The agent should look at `~/.openclaw/workspace/docs/` or the OpenClaw source to get this right.

### 9. Update terraform.tfvars.example

Split into two examples:

**`terraform.tfvars.example`** — Simple/first-time (no mac-mini-setup):

```hcl
# Simple deployment — fill in the basics, deploy, done.
# For advanced config with workspace files and skills, see terraform.tfvars.advanced.example

aws_region      = "us-east-1"
deployment_name = "my-openclaw"
owner_name      = "Your Name"
timezone        = "America/New_York"

# Minimal config — just API key + channel
# Generate your own: openssl rand -hex 24
openclaw_config_json = jsonencode({
  gateway = {
    auth = { token = "YOUR_GATEWAY_TOKEN" }
    port = 18789
  }
  channels = {
    discord = {
      enabled      = true
      token        = "YOUR_DISCORD_BOT_TOKEN"
      groupPolicy  = "allowlist"
      dmPolicy     = "pairing"
      allowFrom    = ["YOUR_DISCORD_USER_ID"]
      guilds = {
        "YOUR_GUILD_ID" = {
          requireMention = false
        }
      }
    }
  }
})

openclaw_env = <<-EOT
  ANTHROPIC_API_KEY=sk-ant-...
  GATEWAY_AUTH_TOKEN=YOUR_GATEWAY_TOKEN
EOT
```

**`terraform.tfvars.advanced.example`** — rename current example to this, for mac-mini-setup users.

## Files to Create/Modify

- **MODIFY:** `setup.sh` — add config collection, deployment name, --destroy flag
- **MODIFY:** `terraform/variables.tf` — add `deployment_name`, remove `project_name`
- **MODIFY:** `terraform/vpc.tf` — use `deployment_name`
- **MODIFY:** `terraform/security.tf` — use `deployment_name`
- **MODIFY:** `terraform/iam.tf` — use `deployment_name`
- **MODIFY:** `terraform/ec2.tf` — use `deployment_name`
- **MODIFY:** `terraform/main.tf` — use `deployment_name` in default tags
- **MODIFY:** `terraform/outputs.tf` — use `deployment_name`
- **CREATE:** `terraform/terraform.tfvars.advanced.example` — rename current example
- **MODIFY:** `terraform/terraform.tfvars.example` — simple first-time version
- **MODIFY:** `README.md` — update quick start, add first-time vs advanced sections

## Constraints

- `jq` must be installed locally for the wizard to generate config JSON. Add it to prerequisites check.
- Secrets should never be written to files inside the repo directory. Use `/tmp/` or `-var` flags.
- The wizard must be idempotent — running it again should detect existing state and offer to destroy first.
- Keep backward compatibility — running with just `aws_region` and no config should work exactly as before.
- All secret-containing variables stay `sensitive = true`.
- The `--destroy` flag should be safe — confirm before doing anything.

## Testing Plan

1. `terraform validate` passes with no variables set
2. `terraform validate` passes with just `deployment_name`
3. `terraform plan` with a generated config shows correct user_data
4. `./setup.sh --destroy` tears down cleanly
5. Full end-to-end: `./setup.sh` → quick setup → instance comes up → gateway is running → can message via Discord/Telegram
