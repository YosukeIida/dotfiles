# Claude Code マルチアカウント設定

複数の Claude アカウントを使いながら、**会話履歴・skills・設定は一箇所に集約**するための設定。
切り替えコマンド（`cc`）とセットアップスクリプトの本体は [tools/agent-switch/](../tools/agent-switch/README.md) にある。ここでは Claude 固有の事情だけをまとめる。

## 設計の考え方

### 認証は macOS Keychain（Codex との最大の違い）

Claude Code の OAuth トークンは `CLAUDE_CONFIG_DIR` ごとの **Keychain エントリ**に保存される（実測記録は [tools/agent-switch/README.md](../tools/agent-switch/README.md) の検証記録参照）。

- `cc <name>` によるシェル切替 = 本物の認証分離。アカウント dir ごとに初回 `/login` が必要。
- トークンがファイルではないため、Codex の `cx app` に相当する「App/拡張の認証 symlink 差替」は**実装不可能**。Desktop App / VS Code 拡張（`CLAUDE_CONFIG_DIR` を無視する）は常に**デフォルトアカウント**（`CLAUDE_CONFIG_DIR` 未設定で login したアカウント = labteam）で動く。

### ディレクトリ構成

```
~/.claude/               デフォルトアカウント (labteam) の実体 + 共有ストア
  （projects, skills, plans, history.jsonl, CLAUDE.md, settings.*.json, ...）
~/.claude.json           デフォルトアカウントの identity（ホーム直下が実体）
~/.claude-personal/      名前制アカウント
  .claude.json 等        実体（アカウント固有）
  projects, skills, plans, history.jsonl, CLAUDE.md → ~/.claude/* へ symlink
  settings.*.json, get_key.sh, statusline.sh → dotfiles/claude/* へ symlink
```

- デフォルトアカウント（labteam）は `unset CLAUDE_CONFIG_DIR` に対応。`~/.claude-labteam` という dir は**作らない**（`CLAUDE_CONFIG_DIR=~/.claude` を export すると Keychain エントリが別になるため、unset が唯一の正解）。
- 旧番号制の `~/.claude-2` は廃止（`cc 2` は警告付きで personal に読み替える shim あり）。

## セットアップ

```bash
# 2つ目以降のアカウント（AGSW_CLAUDE_ASSETS_DIR は zshenv で設定済み）
bash ~/workspace/github.com/YosukeIida/dotfiles/tools/agent-switch/bin/setup-claude-account personal
CLAUDE_CONFIG_DIR=~/.claude-personal claude   # 起動後 /login
```

## 日常の使い方

```bash
cc              # 現在状態表示
cc personal     # このターミナルを personal に（他ターミナルに影響しない）
cc labteam      # デフォルトに戻す（App/拡張と同じ認証）
cc api          # API key モード
cc personal sub # アカウント + モード同時切替
```

### レート制限が来たら

```bash
cc personal && claude
```

`~/.claude/projects/` を共有しているため、どのアカウントから起動しても会話履歴は同じ。

## ファイル

| ファイル | 役割 |
|---|---|
| `settings.json` | live 設定（plugin install 等の書き込みが symlink 経由でここに反映される。**必ず git commit**） |
| `settings.api.json` | API key モード用 settings（⚠ live 設定からドリフト中 — 別タスクで解消予定） |
| `settings.subscription.json` | サブスクモード用 settings（同上） |
| `get_key.sh` | API key 取得ヘルパー（`$CLAUDE_CONFIG_DIR/anthropic.env` を読む） |
| `statusline.sh` | ステータスライン表示スクリプト |

---

Codex のマルチアカウント設定は [../codex/README.md](../codex/README.md) を参照（認証がファイルベースなため設計が異なる）。
