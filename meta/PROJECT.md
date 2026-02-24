# OpenClaw on AWS - Project Overview

## Purpose

Provide a simple, minimal template for deploying OpenClaw on a single EC2 instance using Terraform and SSM-only access.

## Goals

- Minimal, easy-to-reproduce deployment on AWS
- SSM-only access (no SSH)
- Infrastructure as Code using Terraform
- Clear, accurate setup instructions

## Key Security Controls (Current Stack)

- ✅ No SSH access (SSM Session Manager only)
- ✅ Encrypted root volume (EBS)
- ✅ IMDSv2 required on the instance
- ✅ Dedicated security group with outbound-only rules

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Project overview and quick start |
| [terraform/README.md](terraform/README.md) | Terraform deployment guide |

## Cost Estimate (On-Demand, eu-central-1)

Approximate monthly cost with defaults (t4g.small + 30 GB gp3): ~$17/month.

Always review current AWS pricing for your region and adjust in [terraform/variables.tf](terraform/variables.tf).

## Potential Improvements (More Secure, More Expensive)

These are optional upgrades beyond the low-cost baseline.

- Private subnet + NAT Gateway (remove public IP)
- VPC endpoints for SSM and EC2 messages (no public egress for management)
- CloudTrail and VPC Flow Logs (audit and network visibility)
- Secrets Manager for API keys (rotation and access auditing)

## Status

🟢 Ready for deployment
