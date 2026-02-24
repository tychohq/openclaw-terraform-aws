Read PRD-first-time-wizard.md for the current task.

## Project Structure
- `setup.sh` — Interactive CLI wizard (bash)
- `terraform/` — All Terraform files
  - `main.tf` — Provider config
  - `variables.tf` — Input variables
  - `vpc.tf` — VPC, subnet, IGW
  - `security.tf` — Security group
  - `iam.tf` — IAM role + instance profile
  - `ec2.tf` — EC2 instance + cloud-init template
  - `cloud-init.sh.tftpl` — Cloud-init script (Terraform template)
  - `outputs.tf` — Output values
  - `terraform.tfvars.example` — Example tfvars (simple)

## Rules
- Shell scripts: `set -e`, bash, no external deps beyond aws cli / terraform / jq
- Terraform: `>= 1.5.0`, AWS provider `~> 5.0`
- All sensitive vars: `sensitive = true`
- Keep backward compat — no config vars set = same behavior as before
- Never write secrets to files inside the repo directory
- Test: `cd terraform && terraform init && terraform validate` must pass
