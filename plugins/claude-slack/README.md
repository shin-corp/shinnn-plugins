[English](README.md) | [日本語](README.ja.md)

# claude-slack

Route [Claude Code](https://docs.anthropic.com/en/docs/claude-code) permission requests, questions, and notifications to Slack.

Zero dependencies. Single file. Claude Code plugin.

## How it works

When Claude Code needs your approval or has a question, instead of waiting at the terminal, it posts a message to a Slack channel. You reply in a thread, and Claude Code continues.

Three hook types are supported:

- **PermissionRequest** — Tool execution approvals (approve/deny via emoji reaction or thread reply)
- **AskUserQuestion** — Questions from Claude (answer by number or text)
- **Notification** — Idle notifications (fire-and-forget)

## Prerequisites

- Node.js >= 18
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- A Slack workspace with a bot app

### Slack App Setup

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create a new app
2. Under **OAuth & Permissions**, add these Bot Token Scopes:
   - `chat:write` — Post messages
   - `reactions:read` — Read emoji reactions for approvals
   - `channels:history` — Read thread replies (public channels)
   - `groups:history` — Read thread replies (private channels)
3. Install the app to your workspace
4. Copy the **Bot User OAuth Token** (`xoxb-...`)
5. Invite the bot to your channel (`/invite @your-bot-name`)
6. Copy the **Channel ID** (right-click channel name → View channel details)

## Install

```
# 1. Add the marketplace
/plugin marketplace add shin-corp/shinnn-plugins

# 2. Install the plugin
/plugin install claude-slack@shinnn-plugins
```

Restart Claude Code after installation.

## Quick Start

```
# 1. Configure Slack credentials (interactive)
/claude-slack config

# 2. Enable
/claude-slack on
```

Or configure via CLI directly:

```sh
node <plugin-path>/bin/claude-slack config --token xoxb-your-token --channel C0123456789
node <plugin-path>/bin/claude-slack enable
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/claude-slack on` | Enable Slack routing |
| `/claude-slack off` | Disable Slack routing |
| `/claude-slack config` | Configure Slack connection (global) |
| `/claude-slack config --local` | Configure for current project |
| `/claude-slack status` | Show current configuration and sources |

## Configuration Hierarchy

Settings are resolved in this priority order (highest wins):

| Priority | Source | Location |
|----------|--------|----------|
| 1 (highest) | Environment variables | `CLAUDE_SLACK_TOKEN`, `CLAUDE_SLACK_CHANNEL`, etc. |
| 2 | Project-local | `.claude/claude-slack.local.md` |
| 3 (lowest) | Global | `~/.claude-slack/config.json` |

### Per-Project Configuration

Use `--local` to save settings for the current project:

```
/claude-slack config --local
```

This creates `.claude/claude-slack.local.md`:

```markdown
---
slack_bot_token: xoxb-...
channel_id: C0123456789
timeout: 300
enabled: true
---
```

Add to your `.gitignore` if it contains secrets:

```
.claude/claude-slack.local.md
```

### AI Summary (Optional)

Add an Anthropic API key to get a one-line AI-generated summary (powered by Haiku) on each permission request in Slack.

```
/claude-slack config --anthropic-key sk-ant-...
```

When configured, a 💡 summary appears above the tool details, helping you understand what Claude is trying to do at a glance. Without a key, everything works as before.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_SLACK_TOKEN` | Slack Bot User OAuth Token |
| `CLAUDE_SLACK_CHANNEL` | Slack Channel ID |
| `CLAUDE_SLACK_TIMEOUT` | Reply timeout in seconds (default: 300) |
| `CLAUDE_SLACK_ENABLED` | Enable/disable (`true`/`false`) |
| `ANTHROPIC_API_KEY` | Anthropic API key for AI summary (optional) |

## CLI Commands

| Command | Description |
|---------|-------------|
| `config [--local] --token <xoxb-...> --channel <C...>` | Save configuration |
| `test` | Test Slack connection |
| `enable [--local]` | Enable Slack routing |
| `disable [--local]` | Disable Slack routing |
| `status` | Show current configuration with sources |

## Uninstall

```sh
claude plugin remove claude-slack
```

Global config in `~/.claude-slack/` is preserved. To fully remove:

```sh
rm -rf ~/.claude-slack
```

## Debug

Debug logs: `~/.claude-slack/debug.log`

## Testing

```sh
# Run safe tests (no Slack posting)
bash test/test-hooks.sh 2 3 5 6 7 8 9 10 11 12 13

# Run all tests including live Slack posts
bash test/test-hooks.sh
```

## License

[MIT](LICENSE)
