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
| `settings.json` | live 設定＝サブスクモードの実体（plugin install 等の書き込みが symlink 経由でここに反映される。**必ず git commit**） |
| `api-mode-overlay.json` | API モードで live から意図的に変える差分だけを書く（apiKeyHelper、絞った enabledPlugins）。**API モードの設定変更はここを編集** |
| `settings.api.json` | **生成物・git管理外**（`gen-api-settings.sh` が live + overlay から darwin-switch 時に生成）。手で編集しない |
| `gen-api-settings.sh` | settings.api.json の生成スクリプト（overlay のトップレベルキーで live を置換） |
| `get_key.sh` | API key 取得ヘルパー（`$CLAUDE_CONFIG_DIR/anthropic.env` を読む） |
| `statusline.sh` | ステータスライン表示スクリプト |
| `git-filters/strip-model-clean.py` | git clean filter 本体（`model` キーを除去） |

> モード切替の仕組み: `cc api` は `settings.json` symlink を `settings.api.json`（生成物）へ、
> `cc sub` は live の `settings.json` へ差し替える。サブスク専用ファイルは存在しない。
> enabledPlugins はスコープ間で加算マージしかできない（上位で false 無効化は不可）ため、
> plugin を絞る API モードは「ファイル差し替え」方式が唯一の実現手段。
> ドリフトは生成方式により恒久解消（2026-07-06）。

> `model` キーは git 管理から除外している: `/model` コマンドで頻繁にローカル書き換えされ、
> commit するたびに無関係な diff が出るため。`.gitattributes`（`filter=strip-model`）+
> `git-filters/strip-model-clean.py` の clean filter で、worktree の実ファイルには実際の値を
> 残したまま、git 上（diff/status/commit）では常に `model` キーが無い状態に正規化する。
> filter の登録自体（`git config filter.strip-model.*`）は clone ごとに必要なローカル設定
> なので darwin-switch の postActivation で自動セットアップする（2026-07-07）。

---

Codex のマルチアカウント設定は [../codex/README.md](../codex/README.md) を参照（認証がファイルベースなため設計が異なる）。
