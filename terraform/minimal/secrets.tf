# Secrets Manager - Minimal Deployment

resource "aws_secretsmanager_secret" "anthropic_key" {
  name                    = "${var.project_name}/anthropic-api-key"
  description             = "Anthropic API key for Claude"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-anthropic-key"
  }
}

resource "aws_secretsmanager_secret" "telegram_token" {
  name                    = "${var.project_name}/telegram-bot-token"
  description             = "Telegram bot token"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-telegram-token"
  }
}
