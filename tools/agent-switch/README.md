# agent-switch

Claude Code と OpenAI Codex のマルチアカウントを、**再ログインなし**でシェル1コマンドで切り替える zsh プラグイン。

- `cc` — Claude Code のアカウント（`CLAUDE_CONFIG_DIR`）と sub/api モード切替
- `cx` — Codex のアカウント（`CODEX_HOME`）と Desktop App 用認証の切替

> 現在は [YosukeIida/dotfiles](https://github.com/YosukeIida/dotfiles) の `tools/agent-switch/` として開発中。API が安定したら独立リポジトリに切り出す予定（このディレクトリは自己完結しており、そのまま切り出せる構造を保っている）。

## 設計思想

**認証だけをアカウントごとに分離し、会話履歴・skills・設定は共有する。**

- 各ツールの標準ホーム（`~/.claude`, `~/.codex`）が実体を持ち続け、アカウントディレクトリ（`~/.codex-<name>` 等）は認証ファイルだけ実体を持ち、他は標準ホームへの symlink。
- ターミナルごとの切替は環境変数（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`）の export のみ。ターミナル間は独立。
- GUI アプリ（Codex Desktop App 等、環境変数を継承しないプロセス）向けには、標準ホーム側の認証ファイルを symlink 差替で切り替える（`cx app <name>`）。
- Codex の `auth.json` はトークンリフレッシュ時に symlink をフォローして in-place 書き込みされるため（codex-rs ソースで確認済み）、symlink 共有はリフレッシュで壊れない。

## インストール

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/YosukeIida/dotfiles ~/.agent-switch
git -C ~/.agent-switch sparse-checkout set tools/agent-switch
echo 'source ~/.agent-switch/tools/agent-switch/agent-switch.plugin.zsh' >> ~/.zshrc
```

プラグインは source 時に**関数を定義するだけ**で副作用はない。デフォルトアカウントを固定したい場合は、自分の zshenv / zshrc に存在ガード付きで書く：

```zsh
# 例: 新しいシェルは常に work アカウントで開始
[[ -d "$HOME/.codex-work" ]] && export CODEX_HOME="${CODEX_HOME:-$HOME/.codex-work}"
```

### 設定変数（source 前に定義、すべて任意）

| 変数 | 既定値 | 用途 |
|---|---|---|
| `AGSW_CLAUDE_HOME_PREFIX` | `$HOME/.claude-` | Claude アカウント dir の接頭辞 |
| `AGSW_CODEX_HOME_PREFIX` | `$HOME/.codex-` | Codex アカウント dir の接頭辞 |
| `AGSW_CODEX_APP_AUTH` | `$HOME/.codex/auth.json` | Codex App が見る認証 symlink の場所 |
| `AGSW_CLAUDE_ASSETS_DIR` | （なし） | setup-claude-account が settings.*.json 等を直リンクする元 |

## セットアップ（アカウントディレクトリの作成）

### Codex

```bash
# 初回: 既存 ~/.codex の auth.json だけを分離（sessions等は動かさない・即時完了）
./bin/setup-codex-account migrate work

# 2アカウント目
./bin/setup-codex-account personal
CODEX_HOME="$HOME/.codex-personal" codex login
```

### Claude Code

```bash
./bin/setup-claude-account 2
CLAUDE_CONFIG_DIR="$HOME/.claude-2" claude   # 起動後 /login
```

## 日常の使い方

```bash
cx                # 状態表示（shell / App / 起動中デーモンのアカウント）
cx work           # このターミナルを work に切替
cx app personal   # Codex App 用の認証を personal に切替（App再起動で反映）

cc                # 状態表示
cc 2              # アカウント2に切替
cc api            # API keyモードに切替
cc sub 2          # アカウント2 + subscriptionモード
```

### Codex の注意: app-server デーモンの認証キャッシュ

`codex app-server` デーモンは起動時の認証をメモリにキャッシュし、TUI が `CODEX_HOME` をまたいで Remote 接続することがある。`cx` は起動中デーモンとそのアカウントを一覧表示し、現在のシェルと異なる場合に警告する。確実に切り替えるには：

```bash
pkill -f 'codex app-server'
```

## 動作要件

- zsh（bash/fish は未対応。独立リポジトリ化の際に eval-init 方式への移行を検討）
- デーモン警告と email/org 表示は macOS + python3 前提（無い環境では自動スキップ）

## ファイル構成

```
agent-switch.plugin.zsh   # エントリポイント（関数定義のみ）
lib/claude.zsh            # cc / _cc_status
lib/codex.zsh             # cx / _cx_status
bin/setup-claude-account  # Claude アカウント dir 作成
bin/setup-codex-account   # Codex アカウント dir 作成（migrate / add）
```
