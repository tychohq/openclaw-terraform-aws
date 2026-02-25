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

variable "deployment_name" {
  description = "Name for this deployment (used in resource naming and tags). Lowercase alphanumeric + hyphens."
  type        = string
  default     = "openclaw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}$", var.deployment_name))
    error_message = "deployment_name must start with a letter, be lowercase alphanumeric/hyphens, max 24 chars."
  }
}

variable "instance_type" {
  description = "EC2 instance type (t4g.medium recommended for browser automation)"
  type        = string
  default     = "t4g.medium"
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
# Map of file path → content. Supports subdirectories (e.g. "docs/openclaw-playbook.md").
# Parent directories are created automatically.

variable "workspace_files" {
  description = "Map of workspace file paths to contents (e.g. {\"SOUL.md\" = \"...\", \"docs/openclaw-playbook.md\" = \"...\"})"
  type        = map(string)
  default     = {}
}

# ── Custom Skills ─────────────────────────────────────────────────────────────
# Skill directories placed at ~/.openclaw/skills/<skill-name>/
# Each skill is a map of file paths to contents (supports nested paths like scripts/check.sh)

variable "custom_skills" {
  description = "Map of custom skill name to map of file paths and contents. E.g. {\"email\" = {\"SKILL.md\" = \"...\", \"scripts/check.sh\" = \"...\"}}"
  type        = map(map(string))
  default     = {}
}

# ── Cron Jobs ──────────────────────────────────────────────────────────────────
# Written to ~/.openclaw/workspace/cron-jobs/<name>.json for manual registration

variable "cron_jobs" {
  description = "Map of cron job name to JSON content. Written to ~/.openclaw/workspace/cron-jobs/ for manual registration via OpenClaw."
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

# ── Health Checklist ───────────────────────────────────────────────────────────

variable "deploy_checklist" {
  description = "When true, deploy the health check scripts to ~/.openclaw/workspace/scripts/checklist/"
  type        = bool
  default     = true
}

variable "checklist_checks" {
  description = "Map of health check names to enabled/disabled. Keys use underscores (e.g. {\"gateway\" = true, \"node\" = true, \"image_gen\" = false}). Controls which checks run when checklist.sh is executed."
  type        = map(bool)
  default     = {}
}
