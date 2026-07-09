# agent-switch

Claude Code と OpenAI Codex のマルチアカウントを、**再ログインなし**でシェル1コマンドで切り替える zsh プラグイン。

- `cc` — Claude Code のアカウント（`CLAUDE_CONFIG_DIR`）と sub/api モード切替
- `cx` — Codex のアカウント（`CODEX_HOME`）と Desktop App 用認証の切替

> 現在は [YosukeIida/dotfiles](https://github.com/YosukeIida/dotfiles) の `tools/agent-switch/` として開発中。API が安定したら独立リポジトリに切り出す予定（このディレクトリは自己完結しており、そのまま切り出せる構造を保っている）。

## 設計思想

**認証だけをアカウントごとに分離し、会話履歴・skills・設定は共有する。**

- 各ツールの標準ホーム（`~/.claude`, `~/.codex`）が実体を持ち続け、アカウントディレクトリ（`~/.codex-<name>` 等）は認証・アカウント固有ファイルだけ実体を持ち、他は標準ホームへの symlink。
- ターミナルごとの切替は環境変数（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`）の export のみ。ターミナル間は独立。
- GUI アプリ（Codex Desktop App 等、環境変数を継承しないプロセス）向けには、標準ホーム側の認証ファイルを symlink 差替で切り替える（`cx app <name>`）。
- Codex の `auth.json` はトークンリフレッシュ時に symlink をフォローして in-place 書き込みされるため（codex-rs ソースで確認済み）、symlink 共有はリフレッシュで壊れない。

### Claude と Codex の非対称（重要）

Claude Code の OAuth トークンはファイルではなく **macOS Keychain に `CLAUDE_CONFIG_DIR` ごとのエントリ**で保存される。このため：

- `cc <name>` のシェル切替 = 本物の認証分離（各アカウント dir で一度 `/login` が必要）。
- **`cc app` に相当する機能は存在しない**。トークンが symlink 差替できるファイルではないため、Desktop App / VS Code 拡張（`CLAUDE_CONFIG_DIR` を無視して常にデフォルトを見る）は、常に「`CLAUDE_CONFIG_DIR` 未設定で `/login` したアカウント」で動く。
- デフォルトアカウント（既定名 `labteam`、`AGSW_CLAUDE_DEFAULT_NAME` で変更可）は `unset CLAUDE_CONFIG_DIR` に対応する。`export CLAUDE_CONFIG_DIR=~/.claude` にすると Keychain エントリがデフォルトと別になってしまうため、必ず unset を使う（cc が面倒を見る）。

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

デフォルトアカウント（labteam）は `~/.claude` をそのまま使うためセットアップ不要。2つ目以降：

```bash
./bin/setup-claude-account personal
CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude   # 起動後 /login
```

## 日常の使い方

```bash
cx                # 状態表示（shell / App / 起動中デーモンのアカウント）
cx work           # このターミナルを work に切替
cx app personal   # Codex App 用の認証を personal に切替（App再起動で反映）

cc                # 状態表示
cc personal       # このターミナルを personal に切替
cc labteam        # デフォルトに戻す（= unset。App/拡張と同じ認証）
cc api            # API keyモードに切替
cc personal sub   # personal + subscriptionモード
```

### Codex の注意: app-server の control socket は CODEX_HOME ごとに分離される

`codex doctor --json` で確認できる通り、managed daemon の control socket / state dir（`$CODEX_HOME/app-server-control/`, `$CODEX_HOME/app-server-daemon/`）は `$CODEX_HOME` ごとに別物であり、他のツール・プロジェクトが起動した無関係な `codex app-server` プロセス（例: agmsg が別プロジェクト用に起動したもの、Codex Desktop App 自身のプロセス）が動いていても現在のシェルのアカウント切替には影響しない（2026-07-09 実測: `cx` での切替 → `codex` TUI 起動 → `/status` でアカウントが毎回正しく一致することを確認）。

以前 `cx` は `pgrep -f 'codex app-server'` でシステム上の全プロセスを走査し、CODEX_HOME が異なれば警告していたが、これは上記の理由で無関係なプロセスまで拾う誤検知だったため削除した。`cx` は現在、自分の `$CODEX_HOME` に紐づく managed daemon の pid file だけを見る。

## 動作要件

- zsh（bash/fish は未対応。独立リポジトリ化の際に eval-init 方式への移行を検討）
- デーモン警告と email/org 表示は macOS + python3 前提（無い環境では自動スキップ）

## 検証記録（2026-07-02 実測）

設計の根拠となった実測。将来のバージョンで挙動が変わった場合はここを更新する。

1. **Claude の Keychain は dir 単位分離**: 認証情報を持たないテスト用 `CLAUDE_CONFIG_DIR` で `claude -p` を実行 → `Not logged in`（デフォルトの Keychain エントリは流用されない）。Keychain には `Claude Code-credentials`（デフォルト用）のエントリを確認。
2. **Claude の identity ファイルの所在**: `CLAUDE_CONFIG_DIR` 未設定時は `~/.claude.json`（ホーム直下）が実体（mtime 実測）。`~/.claude/.claude.json` は更新されない旧位置。設定時は `$CLAUDE_CONFIG_DIR/.claude.json`。
3. **Codex の auth.json 書き込み**: `codex-rs/login/src/auth/storage.rs` の `FileAuthStorage::save()` は truncate+in-place 書き込みで symlink をフォローする。config.toml 書き込みは `resolve_symlink_write_paths` で symlink 解決後に atomic write（symlink は壊れない）。

## ファイル構成

```
agent-switch.plugin.zsh   # エントリポイント（関数定義のみ）
lib/claude.zsh            # cc / _cc_status
lib/codex.zsh             # cx / _cx_status
bin/setup-claude-account  # Claude アカウント dir 作成
bin/setup-codex-account   # Codex アカウント dir 作成（migrate / add）
```
