---
# Optional semantic facets (G529) — closed set, one line each:
#   vocabulary            — event/command vocabulary: what counts as a fact
#   invariant              — invariants and consistency boundaries
#   decider                — decider judgments: what a command decides
#   acceptance-property    — what must not break
facets: [invariant]
---

# Mission

> Ask intent-cli for guidance before editing:
> `intent-cli guide intent-work setup --kind tree-layout --domain dotfiles --format markdown`

## Mission statement

Yosuke の Mac 環境（Yosukes-MacBook-Air）を、宣言的・再現可能・かつ公開可能な形で
単一の nix flake に集約する。秘密の値と公開したくない個人資産は private overlay に
分離し、public 側は private アクセスなしで評価できる状態を保つ。

## Vision

環境の状態が「コードが正」で説明できること。手作業で入れたもの・手で書き換えたものが
どこにも残っておらず、新しいマシンでも `darwin-switch` 一発で同じ環境に収束する。
「なぜこの設定なのか」は git 履歴と intent tree を辿れば必ず出てくる。

## Values / principles

- **コードが正** — `~/.claude/` 等の実体は dotfiles からの symlink であり、
  実体側を手で書き換える運用を作らない。書き換わったら dotfiles 側に反映して commit する。
- **public flake は private なしで評価できる** — private なソースを flake input にしない。
  private なものは実行時の存在チェックで任意化する。破ると公開 CI が壊れる。
- **言語ランタイムをグローバルに汚さない** — `npm install -g` / `pip install --user` を使わない。
  ツールごとに閉じたバイナリか、使い捨ての実行環境（`uvx` / `npx`）で済ませる。
- **更新の検知は自動化してよいが、更新の適用は人間のレビューを介す** — 外部由来のコンテンツ
  （特に skill）は prompt injection の経路になるため、取り込み時の目視 diff を省略しない。
- **迷ったら private に置く** — public への昇格は後からできるが、逆は取り返せない。
- **厳密な発動制御より、必要な時に楽に呼べること** — skill の自動発動は維持する。
  制御を厳しくする方向（明示呼び出し専用化・ディレクトリスコープ分離）は選ばない。

## Glossary

| 用語 | 意味 |
|---|---|
| `darwin-switch` | `sudo darwin-rebuild switch --flake <dotfiles>#Yosukes-MacBook-Air` のラッパー。この環境の唯一の収束手段 |
| public / private overlay | public = `YosukeIida/dotfiles`（本体）、private = `YosukeIida/dotfiles-private`（公開したくない skill 群）。private は flake input ではなく、activation script が symlink するだけ |
| vendor + sync | 外部由来の skill を rev pin 付きで実ディレクトリとして取り込む方式。`sync-gist-skills.sh` / `sync-lab-skills.sh` が担う |
| `_link` | postActivation で dotfiles 内の実ディレクトリを `~/.claude/skills/` 等へ symlink する仕組み |
| agenix | 秘密の値を `secrets/*.age` として暗号化して public repo に置く仕組み |
| host metadata | intent-cli の durable state（`.intent-cli/` と `intents/`）。`main-metadata` ブランチに隔離されている |
