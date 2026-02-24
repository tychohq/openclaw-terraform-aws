# Slack Bot Setup Guide

Create a Slack app for OpenClaw to connect to your workspace via Socket Mode.

## Step 1: Create the Slack App

1. Go to **https://api.slack.com/apps**
2. Click **Create New App** → **From scratch**
3. Name: `OpenClaw` (or whatever you want)
4. Pick your workspace
5. Click **Create App**

## Step 2: Enable Socket Mode

1. In the left sidebar: **Socket Mode**
2. Toggle **Enable Socket Mode** → ON
3. It will prompt you to create an **App-Level Token**
   - Name: `openclaw-socket` (or anything)
   - Scope: `connections:write`
   - Click **Generate**
4. **Copy the `xapp-...` token** → this is your `SLACK_APP_TOKEN`

## Step 3: Configure Bot Scopes

1. Left sidebar: **OAuth & Permissions**
2. Scroll to **Scopes** → **Bot Token Scopes**
3. Add these scopes:

| Scope | Why |
|-------|-----|
| `chat:write` | Send messages |
| `channels:history` | Read channel messages |
| `channels:read` | List channels |
| `groups:history` | Read private channel messages |
| `im:history` | Read DMs |
| `mpim:history` | Read group DMs |
| `users:read` | Look up user info |
| `app_mentions:read` | Respond to @mentions |
| `reactions:read` | Read reactions |
| `reactions:write` | Add reactions |
| `pins:read` | Read pins |
| `pins:write` | Pin messages |
| `emoji:read` | List custom emoji |
| `commands` | Slash commands |
| `files:read` | Read uploaded files |
| `files:write` | Upload files |

Optional (for streaming "typing" indicators):
| `assistant:write` | Show typing status in threads |

## Step 4: Install App to Workspace

1. Left sidebar: **OAuth & Permissions**
2. Click **Install to Workspace** (or **Reinstall** if updating scopes)
3. Authorize the permissions
4. **Copy the `xoxb-...` token** → this is your `SLACK_BOT_TOKEN`

## Step 5: Subscribe to Events

1. Left sidebar: **Event Subscriptions**
2. Toggle **Enable Events** → ON
3. Under **Subscribe to bot events**, add:

| Event | Why |
|-------|-----|
| `app_mention` | Respond when @mentioned |
| `message.channels` | Messages in public channels |
| `message.groups` | Messages in private channels |
| `message.im` | Direct messages |
| `message.mpim` | Group DMs |
| `reaction_added` | React events |
| `reaction_removed` | Unreact events |
| `member_joined_channel` | Track joins |
| `member_left_channel` | Track leaves |
| `channel_rename` | Channel renames |
| `pin_added` | Pin events |
| `pin_removed` | Unpin events |

4. Click **Save Changes**

## Step 6: Enable App Home (for DMs)

1. Left sidebar: **App Home**
2. Under **Show Tabs**, enable **Messages Tab**
3. Check **Allow users to send Slash commands and messages from the messages tab**

## Step 7: Add to Your .env

```bash
SLACK_APP_TOKEN="xapp-1-..."
SLACK_BOT_TOKEN="xoxb-..."
# Optional: restrict to a single channel
# SLACK_CHANNEL_ID="C0123456789"
```

## Step 8: Invite Bot to Channels

The bot won't see messages in channels it hasn't been added to.

In each Slack channel you want OpenClaw to participate in:
- Type `/invite @OpenClaw` (or whatever you named the bot)

## Optional: Restrict to Specific Channel

If you set `SLACK_CHANNEL_ID` in `.env`, OpenClaw will only respond in that channel.

To get a channel ID:
1. Right-click the channel name in Slack
2. Click **View channel details**
3. Scroll to the bottom — the Channel ID is displayed there

## Quick Manifest (Alternative Setup)

Instead of clicking through the UI, you can paste this app manifest at
**https://api.slack.com/apps** → **Create New App** → **From an app manifest**:

```json
{
  "display_information": {
    "name": "OpenClaw",
    "description": "OpenClaw AI assistant"
  },
  "features": {
    "bot_user": {
      "display_name": "OpenClaw",
      "always_online": false
    },
    "app_home": {
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "chat:write",
        "channels:history",
        "channels:read",
        "groups:history",
        "im:history",
        "mpim:history",
        "users:read",
        "app_mentions:read",
        "assistant:write",
        "reactions:read",
        "reactions:write",
        "pins:read",
        "pins:write",
        "emoji:read",
        "commands",
        "files:read",
        "files:write"
      ]
    }
  },
  "settings": {
    "socket_mode_enabled": true,
    "event_subscriptions": {
      "bot_events": [
        "app_mention",
        "message.channels",
        "message.groups",
        "message.im",
        "message.mpim",
        "reaction_added",
        "reaction_removed",
        "member_joined_channel",
        "member_left_channel",
        "channel_rename",
        "pin_added",
        "pin_removed"
      ]
    }
  }
}
```

After creating from manifest, you still need to:
1. Go to **Socket Mode** → generate an App Token with `connections:write`
2. Go to **OAuth & Permissions** → copy the Bot Token
