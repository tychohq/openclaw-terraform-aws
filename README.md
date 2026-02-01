# OpenClaw on AWS

Deploy [OpenClaw](https://github.com/openclaw/openclaw) AI assistant on AWS.

## ⚡ Quick Start (5 minutes)

```bash
git clone https://github.com/rimaslogic/openclawonaws.git
cd openclawonaws
./setup.sh
```

That's it! The wizard handles everything.

---

## What You Need

1. **AWS account** with admin access
2. **Anthropic API key** from [console.anthropic.com](https://console.anthropic.com)
3. **Telegram bot token** from [@BotFather](https://t.me/BotFather)
4. **Domain name** — only for Simple/Full deployments

### Prerequisites

```bash
# macOS
brew install terraform awscli jq

# Ubuntu/Debian  
sudo apt install terraform awscli jq

# Configure AWS
aws configure
```

---

## Deployment Options

| | Minimal ⭐ | Simple | Full |
|--|---------|--------|------|
| **Cost** | ~$12/mo | ~$18/mo | ~$120/mo |
| **Domain needed** | ❌ No | ✅ Yes | ✅ Yes |
| **Best for** | Personal | Personal | Production |
| **Telegram mode** | Polling | Webhook | Webhook |
| **Setup time** | 5 min | 10 min | 15 min |

### Minimal (~$12/month) ⭐ Recommended

Like your VPS setup — no domain, no fuss:
```
EC2 → polls Telegram API
```

### Simple (~$18/month)

Adds webhook support with automatic HTTPS:
```
Internet → EC2 (Caddy + Let's Encrypt) → OpenClaw
```

### Full (~$120/month)

Production-grade with all security features:
```
Internet → WAF → ALB → Private EC2 → VPC Endpoints
```

---

## After Deployment

### Minimal (no domain)
Just message your Telegram bot! 🎉

### Simple/Full (with domain)
Point your domain to the IP/ALB shown in the output, then message your bot.

---

## Useful Commands

```bash
./scripts/status.sh      # Check deployment health
./scripts/connect.sh     # SSH into instance (via SSM)
./destroy.sh             # Remove everything
```

---

## Manual Deployment

```bash
cd terraform/minimal  # or simple, or full
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

See [terraform/README.md](terraform/README.md) for details.

---

## Documentation

- [Minimal Deployment](terraform/minimal/README.md) — No domain, polling mode
- [Simple Deployment](terraform/simple/README.md) — Domain + Caddy
- [Full Deployment](terraform/full/README.md) — Production security
- [Architecture](architecture.md) — Security design
- [Security Report](SECURITY-REPORT.md) — Checkov scan results

---

## License

MIT — see [LICENSE](LICENSE)
