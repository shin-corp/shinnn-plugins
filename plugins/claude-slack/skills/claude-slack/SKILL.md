---
description: "Claude Code の承認・質問・通知を Slack 経由で処理する"
argument-hint: "[on|off|config|status]"
allowed-tools: Bash(node *), Bash(test *)
---

# claude-slack

引数: $ARGUMENTS

CLI: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack`

## 処理ルール

### 引数なし

使い方を表示:
```
/claude-slack on     - Slack routing を有効化
/claude-slack off    - Slack routing を無効化
/claude-slack config - Slack 接続設定
/claude-slack status - 現在の状態を表示
```

### `on`

1. `~/.claude-slack/config.json` または `.claude/claude-slack.local.md` が存在するか確認（`test -f`）
2. 存在しない場合: 「先に `/claude-slack config` で Slack 接続を設定してください」と案内
3. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack enable` を実行
4. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack test` で接続テスト
5. 成功: 「Slack routing を有効化しました。承認や質問は Slack に送信されます。」
6. 失敗: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack disable` に戻して、設定の確認を案内

### `off`

1. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack disable` を実行
2. 「Slack routing を無効化しました。」

### `config`

ユーザーに対話形式で設定を聞く:

1. **保存先**: グローバル（ユーザー全体）かプロジェクトローカルかを聞く
   - グローバル: `~/.claude-slack/config.json` に保存。すべてのプロジェクトで共通
   - プロジェクト: `.claude/claude-slack.local.md` に保存。このプロジェクト専用
   - プロジェクトを選んだ場合、以降の手順で `--local` フラグを付与する

2. **Slack Bot Token**: xoxb- で始まる Bot User OAuth Token を聞く
   - Slack App の作成手順を簡潔に案内:
     - https://api.slack.com/apps で新しい App を作成
     - Bot Token Scopes に `chat:write`、`channels:history`、`groups:history`（プライベートチャンネル用）、`reactions:read` を追加
     - ワークスペースにインストール
     - Bot User OAuth Token をコピー
     - 対象チャンネルにボットを招待

3. **Channel ID**: C で始まるチャンネル ID を聞く
   - 確認方法を案内: チャンネルを右クリック → チャンネル詳細を表示 → 一番下にチャンネル ID

4. **Anthropic API Key**（オプション）: AI サマリー機能を使うか聞く
   - 使う場合: sk-ant- で始まる Anthropic API Key を聞く
   - 承認リクエストに Haiku による日本語要約が 💡 で表示される
   - 使わない場合: スキップ（従来通りの動作）

5. 実行: `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack config --token "<token>" --channel "<channel_id>"` （プロジェクトローカルの場合は `--local` を追加、Anthropic API Key がある場合は `--anthropic-key "<key>"` も追加）

6. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack test` で接続テスト

7. 結果をユーザーに伝える。プロジェクトローカルの場合は `.gitignore` に `.claude/claude-slack.local.md` を追加するよう案内する

### `config --local`

`config` と同じ手順だが、保存先の質問（手順1）をスキップし、プロジェクトローカルとして扱う。

### `status`

1. `node ${CLAUDE_PLUGIN_ROOT}/bin/claude-slack status` を実行
2. 結果を表示
