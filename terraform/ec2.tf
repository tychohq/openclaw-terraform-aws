# EC2 Instance

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # Non-sensitive boolean used in outputs and user_data template
  has_config = nonsensitive(var.openclaw_config_json) != ""
}

# EC2 Instance
resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ebs_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init.sh.tftpl", {
    has_config                      = local.has_config
    openclaw_config_json_b64        = var.openclaw_config_json != "" ? base64encode(var.openclaw_config_json) : ""
    openclaw_env_b64                = var.openclaw_env != "" ? base64encode(var.openclaw_env) : ""
    openclaw_auth_profiles_json_b64 = var.openclaw_auth_profiles_json != "" ? base64encode(var.openclaw_auth_profiles_json) : ""
    workspace_files_b64             = { for k, v in var.workspace_files : k => base64encode(v) }
    custom_skills_b64               = { for skill_name, skill_files in var.custom_skills : skill_name => { for filepath, content in skill_files : filepath => base64encode(content) } }
    cron_jobs_b64                   = { for name, content in var.cron_jobs : name => base64encode(content) }
    clawhub_skills                  = var.clawhub_skills
    extra_packages                  = var.extra_packages
    owner_name                      = var.owner_name
    timezone                        = var.timezone
  }))

  tags = {
    Name = "${var.project_name}-instance"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
