# Yosuke の環境メモ

## Nix Darwin セットアップ

### darwin-switch コマンド

```bash
darwin-switch
# 実体: sudo darwin-rebuild switch --flake /Users/yosuke/workspace/github.com/YosukeIida/dotfiles#Yosukes-MacBook-Air
```

設定ファイル: `~/workspace/github.com/YosukeIida/dotfiles/configuration.nix`

---

## Nix devshell を新しい repo に追加する手順

### 標準テンプレート（uv + Node.js）

Claude Code を使う repo はこれを使う。Python (uv) と Node.js (npm) の両方が入る。

```bash
cd ~/workspace/github.com/<org>/<repo>
mkdir -p nix
cp ~/workspace/github.com/YosukeIida/dotfiles/templates/python-uv/nix/flake.nix nix/
cp ~/workspace/github.com/YosukeIida/dotfiles/templates/python-uv/nix/flake.lock nix/
echo 'use flake ./nix' > .envrc
direnv allow
```

`nix flake init -t` は使わない（`~/.config/nix-darwin` が存在しないため手動コピーで対応）。

### テンプレートの場所

`~/workspace/github.com/YosukeIida/dotfiles/templates/`
- `python-uv/` : Python 3.13 + uv + Node.js 22
- `node/`      : Python 3.13 + uv + Node.js 22（同じ内容）

### 生成されるファイル構成

```
<repo>/
├── nix/
│   ├── flake.nix    # devshell の定義（git 管理する）
│   └── flake.lock   # nixpkgs のバージョン固定（git 管理する）
└── .envrc           # "use flake nix" の1行
```

`cd` するだけで direnv が自動的に devshell を有効化する。

### devshell に含まれるもの

| ツール | バージョン |
|---|---|
| Python | 3.13 |
| uv | latest |
| Node.js | 22 |
| npm | Node.js に付属 |

`UV_PYTHON_DOWNLOADS = "never"` が設定されているので、uv は nix の Python を使う。

### flake を nix/ サブディレクトリに置く理由

`use flake path:.`（リポジトリ全体）だと git tree が dirty のとき毎回全ファイルを
nix store にコピーするため起動が遅くなる。`nix/` に置くことで対象が2ファイルだけになり高速化される。

---

## Nix GC（ガベージコレクション）

```bash
nix-collect-garbage -d   # 古い世代も含めて全削除
```

`-d` を付けると darwin-rebuild のロールバックはできなくなる（問題なければ OK）。

---

## パッケージ管理の方針

- グローバルに常に使いたいツール（CLI ツール類）→ `~/workspace/github.com/YosukeIida/dotfiles/nix/home/packages.nix` の `home.packages`
- グローバルに常に使いたいツール（Homebrew formula/cask）→ `nix/profiles/darwin/homebrew.nix` の `brews` / `casks`
- プロジェクト固有のツール → `nix/flake.nix` の `packages`（nix devshell）
- `npm install -g` は使わない → `npx` か `nix/flake.nix` に追加する

### nixpkgs にパッケージが存在するか確認する方法

`nix search nixpkgs <package>` はレジストリのキャッシュを参照するため、
flake.lock でピンしたバージョンと一致しないことがある。正確に確認するには：

```bash
# Web（確実・手軽）
# https://search.nixos.org/packages → チャンネルを "unstable" にして検索

# CLI（flake.lockのピンに対して確認）
nix eval nixpkgs#<attribute>.pname                   # 例: nix eval nixpkgs#python3Packages.twscrape.pname
```

## グローバルで使えるツール

### twscrape（X/Twitter スクレイパー）

`python3Packages.twscrape` として `home.packages` に追加済み（darwin-switch 後に有効）。
X の内部 GraphQL API 経由でツイート検索・ユーザー情報取得・タイムライン収集ができる。

使い方の詳細は `twscrape` スキルを参照すること（Skill ツールで自動ロードされる）。
初回はアカウント登録が必要（`twscrape add_accounts` / `twscrape login_all`）。

---

## Python 環境の方針

### 禁止事項

```bash
python3 -m pip install --user <package>  # ❌ macOS のシステム Python を汚す
pip install <package>                    # ❌ 同上
```

macOS の system Python（Xcode 由来）やユーザー領域（`~/Library/Python/`）には何も入れない。

### 正しい使い方

| 用途 | コマンド |
|---|---|
| 一時的なスクリプト実行 | `uvx --with <pkg> python script.py` |
| 複数パッケージが必要 | `uv run --with <pkg1> --with <pkg2> python script.py` |
| プロジェクト内（継続利用） | `uv add <pkg>` して `uv run python script.py` |
| HTTP サーバ（標準ライブラリ） | `python -m http.server 8080`（インストール不要） |

### nix devshell が有効かを確認する手順

プロジェクトに `.envrc` がある場合、作業前に以下を確認する：

```bash
# direnv の状態を確認
direnv status
# "Found RC" かつ "Loaded" になっていれば有効

# nix の python / uv が使われているか確認
which python3   # /nix/store/... → OK
which uv        # /nix/store/... → OK
```

有効でない場合は `direnv allow` を実行してから作業を開始する：

```bash
direnv allow
```

devshell が起動していない状態でパッケージが必要な場合は `uvx` を使う。
