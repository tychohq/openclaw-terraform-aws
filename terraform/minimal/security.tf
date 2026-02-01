# Security - Minimal Deployment (Outbound Only)

# KMS Key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for OpenClaw encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-kms"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.main.key_id
}

# Security Group - Outbound Only (no inbound except SSM)
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for OpenClaw EC2 - outbound only"
  vpc_id      = aws_vpc.main.id

  # No inbound rules - polling mode doesn't need them

  # All outbound (for Telegram API, Anthropic API, package updates)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}
