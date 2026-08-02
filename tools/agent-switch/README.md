# agent-switch

Claude Code と OpenAI Codex のマルチアカウントを、**再ログインなし**でシェル1コマンドで切り替える zsh プラグイン。

- `cc` — Claude Code のアカウント（`CLAUDE_CONFIG_DIR`）と sub/api モード切替
- `cx` — Codex のアカウント（`CODEX_HOME`）と Desktop App 用認証の切替

> 現在は [YosukeIida/dotfiles](https://github.com/YosukeIida/dotfiles) の `tools/agent-switch/` として開発中。API が安定したら独立リポジトリに切り出す予定（このディレクトリは自己完結しており、そのまま切り出せる構造を保っている）。

## 設計思想

**認証だけをアカウントごとに分離し、会話履歴・skills・設定は共有する。**

- 各ツールの標準ホーム（`~/.claude`, `~/.codex`）が実体を持ち続け、アカウントディレクトリ（`~/.codex-<name>` 等）は認証・アカウント固有ファイルだけ実体を持ち、他は標準ホームへの symlink。
- アカウントディレクトリには**プロファイル・マーカー `.agsw-profile`** を置く。`cc` / `cx` はマーカーの無いディレクトリを拒否し、setup スクリプトは既存の未管理ディレクトリの取り込みに `--claim` を要求する。prefix 方式（`~/.claude-<name>`）は agent-switch と無関係な既存ディレクトリに偶然合致しうるため（実例: `~/.claude-science` は Claude Science アプリのデータ）、ディレクトリの存在だけではプロファイルと見なさない。
- ターミナルごとの切替は環境変数（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`）の export のみ。ターミナル間は独立。
- GUI アプリ（Codex Desktop App 等、環境変数を継承しないプロセス）向けには、標準ホーム側の認証ファイルを symlink 差替で切り替える（`cx app <name>`）。
- Codex の `auth.json` はトークンリフレッシュ時に symlink をフォローして in-place 書き込みされるため（codex-rs ソースで確認済み）、symlink 共有はリフレッシュで壊れない。

### Claude と Codex の非対称（重要）

Claude Code の OAuth トークンはファイルではなく **macOS Keychain に `CLAUDE_CONFIG_DIR` ごとのエントリ**で保存される。このため：

- `cc <name>` のシェル切替 = 本物の認証分離（各アカウント dir で一度 `/login` が必要）。
- **`cc app` は未実装（実現可否は検証中）**。トークンが symlink 差替できるファイルではないため、`cx app` と同じ方法では作れない。現状 Desktop App / VS Code 拡張（`CLAUDE_CONFIG_DIR` を無視して常にデフォルトを見る）は、常に「`CLAUDE_CONFIG_DIR` 未設定で `/login` したアカウント」で動く。Keychain エントリの **move** による実装は原理的には可能（下記「`cc app` の検証」参照）。
- デフォルトアカウント（既定名 `labteam`、`AGSW_CLAUDE_DEFAULT_NAME` で変更可）は `unset CLAUDE_CONFIG_DIR` に対応する。`export CLAUDE_CONFIG_DIR=~/.claude` にすると Keychain エントリがデフォルトと別になってしまうため、必ず unset を使う（cc が面倒を見る）。

## インストール

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/YosukeIida/dotfiles ~/.agent-switch
git -C ~/.agent-switch sparse-checkout set tools/agent-switch
echo 'source ~/.agent-switch/tools/agent-switch/agent-switch.plugin.zsh' >> ~/.zshrc
```

プラグインは source 時に**関数を定義する**のが主な仕事で、ファイルを書き換える副作用は一切持たない。ただしインタラクティブシェルに限り、Codex の App 用 `auth.json`（共有 symlink）が「実ファイル化（事故）」または「リンク切れ」のときだけ軽量な警告チェックを表示する（正常時は lstat 数回で即抜ける・出力なし・修復はしない）。実際の修復はユーザーが `cx` を実行したときだけ行う（下記「Codex 認証ファイルの保護」参照）。

デフォルトアカウントを固定したい場合は、自分の zshenv / zshrc に存在ガード付きで書く。ガードは**ディレクトリの有無ではなくマーカー**で行うこと（`-d` だけだと prefix に偶然一致した未管理ディレクトリでも Codex が直接使えてしまい、`cx` 側のガードと食い違う）：

```zsh
# 例: 新しいシェルは常に work アカウントで開始
[[ -f "$HOME/.codex-work/.agsw-profile" ]] && export CODEX_HOME="${CODEX_HOME:-$HOME/.codex-work}"
```

### 設定変数（source 前に定義、すべて任意）

| 変数 | 既定値 | 用途 |
|---|---|---|
| `AGSW_CLAUDE_HOME_PREFIX` | `$HOME/.claude-` | Claude アカウント dir の接頭辞 |
| `AGSW_CODEX_HOME_PREFIX` | `$HOME/.codex-` | Codex アカウント dir の接頭辞 |
| `AGSW_CODEX_APP_AUTH` | `$HOME/.codex/auth.json` | Codex App が見る認証 symlink の場所 |
| `AGSW_CLAUDE_ASSETS_DIR` | （なし） | setup-claude-account が settings.*.json 等を直リンクする元 |
| `AGSW_CLAUDE_DEFAULT_NAME` | `labteam` | `cc` が「`CLAUDE_CONFIG_DIR` 未設定」として扱うアカウント名 |
| `AGSW_ALLOW_RAW_LOGIN` | （未設定） | `1` にすると `codex login`/`logout` の共有 symlink 保護ガードを無効化する |

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

### 既存プロファイルへのマーカー付与（移行）

`.agsw-profile` の導入前に作ったプロファイルは、setup スクリプトを `--claim` 付きで実行するとマーカーが付く。両スクリプトは収束型（`ln -sfn` で張り直し）なので、既存の認証・状態には触らない。

```bash
./bin/setup-claude-account personal --claim
./bin/setup-codex-account labteam --claim
./bin/setup-codex-account personal --claim
```

マーカーが付いた後は `--claim` 不要（再実行は "Normalized" として素通しになる）。

### 二重のガード

マーカーを付けていないディレクトリは `cc` / `cx` / `cc list` / `cx list` / 補完のすべてから除外される。`codex-auth-doctor` も列挙対象外とし、prefix に合致するがマーカーの無いディレクトリを見つけたときは案内にその旨を添える。

さらに **setup スクリプト側にもガードがある**。既存の「マーカー無し・空でない」ディレクトリに対しては、中身を一覧表示したうえで拒否し、明示の `--claim` を要求する。`cc` を塞いでも「マーカーを付ければ通る」迂回路が残ると、無関係な別アプリのデータディレクトリを取り込んでしまうため。

```console
$ ./bin/setup-claude-account science
Error: /Users/yosuke/.claude-science は既に存在し、agent-switch の管理下ではありません（.agsw-profile が無い）。
  中身:
    .oauth-tokens
    auth-owner.lock
    conda
    encryption.key
    ...
  別アプリのデータディレクトリでないことを確認してください。
```

> `--claim` は「既存の未管理ディレクトリをプロファイルとして取り込む」フラグ。`setup-codex-account adopt <name>`（実ファイル化した `auth.json` の取り込み）とは別の概念なので注意。

### プロファイル名の制約

setup スクリプトは名前を検査する（`bin/agsw-check-name`）。

- 先頭は英数字、以降は英数字・`.`・`_`・`-` のみ。**`/` と先頭 `.` は不可**
  名前は prefix と連結してディレクトリパスになるため、`../../victim` のような名前は prefix の外へ書き込める（2026-07-28 実測: `auth.json` が `$HOME/victim/` へ移動した）
- 予約語は不可。`cc` / `cx` がサブコマンドやモード語として消費するため、その名前のプロファイルには切り替えられない
  - Codex: `list` `app`
  - Claude: `list` `api` `sub` `subscription`、および `AGSW_CLAUDE_DEFAULT_NAME`（既定 `labteam`。`cc labteam` は `CLAUDE_CONFIG_DIR` 未設定を意味するので、`~/.claude-labteam` を作っても使われない）

### 共有 symlink と実体の衝突

setup スクリプトは共有 symlink を張る前に、張り先に**実ファイル・実ディレクトリ**が無いかを検査し、あれば何も変更せず中断する。`ln -sfn` は実ファイルを問答無用で置き換えて内容を失わせ、実ディレクトリは置き換えられずその中に同名リンクを作って半壊させるため（2026-07-28 実測）。

マーカー（`.agsw-profile`）は**正規化が完了してから**作る。先に作ると、途中で失敗した半端なディレクトリが「管理下」と誤認される。

## 日常の使い方

```bash
cx                # 状態表示（shell / App の email + plan + account_id / 起動中デーモン）
cx list           # プロファイル一覧（email + plan 付き。* = このシェル、@ = Codex App）
cx work           # このターミナルを work に切替
cx app personal   # Codex App 用の認証を personal に切替（App再起動で反映）

cc                # 状態表示
cc list           # プロファイル一覧（* = このシェル）
cc personal       # このターミナルを personal に切替
cc labteam        # デフォルトに戻す（= unset。App/拡張と同じ認証）
cc api            # API keyモードに切替
cc personal sub   # personal + subscriptionモード
```

> **`cc app` は存在しない。** `cx app` に相当する機能が Claude には無いため、`cc app <name>` は
> エラーになる（理由と実現方針は下記「`cc app` の検証」）。以前は `app` が黙って捨てられて
> `cc <name>` と同じ動作をしていたため、「App も切り替わった」と誤解する事故があった（2026-07-28）。
> Desktop App / VS Code 拡張は**常に**非ハッシュの `Claude Code-credentials`
> （= `CLAUDE_CONFIG_DIR` 未設定のアカウント）を読む。シェルで何に切り替えても GUI は変わらない。

### 引数の解釈（`cc` と `cx` で共通）

どちらも**1語目がサブコマンド**の位置固定で解釈する。余分な引数は黙って捨てずにエラーにする。

| 形 | `cc` | `cx` |
|---|---|---|
| 引数なし | 状態表示 | 状態表示 |
| `list` | プロファイル一覧 | プロファイル一覧 |
| `<name>` | アカウント切替 | アカウント切替 |
| `app <name>` | **未実装（エラー）** | App 用認証の切替 |
| `api` / `sub` | モード切替（`cc` のみ） | — |
| `<name> api\|sub` | アカウント + モード | — |

**アカウント（`personal` / `labteam` …）はサブスクの軸、`api` / `sub` はモードの軸**で、API キーは1つしかないためモードはアカウントの次元ではない。よって `cc api <name>` のような組み合わせは受け付けない（`cc <name> api` の順で指定する）。

> 以前の `cc` は全引数を走査するフラグ集合モデルで、語順が無関係だった（`cc api personal` が `cc personal api` と同義）。この緩さが `cc app personal` を黙って `cc personal` として通す原因になったため、`cx` と同じ位置固定に揃えた（2026-07-28）。

`cc` / `cx` はタブ補完に対応する（プロファイル名 ＋ サブコマンド。`cx app <TAB>` はプロファイル名のみ）。補完関数は `completions/` に置き `fpath` 経由で読み込むため、プラグインを `compinit` の前後どちらで source しても効く。

> 旧仕様の番号制エイリアス（`cc 1` / `cc 2`）は削除済み。3アカウント目以降で `cc 2` が意図しないアカウントへ飛ぶ誤動作があったため、名前指定のみに統一した。

### Codex の注意: app-server の control socket は CODEX_HOME ごとに分離される

`codex doctor --json` で確認できる通り、managed daemon の control socket / state dir（`$CODEX_HOME/app-server-control/`, `$CODEX_HOME/app-server-daemon/`）は `$CODEX_HOME` ごとに別物であり、他のツール・プロジェクトが起動した無関係な `codex app-server` プロセス（例: agmsg が別プロジェクト用に起動したもの、Codex Desktop App 自身のプロセス）が動いていても現在のシェルのアカウント切替には影響しない（2026-07-09 実測: `cx` での切替 → `codex` TUI 起動 → `/status` でアカウントが毎回正しく一致することを確認）。

以前 `cx` は `pgrep -f 'codex app-server'` でシステム上の全プロセスを走査し、CODEX_HOME が異なれば警告していたが、これは上記の理由で無関係なプロセスまで拾う誤検知だったため削除した。`cx` は現在、自分の `$CODEX_HOME` に紐づく managed daemon の pid file だけを見る。

## Codex 認証ファイルの保護

`CODEX_HOME` 未設定のまま生の `codex login` を実行すると、共有 symlink（`~/.codex/auth.json`）が別アカウントの**実ファイル**で上書きされる事故が起きる（2026-07-11 に実際に発生）。放置すると別アカウントの認証が残り続け、`cx app` 切替も拒否される。これを検知・修復・予防するために以下の仕組みがある。

### `~/.codex/auth.json` の3状態

| 状態 | 意味 | 扱い |
|---|---|---|
| (a) 正常な symlink（リンク先実在） | アクティブアカウントを指している | 正常。何もしない |
| (b) 実ファイル | 生 `codex login` が symlink を上書きした事故 | account_id を照合して修復を試みる |
| (c) 不在 or リンク切れ symlink | App 用の認証が無い | `cx app <name>` を案内 |

account_id は `auth.json` の `.tokens.account_id`（平文 JSON）で識別する（`jq` 前提・無い環境では照合をスキップ）。API-key 認証（`tokens` が null）では account_id が取れないため照合せず手動対処を案内する。

### 各機能

- **doctor 自動修復** — `cx`（状態表示）実行のたびに `bin/codex-auth-doctor --fix` が走る。(b) 実ファイルの account_id が既存プロファイルの**ただ1つ**と一致すれば、同一アカウントの新しいトークンとみなして `mv`＋symlink 復元する（上書きで安全）。複数一致・未知アカウントの場合は自動では触らず案内のみ。
- **起動時チェック** — 新しいインタラクティブシェルを開いたとき、App 用 auth.json が (b) または (c) の場合だけ `codex-auth-doctor`（`--fix` 無し・警告のみ）を呼ぶ。正常時は lstat 数回で即抜け、ファイルは一切変更しない。
- **login ガード** — `codex()` ラッパーが `codex login`/`codex logout` を捕捉し、書き込み先が共有 symlink（`CODEX_HOME` 未設定 or `$HOME/.codex`）になるときだけ警告する。インタラクティブなら続行確認、非インタラクティブなら拒否。`codex login status`（読み取りのみ）と `codex mcp login/logout`（MCP サーバの OAuth 操作で auth.json に触れない）は対象外。`AGSW_ALLOW_RAW_LOGIN=1` でバイパス可。正しい手順は `cx <name>` でアカウントを選んでから `codex login`。
- **launchd 通知** — `bin/codex-auth-watch` を launchd(`WatchPaths`) が `~/.codex/auth.json` の変更のたびに起動し、実ファイル化していたら macOS 通知を出す（修復はしない・`cx` 実行で自動修復される旨を通知）。nix 側の定義は `nix/hosts/darwin/yosuke-macbook-air.nix` の `launchd.user.agents."codex-auth-watch"`。
- **adopt** — 実ファイル化した `~/.codex/auth.json` を明示的にプロファイルへ取り込むコマンド。未知アカウント（doctor が自動修復しないケース）の受け皿。

```bash
# 実ファイル化した ~/.codex/auth.json を新規/既存プロファイルへ取り込む
./bin/setup-codex-account adopt <name>
```

`adopt` は取り込み先 dir が無ければ migrate 同様に作成する。dir が既にある場合、auth.json が無ければそのまま取り込み、有れば account_id が取り込み元と一致するときのみ上書きする（異なる・判定不能なら既存認証の破壊を避けて拒否）。

### codex プラグイン用 node の PATH 注入

`codex()` ラッパー（login ガードと同じ関数）は、`~/.local/share/codex-runtime/bin`（nix が node を配置。`nix/home/files.nix` 参照）が存在すれば codex 起動時だけそのディレクトリを PATH 先頭に注入する。node をグローバル PATH には置かない方針のまま、node に依存する Codex プラグイン（`sites@openai-bundled` 等）の MCP サーバを `command: "node"` で起動できるようにするための仕組み。既知の制限として、この zsh 関数を経由しない起動（GUI の Codex App、他ツールが直接 spawn する `codex app-server` 等）には効かない。

### Claude プラグイン hook 用 node の PATH 注入（シム方式）

Claude 側も同じ目的（`~/.local/share/claude-runtime/bin` の node と `.../fallback` の
python ガードを claude のプロセスにだけ注入する）だが、**zsh 関数ではなく実行可能な
シム**が担う。実体は `shims/claude`、配備先は `~/.local/share/agent-switch/shims/claude`
（`nix/home/files.nix` の symlink）。`zsh/zshenv` と `zsh/zshrc` がこのディレクトリを
Homebrew より前に置くので、`claude` は必ずシム経由で起動する。

**なぜ zsh 関数では不十分だったか（2026-07-28 実測）**

`openai-codex` プラグインの SessionEnd hook が

```
SessionEnd hook [node "${CLAUDE_PLUGIN_ROOT}/scripts/session-lifecycle-hook.mjs" SessionEnd] failed: /bin/sh: node: command not found
```

で落ちる事象を調査した結果、

- hook は `/bin/sh -c` で起動されるが、**claude プロセスの env（PATH 含む）をそのまま
  継承する**。sandbox 設定・SessionEnd のタイミング・PATH のサニタイズはいずれも無関係
  （runtime を PATH に入れて `claude -p` を走らせると SessionStart / Stop / SessionEnd の
  すべてで `node` が解決できることを実測で確認）。
- したがって原因は「claude プロセスの PATH に node が無い」ことだけ。PATH から
  `claude-runtime` を外して `claude -p` を走らせると上記エラーが一字一句再現する。
- 旧実装の注入は `lib/claude.zsh` の `claude()` **zsh 関数**にしか無かったため、
  非対話シェル（`zsh -c` / bash / sh）からの起動、herdr / cmux が自プロセスの env のまま
  spawn した claude、関数が定義される前に起動していた古いシェルでは注入されない。
  実際 `herdr server` の PATH には `claude-runtime` が入っていない（実測）ので、
  herdr が直接 spawn した claude はこの状態になる。

シムは実行可能ファイルなのでシェルの種類に依存せず、PATH を継承した子プロセス
（`herdr server` → claude 等）にも効く。`settings.json` の `env` で PATH を渡す方法は
**採らない**（`env.PATH` は PATH を丸ごと置換し、`${PATH}` も展開されない ―― 実測で
`/bin/sh: sh: command not found` になった。devshell の PATH も壊れる）。

`claude()` zsh 関数は残してあるが、シムと注入が二重に走っても PATH は汚れない
（シムの注入は冪等）。関数は「シムがまだ配備されていない古いシェル」の保険。

#### 効く範囲と効かない範囲（重要）

シムが効くのは **PATH を継承して `claude` を起動するプロセス**に限る。

| 起動経路 | シムを通るか |
|---|---|
| 対話シェル（`zsh -ic` / `zsh -lic`）| ✅ |
| 非対話シェル（`zsh -c` / `zsh -lc` / bash / sh）| ✅ |
| PATH を継承した子プロセス（herdr / cmux → claude）| ✅ |
| **launchd 起動の GUI（Claude Desktop / VS Code 拡張）** | ❌ **効かない** |

launchd は zsh の起動ファイルを読まないため、GUI プロセスの PATH にシムのディレクトリが
入らない。GUI が spawn した `claude` はシムを通らず、プラグイン hook は従来どおり
`node: command not found` になりうる。**これは旧実装（zsh 関数）でも同じで、シム方式が
悪化させたわけではないが、解決もしていない。** GUI 経路まで直すには launchd の環境変数
（`launchctl setenv` や `launchd.user.agents` の `EnvironmentVariables`）に頼る必要があり、
未着手。

なお PATH の順序確保には注意が要る。`~/.zprofile` の `brew shellenv` が
`/opt/homebrew/bin` を PATH 先頭へ押し込むため、`zsh/zshenv` での順序付けだけでは
ログインシェルで無効化される。`zsh/zshrc` は非対話では読まれないので、`zsh -lc` に穴が開く
（2026-07-28 実測: シムも `~/.agents/bin/codex` も Homebrew に負けていた）。
このため順序付けは `zsh/zshenv` で `dot_path_priority` 関数として定義し、
`zsh/zprofile`（`brew shellenv` の後）と `zsh/zshrc` から呼び直している。

## `cc app` の検証

`cc app`（Desktop App / VS Code 拡張のアカウント切替）は未実装。設計方針と、着手前に測るべきことを記録する。

**要件**: GUI と CLI が**同じアカウントを同時に**使えること（Codex では `cx app` で成立している）。

**Codex が満たしている不変条件**: `~/.codex/auth.json` が symlink なので、そのアカウントのトークンの実体は1つしかない。refresh は symlink を貫通して実体に in-place 書き込みされるため、GUI と CLI のどちらが refresh してもドリフトしない。

**Claude で同じ不変条件を作る方法**: Keychain エントリは symlink できないので、**コピーではなく move** でしか作れない。

- 共有スロット = 非ハッシュの `Claude Code-credentials`（GUI / 拡張が読む唯一の場所。`CLAUDE_CONFIG_DIR` 未設定の CLI も同じエントリを読む ＝ **同時使用可**）
- パーク中のアカウント = `Claude Code-credentials-<SHA256(dir)[0:8]>`
- `cc app <name>` は「今のスロット占有者をパーク（move out）→ `<name>` をマウント（move in）」。移動元を消すことで、各アカウントのトークンが常に1箇所にしか存在しない状態を保つ
- 共有スロットに載っているアカウントは `cc <name>` でも `unset CLAUDE_CONFIG_DIR` になる（ポインタファイルから導出）

**着手前に測ること**:

1. **Keychain ↔ `.credentials.json` の相互削除**（最重要）。Claude Code の credential store は「Keychain 優先 → `~/.claude/.credentials.json` フォールバック」の組み合わせで、片方への書き込み成功時に他方を削除するクリーンアップを持つ（[claude-code#37512](https://github.com/anthropics/claude-code/issues/37512) の解析）。実際に `~/.claude/.credentials.json` が存在する。**Keychain エントリが勝手に消える事象が観測されたら実装は見送る**（土台が不安定な上に move 方式を積んでも間欠故障になる）。
2. **refreshToken のローテーション**。`refreshTokenExpiresAt` フィールドが存在し、[#68241](https://github.com/anthropics/claude-code/issues/68241) は「single-use refresh token が既に消費された」と記述している。ローテーションするなら move 方式が必須（コピーでは必ず壊れる）。

**却下した代替案**: `CLAUDE_CODE_OAUTH_TOKEN`（`claude setup-token` の長寿命トークンを env var で渡す）。config dir が1つで済み symlink も不要という利点があるが、[#37512](https://github.com/anthropics/claude-code/issues/37512)（env var を設定すると終了時に Keychain エントリを**削除する**）、[#68241](https://github.com/anthropics/claude-code/issues/68241)（stale な `.credentials.json` が env var を shadow する）、[#78181](https://github.com/anthropics/claude-code/issues/78181)（長時間プロセスで 401）により不適格。GUI 切替も解決しない（env var は launchd に届かない）。

**却下した代替案2**: 全アカウントを `CLAUDE_CONFIG_DIR` 化する素朴な対称化。unset スロットを誰も占めなくなり、GUI / 拡張のアカウントが宙に浮くため、`cc app` とセットでなければ現状より悪化する。

## 動作要件

- zsh（bash/fish は未対応。独立リポジトリ化の際に eval-init 方式への移行を検討）
- デーモン警告は macOS 前提
- Claude 側の email/org 表示、Codex 側の email / plan / account_id 表示はいずれも `jq` 前提
  （無い環境ではその旨を表示してスキップ。以前は Claude 側だけ python3 実装だったため、
  Claude Code セッション内の system-python 誤用ガードで動かなくなっていた。2026-08-04 統一）

## 検証記録（2026-07-02 実測）

設計の根拠となった実測。将来のバージョンで挙動が変わった場合はここを更新する。

1. **Claude の Keychain は dir 単位分離**: 認証情報を持たないテスト用 `CLAUDE_CONFIG_DIR` で `claude -p` を実行 → `Not logged in`（デフォルトの Keychain エントリは流用されない）。Keychain には `Claude Code-credentials`（デフォルト用）のエントリを確認。
2. **Claude の identity ファイルの所在**: `CLAUDE_CONFIG_DIR` 未設定時は `~/.claude.json`（ホーム直下）が実体（mtime 実測）。`~/.claude/.claude.json` は更新されない旧位置。設定時は `$CLAUDE_CONFIG_DIR/.claude.json`。
3. **Codex の auth.json 書き込み**: `codex-rs/login/src/auth/storage.rs` の `FileAuthStorage::save()` は truncate+in-place 書き込みで symlink をフォローする。config.toml 書き込みは `resolve_symlink_write_paths` で symlink 解決後に atomic write（symlink は壊れない）。

## ファイル構成

```
agent-switch.plugin.zsh   # エントリポイント（関数定義＋補完登録＋起動時の読み取り専用チェック）
lib/common.zsh            # マーカー定数 / プロファイル判定・列挙の共通ヘルパ
lib/claude.zsh            # cc / cc_list / cc_status / claude() ラッパー
lib/codex.zsh             # cx / cx_list / cx_status / codex() ガード / 起動時チェック
completions/_cc           # cc のタブ補完（fpath 経由で読み込む）
completions/_cx           # cx のタブ補完
bin/agsw-list-profiles    # マーカー付きプロファイルの列挙（zsh/bash 双方から使う唯一の実装）
bin/agsw-codex-account-id # Codex auth.json から account_id を取り出す（同上）
bin/agsw-codex-identity   # Codex auth.json から email / plan / account_id を取り出す（jq 実装）
bin/agsw-check-name       # プロファイル名の検査（パス脱出・予約語の拒否）
bin/setup-claude-account  # Claude アカウント dir 作成・正規化
bin/setup-codex-account   # Codex アカウント dir 作成・正規化（migrate / adopt / add）
bin/check-codex-drift     # プロファイル間の symlink 漏れ検出・修復
bin/codex-auth-doctor     # App 用 auth.json の3状態チェック・修復
bin/codex-auth-watch      # launchd から実ファイル化を検知して macOS 通知
```

`bin/*` は bash、`lib/*` と `completions/*` は zsh。両者から使う判定ロジック（マーカー規則・`account_id` 取得）は実装が分岐しないよう `bin/agsw-*` に実行可能スクリプトとして切り出してある。
