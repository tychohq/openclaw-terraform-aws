# Discord Bot Setup

Step-by-step guide to creating a Discord bot for your OpenClaw deployment.

## 1. Create the Application

Go to https://discord.com/developers/applications and click **New Application**.

### With agent-browser (fast path)

```bash
# Open the Developer Portal
agent-browser --cdp 9222 open "https://discord.com/developers/applications"

# After creating the app, navigate to its page
agent-browser --cdp 9222 open "https://discord.com/developers/applications/<APP_ID>/information"

# Fill in name and description
agent-browser --cdp 9222 fill @e24 "My OpenClaw Bot"
agent-browser --cdp 9222 fill @e25 "OpenClaw bot deployed on AWS"

# Save
agent-browser --cdp 9222 snapshot -i -c | grep -i save
agent-browser --cdp 9222 click @e35  # Save Changes button (ref may vary)
```

## 2. Configure the Bot

Navigate to the **Bot** tab (left sidebar).

### Disable Public Bot

The bot should NOT be public — only you should be able to add it to servers.

```bash
agent-browser --cdp 9222 open "https://discord.com/developers/applications/<APP_ID>/bot"

# The "Public Bot" switch is typically the first switch on the page
# Check its state and uncheck if needed:
agent-browser --cdp 9222 eval "
const inputs = document.querySelectorAll('input[role=switch]');
// Index 0 = Public Bot toggle
if (inputs[0].checked) inputs[0].click();
'Public Bot disabled';
"
```

### Enable Privileged Gateway Intents

All three must be enabled for OpenClaw to work properly:

```bash
agent-browser --cdp 9222 eval "
const inputs = document.querySelectorAll('input[role=switch]');
// Index 2 = Presence Intent
// Index 3 = Server Members Intent  
// Index 4 = Message Content Intent
[2, 3, 4].forEach(i => { if (!inputs[i].checked) inputs[i].click(); });
'All intents enabled';
"

# Save
agent-browser --cdp 9222 snapshot -i -c | grep -i save
agent-browser --cdp 9222 click @<save_ref>
```

### Get the Bot Token

Click **Reset Token** on the Bot page. Discord will ask for your password — you must enter this manually. The token is shown only once; copy it immediately.

Store the token:
- In `.env` as `DISCORD_BOT_TOKEN=<token>`
- Or in 1Password / your preferred secret store

## 3. Invite the Bot to Your Server

Build the OAuth2 invite URL:

```
https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=277025770560
```

The permission integer `277025770560` includes:
- View Channels
- Send Messages
- Send Messages in Threads
- Embed Links
- Attach Files
- Read Message History
- Add Reactions
- Use External Emoji
- Use Application Commands

```bash
agent-browser --cdp 9222 open "https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=277025770560"

# Click through: Continue to Discord → Select server → Authorize
```

## 4. Restrict Bot to a Specific Channel

By default, the bot can see all channels. To restrict it to one channel:

### Discord Side (recommended)

The bot gets an auto-created role with the same name as the bot. Find it in **Server Settings → Roles**.

1. Go to **Server Settings → Roles** → click the bot's role (e.g. "OpenClaw AWS Test")
2. Under the role's base permissions, **disable** "View Channels"
3. Go to the target channel → **Edit Channel → Permissions**
4. Add the bot's role → **Allow**: View Channel, Send Messages, Embed Links, Attach Files, Read Message History, Add Reactions

This way the bot physically cannot see any other channel.

### OpenClaw Side (config-level)

In the OpenClaw config JSON, add the channel ID under the guild config:

```json
{
  "channels": {
    "discord": {
      "guilds": {
        "<GUILD_ID>": {
          "requireMention": false,
          "channels": {
            "<CHANNEL_ID>": {
              "allow": true
            }
          }
        }
      }
    }
  }
}
```

With `groupPolicy: "allowlist"`, the bot will only respond in explicitly configured guilds. Adding `channels` further restricts it to specific channels within that guild.

### Both Layers Together

For maximum safety, use both:
- **Discord permissions** prevent the bot from even seeing other channels
- **OpenClaw config** ensures the bot only responds where configured, even if Discord permissions are misconfigured

## 5. Values for .env

After setup, your `.env` should have:

```bash
DISCORD_BOT_TOKEN=<token from step 3>
DISCORD_GUILD_ID=<right-click server → Copy Server ID>
DISCORD_CHANNEL_ID=<right-click channel → Copy Channel ID>  # optional, restricts to one channel
DISCORD_OWNER_ID=<right-click yourself → Copy User ID>
```

## Reference: Discord Switch Indices on Bot Page

When automating with agent-browser, the `input[role=switch]` elements on the Bot page are:

| Index | Toggle | Default |
|-------|--------|---------|
| 0 | Public Bot | ✅ ON (disable this) |
| 1 | Require OAuth2 Code Grant | ❌ OFF |
| 2 | Presence Intent | ❌ OFF (enable this) |
| 3 | Server Members Intent | ❌ OFF (enable this) |
| 4 | Message Content Intent | ❌ OFF (enable this) |
