# Learnings

Hard-won lessons from building and testing this deploy wizard. Read this before making changes.

## AL2023 "Minimal" AMIs Are a Trap

The AMI filter `al2023-ami-*-arm64` matches **both** standard and minimal Amazon Linux 2023 images. The minimal variant (`al2023-ami-minimal-*`) looks identical in EC2 but lacks:
- SSM agent (can't remote in)
- Many standard packages

**Fix:** Use a filter that excludes minimal: `al2023-ami-2023.*-kernel-*-arm64`

## macOS Shell Compatibility

The setup wizard runs on user machines — primarily macOS. These don't work:

| Doesn't work on macOS | Use instead |
|---|---|
| `grep -P` (Perl regex) | `grep -E` (extended regex) |
| `sed -i 's/...'` | `sed -i '' 's/...'` (empty string arg) |
| `readarray` / `mapfile` | `while read` loops |
| Unquoted `.env` values with spaces | Always double-quote values in `.env` |

**Rule:** If it's not POSIX or basic bash, test on macOS before committing.

## cloud-init: Ownership Before User Operations

`npm install -g openclaw` runs as root, creating files under `/home/openclaw/.openclaw/` owned by root. Any subsequent operation running as the `openclaw` user (like `git init`) will fail with "Permission denied".

**Fix:** Always `chown -R openclaw:openclaw /home/openclaw` **before** any `su - openclaw -c '...'` commands.

**Corollary:** `set -e` in cloud-init scripts is aggressive — one failure kills the entire script, leaving the instance half-configured (no gateway, no systemd service, nothing). If ownership is wrong, everything after it silently never runs.

## Interactive Scripts Need --auto

An agent rapid-firing Enter keys through the wizard accidentally hit "Abort" on a confirmation prompt. Interactive prompts are fine for humans but:
- Agents and CI need a non-interactive path (`--auto`)
- `--auto` should validate ALL required values upfront and fail with a complete list of what's missing
- Unknown flags should error, not silently proceed (the original script had no flag parsing — `--dry-run` just ran a full deploy)

## Terraform Plan Output Parsing Is Fragile

Parsing `terraform plan` text output with regex to extract "X to add, Y to change, Z to destroy" broke:
- `grep -P` doesn't work on macOS (see above)
- Output format varies across Terraform versions
- Color codes can interfere with matching

**Better approach:** Use `terraform show -json tfplan` for machine-readable output, or at minimum use `grep -oE` with simple patterns.

## Secrets: TF_VAR_ > -var= CLI Args

Passing JSON config via `-var='openclaw_config_json=...'` broke on shell quoting (nested quotes, special chars). `TF_VAR_` environment variables handle arbitrary content without quoting issues.

**Rule:** Always use `export TF_VAR_foo="$value"` for secrets, never `-var=` CLI args.

## Discord Bot Setup Gotchas

- **Public Bot toggle must be OFF** — otherwise anyone can add the bot to their server
- **All 3 privileged gateway intents must be ON** — Presence, Server Members, Message Content
- **Bot can't modify its own role** — if another bot has the same role position, neither can modify the other. Roles must be manually ordered in Server Settings.
- **Two layers of channel restriction:** Discord permissions (server-side, blocks visibility) + OpenClaw config `channels.<id>.allow: true` (app-side, blocks responses). Both recommended.
