# First Boot Onboarding

Guides a new user through initial setup after their OpenClaw instance deploys.

## Trigger

This skill activates when `~/.openclaw/workspace/.first-boot` exists.
Check for this file on every message. When present, follow this flow instead of normal operation.

## Flow

### Step 1: Welcome + Identity Selection

Send a welcome message:

```
Hey! 👋 I just woke up for the first time and I don't really know who I am yet.

Head over to https://righthands.dev — browse the personas and pick the one you want me to be.

Then just send me the link (like righthands.dev/alfred-pennyworth) and I'll become that persona.

Or say "skip" to keep the default.
```

**When the user sends a righthands.dev URL:**

1. Extract the slug from the URL. Accept any of these formats:
   - `righthands.dev/alfred-pennyworth`
   - `https://righthands.dev/alfred-pennyworth`
   - `http://righthands.dev/alfred-pennyworth`
   - Just the slug like `alfred-pennyworth` (if it looks like a persona slug)

2. Fetch the persona data:
   ```bash
   curl -s "https://righthands.dev/api/persona/<slug>"
   ```

3. Parse the JSON response. It contains `identityMd`, `soulMd`, `name`, `famousLine`, and other fields.

4. If the response is a 404 or error, tell the user the slug wasn't found and ask them to try again.

5. Write the persona files:
   - Write the `identityMd` field to `~/.openclaw/workspace/IDENTITY.md`
   - Write the `soulMd` field to `~/.openclaw/workspace/SOUL.md`

6. Confirm:
   ```
   Done! I'm now **{name}**. ✨

   "{famousLine}"

   My identity and personality are set. Let me know if you want to change anything.
   ```

### Step 2: Google Workspace (conditional)

Check if GOG CLI credentials are configured:
```bash
gog auth credentials check 2>&1
```

**If no credentials exist**, skip this step entirely (don't mention Google).

**If credentials exist** but no accounts are authorized:
```
Now let's connect your Google account so I can help with Gmail, Calendar, and Drive.

What's your Google email address? (or say "skip" to set this up later)
```

When they provide an email:
```bash
gog auth add <email> --remote 2>&1
```

This command outputs an authorization URL. Extract the URL and send it:
```
Click this link to authorize Google access:
<url>

Once you've completed authorization in your browser, say "done" and I'll verify the connection.
```

When they say done/confirmed:
```bash
gog gmail search 'newer_than:1d' --max 1 --json --no-input --account <email> 2>&1
```

- Success → `"Google connected! ✅ I can now access your Gmail, Calendar, and Drive."`
- Failure → `"Hmm, authorization didn't seem to complete. Want to try the link again?"`

### Step 3: Completion

After identity is set (and Google is connected or skipped):

1. **Delete the trigger file:**
   ```bash
   rm ~/.openclaw/workspace/.first-boot
   ```

2. Send a final summary:
   ```
   All set! Here's what's configured:

   ✅ Identity: {persona name}
   ✅ Google: Connected as {email}  (or: ⏭️ Skipped)

   I'm ready to help — message me anytime!
   ```

## Skip Handling

- "skip" at identity → keep default IDENTITY.md, move to Google step
- "skip" at Google → move to completion
- "skip" at any point → advance to next step gracefully

## Important

- This is conversational — wait for user responses between steps
- Don't send all steps in one message
- The `.first-boot` file is the ONLY trigger — once deleted, this skill never activates again
- If the user sends a non-righthands URL or random text during Step 1, gently redirect them
