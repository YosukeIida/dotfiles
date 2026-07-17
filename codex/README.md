# Codex CLI/App マルチアカウント設定

複数のCodexアカウント（例: labteam / personal）を使いながら、**会話履歴・記憶は一箇所に集約**するための設定。[claude/README.md](../claude/README.md)のClaude Code版と同じ発想だが、Codex特有の事情により設計が異なる。

## Claude Codeと異なる理由

Claude Codeは `CLAUDE_CONFIG_DIR` を切り替えるだけで完結する（CLIのみで、GUIアプリが関与しない）。Codexには次の制約がある。

1. **Codex Desktop App / IDE拡張はシェルの`CODEX_HOME`を継承しない**。Finder/Dockから起動するため、ターミナルで`export CODEX_HOME=...`してもAppには反映されない（OpenAI公式ドキュメントで明言されている: "if you set a custom CODEX_HOME in one terminal but not in the App, they will use different auth caches"）。
   → そのためCLIは`CODEX_HOME`で切り替えつつ、App用に`~/.codex/auth.json`を**symlinkで**差し替える、というハイブリッド方式を採る。

2. **`auth.json`はcopyではなくsymlinkにする**。`codex-rs/login/src/auth/storage.rs`の`FileAuthStorage::save()`は`OpenOptions::new().truncate(true).write(true).create(true).open(auth_file)`でsymlinkをフォローするin-place書き込みを行う（tempfile+renameのatomic差し替えではない）。よってsymlinkにしてもトークンリフレッシュ時にリンクは壊れず、リンク先の実体ファイルが常に最新化される。copy方式だと、CLI/Appどちらかがリフレッシュした際にコピー元とコピー先がズレて古い方が失効するリスクがある。

3. **`~/.codex`自体が「共有ストア」を兼ねる**。専用の共有ディレクトリは作らない。`~/.codex`は今まで通りsessions/history.jsonl/skills/AGENTS.md/config.toml等の実体を持ち続け、各`~/.codex-<name>/`はそれらへのsymlinkを持つだけ（実体はコピーも移動もしない）。実際に必要な実体move は`auth.json`一つだけ。

4. **`config.toml`も共有symlinkにする**。Codexのconfig書き込み（trust承認・plugin登録等）は`resolve_symlink_write_paths`（`codex-rs/utils/path-utils/src/lib.rs`）が**symlinkを終端まで解決してから実体にatomic writeする**設計のため、symlinkは壊れない（ソース確認済み）。これによりproject trustの承認が全アカウントで一度で済む。
   注意点: `service_tier = "priority"`のような**プラン固有の設定**も共有されるため、Plus側のアカウントで問題が出たらその行を調整する。また複数アカウントのデーモンが同時にconfigを書くと、まれに片方の編集（trust追加等）が失われうるが、実害は再承認程度。

## ディレクトリ構成

```
~/.codex/                      実体（今まで通り。App/IDE拡張が常に見るデフォルト）
  auth.json                    symlink → ~/.codex-<active>/auth.json（cxコマンドでln -sf差替）
  config.toml, AGENTS.md, skills/, sessions/, history.jsonl, ...  実体（そのまま）

~/.codex-labteam/               薄いディレクトリ
  auth.json                    実体（labteamの認証。移行時に~/.codex/auth.jsonをmvしたもの）
  config.toml, skills, AGENTS.md, sessions, history.jsonl, ...  → ~/.codex/* へのsymlink

~/.codex-personal/               同上構造（auth.jsonは新規ログイン）
```

## Keyring future-proofing

Codexの認証保存方式（`AuthCredentialsStoreMode`）は現在デフォルト`File`だが、将来`Keyring`/`Auto`がデフォルトになった場合、`compute_store_key()`が`CODEX_HOME`の実パスをSHA256ハッシュ化してKeychainキーにするため、ディレクトリごとに別々のKeychainエントリになり、上記のsymlink方式が機能しなくなる。

