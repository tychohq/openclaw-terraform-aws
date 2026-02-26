# Outputs

locals {
  _next_steps_configured = <<-EOT

    ╔════════════════════════════════════════════════════════════╗
    ║          OPENCLAW IS DEPLOYED AND CONFIGURED!              ║
    ╠════════════════════════════════════════════════════════════╣
    ║                                                            ║
    ║  OpenClaw was pre-configured and is starting up now.       ║
    ║  Allow ~2 min for cloud-init to complete.                  ║
    ║                                                            ║
    ║  1. Check install progress:                                ║
    ║                                                            ║
    ║     aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}
    ║     tail -f /var/log/openclaw-install.log                  ║
    ║                                                            ║
    ║  2. View gateway logs:                                     ║
    ║                                                            ║
    ║     sudo -u openclaw journalctl --user -u openclaw-gateway -f
    ║                                                            ║
    ║  3. Open dashboard via SSM port forward:                   ║
    ║                                                            ║
    ║     aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region} \
    ║       --document-name AWS-StartPortForwardingSession \
    ║       --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
    ║                                                            ║
    ║     http://localhost:18789/                                ║
    ║                                                            ║
    ╚════════════════════════════════════════════════════════════╝
  EOT

  _next_steps_manual = <<-EOT

    ╔════════════════════════════════════════════════════════════╗
    ║                   SETUP COMPLETE! 🎉                       ║
    ╠════════════════════════════════════════════════════════════╣
    ║                                                            ║
    ║  1. Connect to your instance:                              ║
    ║                                                            ║
    ║     aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}
    ║                                                            ║
    ║  2. Initialize OpenClaw (enter your API keys):             ║
    ║                                                            ║
    ║     sudo -u openclaw openclaw onboard --install-daemon      ║
    ║                                                            ║
    ║  3. Open dashboard locally (SSM port forward):             ║
    ║                                                            ║
    ║     aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region} \
    ║       --document-name AWS-StartPortForwardingSession \
    ║       --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
    ║                                                            ║
    ║     http://localhost:18789/                                ║
    ║     Token: sudo -u openclaw openclaw config get gateway.auth.token ║
    ║                                                            ║
    ╚════════════════════════════════════════════════════════════╝
  EOT
}

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.openclaw.id
}

output "public_ip" {
  description = "Public IP (may change on restart; empty if in private subnet)"
  value       = aws_instance.openclaw.public_ip
}

output "private_ip" {
  description = "Private IP address"
  value       = aws_instance.openclaw.private_ip
}

output "connect_command" {
  description = "Connect via SSM"
  value       = "aws ssm start-session --target ${aws_instance.openclaw.id} --region ${var.aws_region}"
}

output "next_steps" {
  value = local.has_config ? local._next_steps_configured : local._next_steps_manual
}
