---
facets: [invariant]
---

# intent-cli-integration — overview

> **Ask intent-cli first:** `intent-cli guide intent-work setup --kind tree-layout --domain dotfiles --format markdown`

## Goals

intent-cli による意図駆動開発を dotfiles ドメインで運用可能にし、**その導入自体を
dotfiles の宣言的管理の原則に完全に載せる**。

導入は 2026-08-03 に開始した。CLI の install（nix derivation）と host metadata の初期化
（トポロジー B）は完了しているが、**dotfiles の既存原則と整合しない箇所が残っている**。
この feature はその解消を担う。

## Current state（2026-08-03 時点）

完了:

- `intent-cli` を `nix/home/packages.nix` の custom derivation として導入（self-contained
  binary を `fetchurl` + sha256 検証。dotnet SDK は入れない
  → [ADR 0004](../../decisions/0004-nix-first-packages.md)）
- トポロジー B を採用し、host metadata を orphan ブランチ `main-metadata` に隔離
  （`main` には実装コードのみ。実装 PR が metadata を含まないようにするため）
- tree-v1 layout、`project_type: infrastructure`
- `intent host-check`: ok ／ `intent lint-layout`: clean ／ `same-repo-metadata-preflight`: clean

未解決（下記 Acceptance criteria に対応）:

1. dispatcher skill が dotfiles の管理外にある
2. dotfiles 実作業の粒度と intent-cli の issue 契約の粒度が合っていない
3. 4スレッド運用の物理配置（review-runtime / child worktree）が未整備

## Acceptance criteria summary

- [ ] dispatcher skill の配備が dotfiles 側から再現できる（新マシンで入れ忘れない）
- [ ] dotfiles の実作業に対して packet → issue → PR を1周させ、粒度の妥当性を実測で判断できている
- [ ] 4スレッド運用の物理配置が決まり、記録されている

詳細は [acceptance.md](acceptance.md)。

## Non-goals

- agmsg の廃止。agmsg と herdr-only はチーム単位で選ぶ対等な選択肢であり、
  どちらかに寄せることはこの feature の目的ではない。
- intent-cli 自体への機能追加・upstream への PR。

## Related

- [requirements.md](requirements.md)
- [acceptance.md](acceptance.md)
- [decisions.md](decisions.md)
- [open-questions.md](open-questions.md)
- [packets.md](packets.md)
