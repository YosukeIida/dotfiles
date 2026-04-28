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

- グローバルに常に使いたいツール → `configuration.nix` の `homebrew.brews` または `environment.systemPackages`
- プロジェクト固有のツール → `nix/flake.nix` の `packages`（nix devshell）
- `npm install -g` は使わない → `npx` か `nix/flake.nix` に追加する
