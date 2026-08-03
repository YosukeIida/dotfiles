---
facets: [invariant, acceptance-property]
---

# 0006 — 更新の検知は自動化する。更新の適用は人間のレビューを介す

- Status: **Canonical**
- Date: 2026-07（自動検知の実装を含む）
- Scope: 外部由来 skill の更新運用

## Context

外部由来の skill は他人が書いたプロンプトであり、prompt injection の経路になりうる。
一方で、upstream の更新に気づかないまま古いものを使い続けるのも避けたい。
この2つの要求は「自動化してよい範囲」が違う。

## Decision

**検知は自動化する。適用は必ず人間の目視 diff を介す。**

- `darwin-switch` のたびに `sync-gist-skills.sh --check` と `sync-lab-skills.sh --check` が
  自動実行され、upstream に更新があれば通知する。**内容は一切書き換えない、読み取り専用。**
- 実際に取り込むときは、スクリプト本体の rev pin を手で更新して実行し、
  `git diff` を目視してから commit する。この目視は省略しない。
- 取り込み前の検査には `gh skill preview <owner/repo> <skill>` が使える。

## Rationale

外部 skill の内容は LLM に渡る指示そのものなので、内容を見ずに自動適用すると
injection をそのまま受け入れることになる（ToxicSkills 型のリスク）。
一方「更新があるか」の判定は内容を信頼せずに実行できるので、自動化して差し支えない。

Homebrew との対比: `brew bundle install --cleanup` は宣言リストとの差分を取って収束させる
リコンサイル機能を持つため自動適用が成立する。skill にはその収束機能が無く、かつ
内容が指示である点が根本的に違う。

## Implementation note

`sync-lab-skills.sh` は各 SKILL.md の frontmatter に
`metadata.github-repo` / `github-ref` / `github-path` / `github-tree-sha` を自前で注入している。
この metadata を使って `gh skill update --dir ... --dry-run` が skill 単位の正確な差分検知を行う
（whole-repo の commit 数比較ではなく tree-sha 比較）。

- `gh skill install` の出力そのものは使わない。YAML 再シリアライズが改行入り description を
  1行に畳んでパッチのアンカーを壊すため。
- **`github-pinned` は入れない。** 入れると `gh skill update` が「pin 済みだからチェック対象外」
  としてスキップすることを実測で確認した。
- gist は `gh skill install` が受け付けない（GitHub Repos API のみ。gist URL は 404）ため、
  この metadata 方式が使えず、rev コミット数比較のままである。

## Consequences

- `darwin-switch` の出力に「agent skills: 更新があります」が出ても、それは通知のみで
  何も変わっていない。pin は手で上げるまで動かない。
- upstream が SKILL.md の配置を変えた場合、sync スクリプトが 404 で落ちる。これは
  fail-fast として機能する（黙って古いものを使い続けない）。

## Source

- `dotfiles/CLAUDE.md` — 「外部 skill の取り込み・更新時は内容の目視 diff を必須とする」
- memory `skill-architecture-4layer` — 自動検知の実装詳細と実測記録

## Related

- [0002 — 外部 skill は vendor + sync に統一](0002-vendor-over-nix-for-skills.md)
