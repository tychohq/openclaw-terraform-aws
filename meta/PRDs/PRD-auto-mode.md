# PRD: --auto Flag for setup.sh

## Goal
Add `--auto` flag to `setup.sh` that reads all values from `.env` and runs non-interactively. No prompts, no confirmations — just validate and deploy (or fail with clear errors).

## How It Works

```bash
./setup.sh --auto          # Deploy non-interactively
./setup.sh --destroy --auto  # Destroy non-interactively (no DESTROY confirmation)
```

## Requirements

### 1. Flag Parsing
- Parse `--auto` from `$@` early (before --destroy handling)
- Set `AUTO_MODE=true`
- Add `--help` / `-h` that shows usage for all flags
- **Already partially done** — check existing code first, it has `AUTO_MODE` variable and `.env` validation block already started

### 2. .env Validation (--auto only)
When `--auto` is set, validate ALL required fields BEFORE doing anything:

**Always required:**
- `DEPLOYMENT_NAME` (must match `^[a-z][a-z0-9-]{0,23}$`)
- `AWS_REGION`

**At least one LLM provider:**
- `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`

**At least one channel + its required fields:**
- Discord: `DISCORD_BOT_TOKEN` + `DISCORD_GUILD_ID` + `DISCORD_OWNER_ID`
- Telegram: `TELEGRAM_BOT_TOKEN` + `TELEGRAM_OWNER_ID`

**Optional (have sensible defaults):**
- `OWNER_NAME` (default: empty)
- `TIMEZONE` (default: "UTC")
- `DISCORD_CHANNEL_ID` (default: empty = all channels)

If ANY required field is missing, print ALL missing fields at once with helpful descriptions, then exit 1. Don't fail on the first one — show everything that's needed.

### 3. Skip All Prompts
Every `read -p` in the script must be wrapped: if `AUTO_MODE=true`, use the `.env` value (or default) instead of prompting.

Key prompts to skip:
- Step 2: AWS account choice → always "1" (current account)
- Step 3: Region → use `$AWS_REGION` from .env
- Step 4: Deployment name → use `$DEPLOYMENT_NAME` from .env
- Step 5: Config choice → always "1" (quick setup), then use .env values for all sub-prompts (API keys, tokens, IDs)
- Step 6: Existing resources warning → auto-continue (option "1")
- Step 6: "Do you want to proceed?" → auto-yes
- Step 7: "Do you want to apply?" → auto-yes
- Step 7: DESTROY confirmation (if resources being destroyed) → auto-confirm

### 4. Destroy + Auto
`./setup.sh --destroy --auto` should skip the `Type 'DESTROY' to confirm` prompt.

### 5. Logging in Auto Mode
- Still print the step headers and status messages (useful for CI logs)
- Skip the banner `clear` in auto mode
- Print a single validation summary at start: `✓ .env validated — all required values present`

## Implementation Notes

- The script already has `AUTO_MODE=false` and some partial `--auto` handling at the top. Build on what's there.
- The `ask()` helper function is already defined — use it where it helps.
- Check `AUTO_MODE` before every `read -p` call.
- The Quick Setup section (config choice "1") has complex logic with `_ENV_*` variable masking — in auto mode, just use the raw env vars directly without the masking/prompting dance.
- Don't change the `.env.example` format.
- Verify the script still works in interactive mode (no `--auto`) — don't break existing behavior.

## Testing
After implementation:
1. `./setup.sh --help` should show usage
2. Remove a required var from .env → `./setup.sh --auto` should list all missing vars
3. With complete .env → `./setup.sh --auto` should run through with zero prompts

## Non-Goals
- No `--dry-run` flag (separate concern)
- No CI/CD pipeline integration (future)
- Don't change terraform files
