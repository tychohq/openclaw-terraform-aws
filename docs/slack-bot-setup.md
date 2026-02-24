# Slack Bot Setup Guide

Create a Slack app for OpenClaw to connect to your workspace via Socket Mode.

## Option A: From App Manifest (Recommended)

1. Go to **https://api.slack.com/apps**
2. Click **Create New App** → **From an app manifest**
3. Select your workspace
4. Paste the contents of [`templates/slack-app-manifest.json`](../templates/slack-app-manifest.json)
5. Click **Create**
6. Go to **Socket Mode** (left sidebar) → generate an App-Level Token
   - Name: `openclaw-socket` (or anything)
   - Scope: `connections:write`
   - Click **Generate**
   - **Copy the `xapp-...` token** → this is your `SLACK_APP_TOKEN`
7. Go to **OAuth & Permissions** → **Install to Workspace**
   - **Copy the `xoxb-...` token** → this is your `SLACK_BOT_TOKEN`

## Option B: Manual Setup

If you prefer to configure step-by-step instead of using the manifest:

1. **Create App**: https://api.slack.com/apps → **Create New App** → **From scratch**
2. **Socket Mode**: Left sidebar → enable Socket Mode, generate an app-level token with `connections:write` scope
3. **Bot Scopes**: Left sidebar → **OAuth & Permissions** → add all scopes listed in `templates/slack-app-manifest.json`
4. **Install**: Click **Install to Workspace**, copy the bot token
5. **Events**: Left sidebar → **Event Subscriptions** → enable, add all bot events from the manifest
6. **App Home**: Left sidebar → **App Home** → enable Messages Tab, allow users to send messages

## Add Tokens to .env

```bash
SLACK_APP_TOKEN="xapp-1-..."
SLACK_BOT_TOKEN="xoxb-..."
# Optional: restrict to a single channel
# SLACK_CHANNEL_ID="C0123456789"
```

## Invite Bot to Channels

The bot won't see messages in channels it hasn't been added to:

```
/invite @YourBotName
```

## Get a Channel ID

1. Right-click the channel name in Slack
2. Click **View channel details**
3. Scroll to the bottom — the Channel ID is there
