# dotfiles

Yosuke の Mac 環境の本体 flake。nix 設定・homebrew・agenix シークレットを一元管理。

## public / private の分担

このリポジトリは**公開できるもの**を置く。
公開したくない個人 skills は private overlay（`dotfiles-private`）に分離されている。

private overlay が手元にある場合はそちらのコンテキストも読み込む：

@../dotfiles-private/CLAUDE.md

## skill の置き場所（4層アーキテクチャ、2026-07 移行）

新しい skill を追加・取り込むときは以下で判断する：

| 種類 | 置き場所 | 配備 / 更新 |
|---|---|---|
| 自作・公開できる | `YosukeIida/personal-agent-skills`（別repo、root-level `<skill>/SKILL.md`） | postActivation `_link`（編集即時反映）。他者は `gh skill install` で利用可 |
| 自作・公開したくない | `dotfiles-private/agents/skills/` | 同上 |
| 外部・研究室（private repo 由来） | `dotfiles-private/agents/skills/tmllab-*`（vendored） | `dotfiles-private/sync-lab-skills.sh`（rev pin・パッチ内蔵）→ git diff 目視 → commit |
| 外部・公開 repo/gist 由来 | flake input + `nix/home/agent-skills.nix`（agent-skills-nix） | `nix flake update <input>` → diff 目視 → darwin-switch |

判断に迷ったら **private 側に置く**（後で public に昇格させることはできる）。

**原則：public flake は private アクセスなしで評価できること。** private なソースを
flake input にしない（公開 CI が壊れる）。private なものは実行時の存在チェックで任意化する。

外部 skill の取り込み・更新時は内容の目視 diff を必須とする（外部 skill の
プロンプトインジェクション対策）。取り込み前の検査には `gh skill preview <owner/repo> <skill>`
が使える。`gh skill install/update` は命令型で Nix 管理と競合するため使わない。

## ディレクトリ構成（主要部分）

```
dotfiles/
├── agents/subagents/  # サブエージェント定義（skills 本体は personal-agent-skills repo へ分離済み）
├── nix/             # nix 設定（hosts・profiles・home-manager）
│   └── home/agent-skills.nix  # 外部公開 skill（gist 等）の宣言管理
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
- 自作 skills は per-directory symlink（public は personal-agent-skills repo、private は
  dotfiles-private から）。ディレクトリを新規追加したら `darwin-switch` が必要。
  リンク切れ symlink は switch 時に自動掃除される。
- 外部 gist/repo 由来 skills は home-manager（agent-skills-nix、structure = "link"）が
  `~/.claude/skills/` と `~/.codex/skills/` に per-file symlink で配備する。
  `structure = "symlink-tree"` は rsync --delete が `_link` 管理 skill を消すため使用禁止。
- plugins は `claude/install-plugins.sh` が `darwin-switch` 時に冪等インストールする。
  `settings.json` の `enabledPlugins` が source of truth。

## よく使う操作

```bash
# nix 設定・homebrew を変更したあと
darwin-switch

# 自作の公開 skill を追加（新規ディレクトリを足したら darwin-switch が必要）
mkdir ~/workspace/github.com/YosukeIida/personal-agent-skills/<name>
# SKILL.md を書く → personal-agent-skills 側で commit
darwin-switch

# 外部の公開 skill（gist/repo）を宣言的に取り込む
# flake.nix に input 追加 + nix/home/agent-skills.nix に source/explicit を追記
darwin-switch

# 研究室 skill（tmllab-*）の更新確認と取り込み
~/workspace/github.com/YosukeIida/dotfiles-private/sync-lab-skills.sh --check
# REV を更新して実行 → dotfiles-private で git diff を目視 → commit
```
