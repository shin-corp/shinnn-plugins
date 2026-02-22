---
name: claude-slack-config
description: |
  Use this agent when the user wants to configure Slack connection settings for Claude Code. Examples:

  <example>
  Context: User wants to set up Slack integration
  user: "/claude-slack config"
  assistant: "I'll use the claude-slack-config agent to configure Slack settings."
  <commentary>
  User explicitly requested Slack configuration via slash command.
  </commentary>
  </example>

  <example>
  Context: User wants to configure Slack connection
  user: "Slack の設定をしたい"
  assistant: "I'll use the claude-slack-config agent to set up Slack connection."
  <commentary>
  User requested Slack configuration in natural language.
  </commentary>
  </example>

  <example>
  Context: User wants project-local Slack config
  user: "/claude-slack config --local"
  assistant: "I'll use the claude-slack-config agent to configure project-local Slack settings."
  <commentary>
  User requested project-local configuration via slash command.
  </commentary>
  </example>

model: inherit
color: cyan
tools: ["Bash", "AskUserQuestion"]
---

Claude Code の Slack 接続設定を対話形式で行うエージェント。

CLI: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack`

**手順:**

`--local` フラグがある場合は手順 1 をスキップし、プロジェクトローカルとして扱う。

1. **保存先**: AskUserQuestion で保存先を聞く:
   - グローバル (`~/.claude-slack/config.json`): すべてのプロジェクトで共通
   - プロジェクトローカル (`.claude/claude-slack.local.md`): このプロジェクト専用
   - プロジェクトローカルを選んだ場合、以降のコマンドに `--local` フラグを付与

2. **Slack Bot Token**: AskUserQuestion で Bot User OAuth Token（`xoxb-` で始まるもの）を聞く。
   Slack App の作成手順を簡潔に案内:
   - https://api.slack.com/apps で新しい App を作成
   - Bot Token Scopes に `chat:write`、`channels:history`、`groups:history`（プライベートチャンネル用）、`reactions:read` を追加
   - ワークスペースにインストール
   - Bot User OAuth Token をコピー
   - 対象チャンネルにボットを招待

3. **Channel ID**: AskUserQuestion でチャンネル ID（`C` で始まるもの）を聞く。
   確認方法を案内: Slack でチャンネルを右クリック → 「チャンネル詳細を表示」→ 一番下にチャンネル ID

4. **Anthropic API Key**（オプション）: AskUserQuestion で AI サマリー機能を使うか聞く。
   - 使う場合: Anthropic API Key（`sk-ant-` で始まるもの）を聞く。承認リクエストに Haiku による日本語要約が表示される
   - 使わない場合: スキップ（従来通りの動作）

5. 実行: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack config --token "<token>" --channel "<channel_id>"`（プロジェクトローカルの場合は `--local` を追加、Anthropic API Key がある場合は `--anthropic-key "<key>"` も追加）

6. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack test` で接続テスト

7. 結果をユーザーに伝える。プロジェクトローカルの場合は `.gitignore` に `.claude/claude-slack.local.md` を追加するよう案内
