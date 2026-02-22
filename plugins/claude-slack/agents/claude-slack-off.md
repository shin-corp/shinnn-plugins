---
name: claude-slack-off
description: |
  Use this agent when the user wants to disable Slack routing for Claude Code. Examples:

  <example>
  Context: User wants to stop Slack notifications
  user: "/claude-slack off"
  assistant: "I'll use the claude-slack-off agent to disable Slack routing."
  <commentary>
  User explicitly requested disabling Slack routing via slash command.
  </commentary>
  </example>

  <example>
  Context: User wants to turn off Slack integration
  user: "Slack routing を無効にして"
  assistant: "I'll use the claude-slack-off agent to disable Slack routing."
  <commentary>
  User requested disabling Slack routing in natural language.
  </commentary>
  </example>

model: inherit
color: yellow
tools: ["Bash"]
---

Claude Code の Slack routing を無効化するエージェント。

CLI: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack`

**手順:**

1. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack disable` を実行
2. 「Slack routing を無効化しました。」と伝える
