# dotfiles

Yosuke の Mac 環境の本体 flake。nix 設定・homebrew・agenix シークレットを一元管理。

## public / private の分担

このリポジトリは**公開できるもの**を置く。
公開したくない個人 skills は private overlay（`dotfiles-private`）に分離されている。

private overlay が手元にある場合はそちらのコンテキストも読み込む：

@../dotfiles-private/CLAUDE.md

## skill の置き場所

新しい skill を追加するときは以下で判断する：

| 種類 | 置き場所 |
|---|---|
| 汎用・他人にも役立つ・公開できる | `agents/skills/`（このリポジトリ） |
| 個人ワークフロー・公開したくない | `dotfiles-private/agents/skills/` |

判断に迷ったら **private 側に置く**（後で public に昇格させることはできる）。

## ディレクトリ構成（主要部分）

```
dotfiles/
├── agents/skills/   # 汎用 skills（Claude Code / Codex）
├── nix/             # nix 設定（hosts・profiles・home-manager）
├── secrets/         # agenix 暗号化シークレット（*.age）
├── flake.nix        # 本体 flake（darwinConfigurations を定義）
├── templates/       # devshell テンプレート（python-uv・node）
└── tools/agent-switch/  # cc/cx アカウント切替（自己完結・将来独立repo化予定）
```

## マルチアカウント切り替え（cc / cx）

Claude Code / Codex のアカウント切替は `tools/agent-switch/` 参照（zshrc から source される
zsh プラグイン）。設計・検証記録は `tools/agent-switch/README.md`、ツール固有の事情は
`claude/README.md`・`codex/README.md`。

## Symlink の仕組み

`~/.claude/` や `~/.codex/` 以下のファイルは dotfiles からの symlink で管理されている。
symlink の定義はコードが正。参照先：

- public: `nix/hosts/darwin/common/default.nix` の `postActivation`
- private overlay: `nix/hosts/darwin/yosuke-macbook-air.nix` の `postActivation`

### 覚えておくべき原則

- `~/.claude/settings.json` は symlink のため、`/plugin install` 等による書き換えは
  自動で dotfiles 側（`claude/settings.json`）に反映される。変更後は必ず `git commit` する。
- skills は per-directory symlink。ディレクトリを新規追加したら `darwin-switch` が必要。
- plugins は `claude/install-plugins.sh` が `darwin-switch` 時に冪等インストールする。
  `settings.json` の `enabledPlugins` が source of truth。

## よく使う操作

```bash
# nix 設定・homebrew を変更したあと
darwin-switch

# 汎用 skill を追加（新規ディレクトリを足したら darwin-switch が必要）
mkdir agents/skills/<name>
# SKILL.md を書く
darwin-switch
```
