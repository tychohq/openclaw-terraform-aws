# Outputs - Minimal Deployment

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.openclaw.id
}

output "public_ip" {
  description = "Public IP address (auto-assigned, may change on restart)"
  value       = aws_instance.openclaw.public_ip
}

output "secrets_arns" {
  description = "Secrets Manager ARNs"
  value = {
    anthropic_key  = aws_secretsmanager_secret.anthropic_key.arn
    telegram_token = aws_secretsmanager_secret.telegram_token.arn
  }
}

output "ssm_connect_command" {
  description = "Command to connect via SSM"
  value       = "aws ssm start-session --target ${aws_instance.openclaw.id}"
}

output "next_steps" {
  description = "Steps to complete setup"
  value       = <<-EOT

    ╔═══════════════════════════════════════════════════════════════╗
    ║                     DEPLOYMENT COMPLETE!                      ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║                                                               ║
    ║  1. Store your secrets:                                       ║
    ║                                                               ║
    ║     aws secretsmanager put-secret-value \                     ║
    ║       --secret-id ${var.project_name}/anthropic-api-key \     ║
    ║       --secret-string "sk-ant-xxx..."                         ║
    ║                                                               ║
    ║     aws secretsmanager put-secret-value \                     ║
    ║       --secret-id ${var.project_name}/telegram-bot-token \    ║
    ║       --secret-string "123456:ABC..."                         ║
    ║                                                               ║
    ║  2. Start OpenClaw:                                           ║
    ║                                                               ║
    ║     aws ssm start-session --target ${aws_instance.openclaw.id}║
    ║     sudo systemctl start openclaw                             ║
    ║                                                               ║
    ║  3. Message your Telegram bot! 🎉                             ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
  EOT
}
