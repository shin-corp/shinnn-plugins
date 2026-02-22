---
name: claude-slack-on
description: |
  Use this agent when the user wants to enable Slack routing for Claude Code permission requests and questions. Examples:

  <example>
  Context: User wants to start receiving Claude Code notifications via Slack
  user: "/claude-slack on"
  assistant: "I'll use the claude-slack-on agent to enable Slack routing."
  <commentary>
  User explicitly requested enabling Slack routing via slash command.
  </commentary>
  </example>

  <example>
  Context: User wants Slack integration active
  user: "Slack routing を有効にして"
  assistant: "I'll use the claude-slack-on agent to enable Slack routing."
  <commentary>
  User requested enabling Slack routing in natural language.
  </commentary>
  </example>

model: inherit
color: green
tools: ["Bash"]
---

Claude Code の Slack routing を有効化するエージェント。

CLI: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack`

**手順:**

1. `~/.claude-slack/config.json` または `.claude/claude-slack.local.md` が存在するか確認（`test -f`）
2. どちらも存在しない場合: 「先に `/claude-slack config` で Slack 接続を設定してください」と案内して終了
3. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack enable` を実行
4. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack test` で接続テスト
5. 成功: 「Slack routing を有効化しました。承認や質問は Slack に送信されます。」と伝える
6. 失敗: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack disable` で元に戻し、`/claude-slack config` で設定を確認するよう案内
