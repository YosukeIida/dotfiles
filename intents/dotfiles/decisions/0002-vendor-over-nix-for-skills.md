---
facets: [invariant]
---

# 0002 — 外部 skill は vendor + sync に統一する（agent-skills-nix を採用しない）

- Status: **Canonical**
- Date: 2026-07-17
- Scope: 外部由来 skill の配備方式

## Context

外部の公開 skill（gist・repo 由来）を宣言的に管理したい。当初は
`Kyure-A/agent-skills-nix`（home-manager モジュール、flake input + `structure = "link"`）で
各 skill を個別の Nix derivation として配備する設計にし、実装・build・`darwin-switch` まで
通した。

## Decision

**agent-skills-nix を採用せず、git 管理された実ディレクトリを postActivation の `_link` で
1回だけ symlink する vendor + sync 方式に統一する。**

## Rationale — 実機検証で相対参照が壊れることを確認した

`structure = "link"` は各 skill を `home.file` の `recursive = true` で **per-file symlink** する
ため、各 skill が個別の Nix derivation に隔離される。

`cognitive-rhythm-writing` は `../japanese-tech-writing/SKILL.md` を相対参照している。
symlink を辿った**後の物理的な親**から `..` を解決するため、そこには
`japanese-tech-writing` が存在せず `ENOENT` になる（`cat` でリテラルパスを開いて実証済み）。

一方 vendor + sync 方式なら、symlink 解決後の `..` は git checkout 内の本物の兄弟
ディレクトリに戻るため、この問題が起きない。

**教訓**: skill 間に相対参照の依存がある場合、Nix の個別 derivation 化は罠になりうる。

## Consequences

- 外部 skill は `agents/skills/<name>` に実体として commit される（vendor）。
- 更新は sync スクリプト（`sync-gist-skills.sh` / `sync-lab-skills.sh`）で rev pin を
  書き換えて実行し、`git diff` を目視してから commit する。
- `gh skill install` / `update` は使わない（命令型で、Nix / git の diff レビュー運用と競合する）。
  `gh skill search` / `preview` / `publish` のみ使う。
- upstream が SKILL.md の配置を変えると sync スクリプトが 404 で落ちる。落ちたらパスを直す
  （2026-08-03 に herdr がこれに該当し、`SKILL.md` → `skills/herdr/SKILL.md` へ追従した）。

## Alternatives considered

**Homebrew ラッパー方式（`brew bundle install --cleanup` 相当を skill に作る）** — 不採用。
brew wrapper が成立するのは `brew bundle install --cleanup` 自体が宣言リストとの差分を取って
収束させるリコンサイル機能を持つため。`gh skill` / `vercel-labs/skills` にはこの収束機能が無く
（[vercel-labs/skills#1530](https://github.com/vercel-labs/skills/issues/1530) で報告されている）、
自作すると brew の cleanup 相当を再実装することになり複雑性に見合わない。GUI アプリと違い
skill は Markdown で git にそのまま持てるので、impure なラッパーを許容する物理的理由もない。

## Source

- memory `skill-architecture-4layer`（2026-07-17、実機検証の記録）
- `dotfiles/CLAUDE.md` — 「外部 skill は vendor + sync スクリプトに統一する（agent-skills-nix 等は使わない）」

## Related

- [0006 — 外部 skill 取り込み時の目視 diff を必須にする](0006-external-skill-diff-review.md)
