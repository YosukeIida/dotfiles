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
└── templates/       # devshell テンプレート（python-uv・node）
```

## よく使う操作

```bash
# nix 設定・homebrew を変更したあと
darwin-switch

# 汎用 skill を追加（新規ディレクトリを足したら darwin-switch が必要）
mkdir agents/skills/<name>
# SKILL.md を書く
darwin-switch
```
