# Security Group - Created or Existing
#
# When existing_security_group_id is set, we use it directly.
# Otherwise, we create a minimal outbound-only SG.

locals {
  use_existing_sg   = var.existing_security_group_id != ""
  security_group_id = local.use_existing_sg ? var.existing_security_group_id : aws_security_group.ec2[0].id
}

# ── New SG (when no existing SG provided) ─────────────────────────────────────

resource "aws_security_group" "ec2" {
  count       = local.use_existing_sg ? 0 : 1
  name        = "${var.deployment_name}-ec2-sg"
  description = "OpenClaw EC2 - outbound only"
  vpc_id      = local.vpc_id

  # No inbound rules — polling/socket mode only

  # Outbound for Slack/Discord/Telegram API, Anthropic API, updates
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.deployment_name}-ec2-sg"
  }
}
