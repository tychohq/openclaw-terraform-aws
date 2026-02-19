# Variables for OpenClaw AWS Deployment

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "openclaw"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.small"
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 30
}

# ── OpenClaw Config Files ──────────────────────────────────────────────────────
# Pass the CONTENT of your filled-in config files.
# These match the mac-mini-setup config format exactly.

variable "openclaw_config_json" {
  description = "Content of your openclaw config JSON (from openclaw-secrets.json). Leave empty to configure manually via SSH."
  type        = string
  default     = ""
  sensitive   = true
}

variable "openclaw_env" {
  description = "Content of your openclaw .env file (API keys, tokens). Leave empty to configure manually."
  type        = string
  default     = ""
  sensitive   = true
}

variable "openclaw_auth_profiles_json" {
  description = "Content of your auth-profiles.json (provider API keys). Leave empty to skip."
  type        = string
  default     = ""
  sensitive   = true
}

# ── Workspace Seed Files ───────────────────────────────────────────────────────
# Map of filename → content for workspace root files

variable "workspace_files" {
  description = "Map of workspace files to create (e.g. {\"SOUL.md\" = \"...\", \"USER.md\" = \"...\"})"
  type        = map(string)
  default     = {}
}

# ── Skills ─────────────────────────────────────────────────────────────────────

variable "clawhub_skills" {
  description = "List of clawhub skills to pre-install"
  type        = list(string)
  default     = []
}

variable "extra_packages" {
  description = "Extra system packages to install via dnf (e.g. [\"golang\", \"python3-pip\"])"
  type        = list(string)
  default     = []
}

# ── Owner Info (written to USER.md if no workspace_files provided) ─────────────

variable "owner_name" {
  description = "Owner name for OpenClaw"
  type        = string
  default     = ""
}

variable "timezone" {
  description = "Timezone (e.g. America/New_York)"
  type        = string
  default     = "UTC"
}
