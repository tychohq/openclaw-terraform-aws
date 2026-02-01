# OpenClaw AWS Terraform

Choose your deployment:

## 🚀 Quick Comparison

| Feature | Minimal ⭐ | Simple | Full |
|---------|---------|--------|------|
| **Cost** | ~$12/mo | ~$18/mo | ~$120/mo |
| **Domain required** | ❌ | ✅ | ✅ |
| **Telegram mode** | Polling | Webhook | Webhook |
| **TLS** | N/A | Caddy | ALB + ACM |
| **Network** | Public | Public | Private |
| **WAF** | ❌ | ❌ | ✅ |
| **VPC Endpoints** | ❌ | ❌ | ✅ |

---

## Option 1: Minimal (~$12/month) ⭐

**Best for:** Single Telegram user, no domain

```bash
cd minimal
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

[📖 Minimal README](minimal/README.md)

---

## Option 2: Simple (~$18/month)

**Best for:** Single user with domain, webhook mode

```bash
cd simple
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

[📖 Simple README](simple/README.md)

---

## Option 3: Full (~$120/month)

**Best for:** Production, multiple users, compliance

```bash
cd full
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

[📖 Full README](full/README.md)

---

## Decision Guide

```
Do you have a domain?
        │
        ├── No ──────────────► MINIMAL ($12/mo)
        │
        └── Yes
             │
             └── How many users?
                      │
                      ├── Just me ───► SIMPLE ($18/mo)
                      │
                      └── Multiple ──► FULL ($120/mo)
```

## Prerequisites

1. AWS CLI configured (`aws configure`)
2. Terraform >= 1.5.0
3. For Simple/Full: a domain name