[codex/config.toml](config.toml)に`cli_auth_credentials_store = "file"`を明記することでFileモードを固定し、将来のデフォルト変更の影響を受けないようにしている（`/etc/codex/config.toml`経由でsystem layerとして全`CODEX_HOME`に適用される）。[migrate-user-config.sh](migrate-user-config.sh)はuser layer側にこのキーの古い値が紛れ込んでpinを無効化しないよう除去する。

## セットアップ手順

### 1. 初回移行（既存 `~/.codex` の auth.json だけ分離）

```bash
bash ~/workspace/github.com/YosukeIida/dotfiles/tools/agent-switch/bin/setup-codex-account migrate labteam
```

`~/.codex/auth.json`を`~/.codex-labteam/auth.json`にmvし、symlinkを張り直すだけ。sessions/history等は一切動かさないので、データ量に関係なく即時完了する。

### 2. 2アカウント目の追加

```bash
bash ~/workspace/github.com/YosukeIida/dotfiles/tools/agent-switch/bin/setup-codex-account personal
CODEX_HOME="$HOME/.codex-personal" codex login
```

## 日常の使い方

**ターミナルとAppで切り替えを分離**している。ターミナルはzshrcで`CODEX_HOME`がデフォルト`~/.codex-labteam`に固定され、`cx <name>`は**そのシェルだけ**を切り替える（symlinkを触らないので他のターミナルに影響しない）。`~/.codex`（`CODEX_HOME`未設定のプロセス＝Dockから起動したApp・launchd系が見る場所）は`cx app <name>`で切り替える。

```bash
cx                # 現在状態表示（shell / App / 起動中デーモンとそのアカウント）
cx labteam        # このターミナルをlabteamに切替
cx personal       # このターミナルをpersonalに切替
cx app personal   # Codex App用（~/.codex/auth.json symlink）をpersonalに切替
```

- 新しいターミナルは常にデフォルト（labteam）で始まる。
- ターミナルから`codex app`でAppを起動した場合はシェルの`CODEX_HOME`を継承する（Dock起動とは異なる）。
- App側は再起動すると切り替えたアカウントが反映される。

### 注意: app-serverデーモンのauthキャッシュ

`codex app-server`デーモン（Desktop App・TUI・agmsg bridge等が起動する）は、**起動時点のauth/configをメモリにキャッシュする**。さらにデーモンの発見は`CODEX_HOME`をまたいで行われるため（実際に`CODEX_HOME=~/.codex-labteam`のTUIが`~/.codex`起点のデーモンにRemote接続する事象を確認済み）、切り替えた後でも新しいTUIセッションが**古いアカウントをキャッシュしたデーモン**に接続することがある。`/status`の`Remote: ws://127.0.0.1:...`行で接続先を確認できる。

`cx`は起動中のデーモンとその`CODEX_HOME`を一覧表示し、現在のシェルと実体authが異なるデーモンがあれば警告する。切り替えを確実にするには:

```bash
pkill -f 'codex app-server'
```

その後にTUI/Appを起動し直すと、現在の`auth.json`が読み込まれる。

### レート制限が来たら

```bash
cx personal && codex
```

`~/.codex/*`を全アカウントがsymlinkで参照するため、どのアカウントから使っても履歴は統一される。

## ファイル

| ファイル | 役割 |
|---|---|
| [tools/agent-switch/bin/setup-codex-account](../tools/agent-switch/bin/setup-codex-account) | 初回移行 + アカウント追加（cc/cx本体は [tools/agent-switch/](../tools/agent-switch/README.md)） |
| `config.toml` | system layer（`/etc/codex/config.toml`）の安定設定（dotfiles管理） |
| `migrate-user-config.sh` | user layerに紛れ込んだ管理対象キーを除去する冪等スクリプト |
| `install-plugins.sh` / `marketplaces.txt` / `plugins.txt` | Codexプラグインの冪等インストール（サードパーティmarketplaceの登録＋plugin導入） |
