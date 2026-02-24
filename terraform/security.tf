# Security - Minimal Deployment (Outbound Only)

# Security Group - Outbound Only
resource "aws_security_group" "ec2" {
  name        = "${var.deployment_name}-ec2-sg"
  description = "OpenClaw EC2 - outbound only"
  vpc_id      = aws_vpc.main.id

  # No inbound rules needed - polling mode

  # Outbound for Telegram API, Anthropic API, updates
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
