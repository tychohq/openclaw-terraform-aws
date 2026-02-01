# OpenClaw AWS - Minimal Deployment

**No domain required!** Uses Telegram polling mode, just like a local VPS.

## Cost: ~$12/month

| Component | Cost |
|-----------|------|
| EC2 t3.micro | $7.59 |
| EBS 20GB | $1.60 |
| Secrets Manager (2) | $0.80 |
| KMS | $1.00 |
| **Total** | **~$11-12** |

## Architecture

```
EC2 (polls) → Telegram API
EC2 (calls) → Anthropic API
     ↓
Secrets Manager
```

No inbound traffic. No domain. No certificates.

## Quick Start

```bash
cd terraform/minimal
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## After Deployment

1. **Store secrets:**
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id openclaw/anthropic-api-key \
     --secret-string "sk-ant-xxx"
   
   aws secretsmanager put-secret-value \
     --secret-id openclaw/telegram-bot-token \
     --secret-string "123456:ABC"
   ```

2. **Start OpenClaw:**
   ```bash
   aws ssm start-session --target <instance-id>
   sudo systemctl start openclaw
   ```

3. **Message your Telegram bot!**

## Notes

- Public IP is auto-assigned and may change on instance restart
- Use SSM Session Manager to connect (no SSH needed)
- Logs: `sudo journalctl -u openclaw -f`

## When to use Simple/Full instead

Choose **Simple** ($18/mo) or **Full** ($120/mo) if you need:
- Webhook mode (lower latency)
- Static IP / domain
- Multiple channels (not just Telegram)
- Production security features
