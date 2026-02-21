[English](README.md) | [日本語](README.ja.md)

# claude-slack

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) の承認リクエスト・質問・通知を Slack に転送します。

依存パッケージなし。単一ファイル。Claude Code プラグイン。

## 仕組み

Claude Code がツール実行の承認や質問を必要とするとき、ターミナルで待機する代わりに Slack チャンネルにメッセージを投稿します。スレッドで返信すると、Claude Code がそのまま続行します。

3種類のフックに対応しています:

- **PermissionRequest** — ツール実行の承認（絵文字リアクションまたはスレッドで approve / deny を返信）
- **AskUserQuestion** — Claude からの質問（番号またはテキストで回答）
- **Notification** — アイドル通知（投げっぱなし）

## 前提条件

- Node.js >= 18
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Slack ワークスペースと Bot アプリ

### Slack アプリの準備

1. [api.slack.com/apps](https://api.slack.com/apps) で新しいアプリを作成
2. **OAuth & Permissions** で以下の Bot Token Scopes を追加:
   - `chat:write` — メッセージ投稿
   - `reactions:read` — 承認用の絵文字リアクションの読み取り
   - `channels:history` — スレッド返信の読み取り（パブリックチャンネル）
   - `groups:history` — スレッド返信の読み取り（プライベートチャンネル）
3. ワークスペースにアプリをインストール
4. **Bot User OAuth Token**（`xoxb-...`）をコピー
5. チャンネルに Bot を招待（`/invite @ボット名`）
6. **チャンネル ID** をコピー（チャンネル名を右クリック → チャンネル詳細を表示）

## インストール

```
# 1. マーケットプレイスを追加
/plugin marketplace add shin-corp/claude-code-plugins

# 2. プラグインをインストール
/plugin install claude-slack@claude-code-plugins
```

インストール後、Claude Code を再起動してください。

## クイックスタート

```
# 1. Slack の認証情報を設定（対話形式）
/claude-slack config

# 2. 有効化
/claude-slack on
```

CLI で直接設定する場合:

```sh
node <plugin-path>/bin/claude-slack config --token xoxb-your-token --channel C0123456789
node <plugin-path>/bin/claude-slack enable
```

## スラッシュコマンド

| コマンド | 説明 |
|---------|------|
| `/claude-slack on` | Slack 転送を有効化 |
| `/claude-slack off` | Slack 転送を無効化 |
| `/claude-slack config` | Slack 接続設定（グローバル） |
| `/claude-slack config --local` | このプロジェクト用に設定 |
| `/claude-slack status` | 現在の設定とソースを表示 |

## 設定の優先順位

設定は以下の優先順位で解決されます（上が最優先）:

| 優先度 | ソース | 場所 |
|--------|--------|------|
| 1（最高） | 環境変数 | `CLAUDE_SLACK_TOKEN`, `CLAUDE_SLACK_CHANNEL` 等 |
| 2 | プロジェクトローカル | `.claude/claude-slack.local.md` |
| 3（最低） | グローバル | `~/.claude-slack/config.json` |

### プロジェクト別設定

`--local` で現在のプロジェクト専用の設定を保存:

```
/claude-slack config --local
```

`.claude/claude-slack.local.md` が作成されます:

```markdown
---
slack_bot_token: xoxb-...
channel_id: C0123456789
timeout: 300
enabled: true
---
```

シークレットを含む場合は `.gitignore` に追加してください:

```
.claude/claude-slack.local.md
```

### AI サマリー（オプション）

Anthropic API キーを設定すると、Slack の承認リクエストに Haiku による一行要約が 💡 で表示されます。

```
/claude-slack config --anthropic-key sk-ant-...
```

設定すると、ツール詳細の上に Claude が何をしようとしているかの要約が表示され、一目で判断しやすくなります。未設定の場合は従来通りの動作です。

### 環境変数

| 変数 | 説明 |
|------|------|
| `CLAUDE_SLACK_TOKEN` | Slack Bot User OAuth Token |
| `CLAUDE_SLACK_CHANNEL` | Slack チャンネル ID |
| `CLAUDE_SLACK_TIMEOUT` | 返信タイムアウト（秒、デフォルト: 300） |
| `CLAUDE_SLACK_ENABLED` | 有効/無効（`true`/`false`） |
| `ANTHROPIC_API_KEY` | AI サマリー用 Anthropic API キー（オプション） |

## CLI コマンド

| コマンド | 説明 |
|---------|------|
| `config [--local] --token <xoxb-...> --channel <C...>` | 設定を保存 |
| `test` | Slack 接続テスト |
| `enable [--local]` | Slack 転送を有効化 |
| `disable [--local]` | Slack 転送を無効化 |
| `status` | 現在の設定とソースを表示 |

## アンインストール

```sh
claude plugin remove claude-slack
```

`~/.claude-slack/` のグローバル設定は保持されます。完全に削除するには:

```sh
rm -rf ~/.claude-slack
```

## デバッグ

デバッグログ: `~/.claude-slack/debug.log`

## テスト

```sh
# 安全なテスト（Slack への投稿なし）
bash test/test-hooks.sh 2 3 5 6 7 8 9 10 11 12 13

# Slack 投稿を含む全テスト
bash test/test-hooks.sh
```

## ライセンス

[MIT](LICENSE)
