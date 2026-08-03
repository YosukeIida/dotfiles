---
facets: [invariant]
---

# 0001 — public / private の分離と、public flake の自己完結性

- Status: **Canonical**
- Date: 2026-06（単一 public repo 化）／2026-07 に skill 4層へ発展
- Scope: リポジトリ構成全体

## Context

環境設定には、公開して差し支えないもの（nix 設定・homebrew リスト・暗号化済み secret）と、
公開したくないもの（個人的な skill、研究室由来の skill）が混在する。当初は private repo
1本だったが、2026-06 に本体を public 化した。

## Decision

**本体（`YosukeIida/dotfiles`）を public とし、公開したくない skill だけを
private overlay（`YosukeIida/dotfiles-private`）に分離する。**

そして最も重要な制約として:

> **public flake は private アクセスなしで評価できること。**

- private なソースを flake input にしない。
- private なものは実行時の存在チェックで任意化する。
- private overlay の取り込みは、activation script（postActivation）が
  ローカルパスを symlink するだけに留める。

秘密の「値」は private repo には置かず、public 側の agenix（`secrets/*.age`）に集約する。

## Consequences

- 公開 CI が private アクセス権を持たなくても flake が評価できる。この性質を破る変更は入れない。
- private overlay が手元に無いマシンでも `darwin-switch` が通る。
- 判断に迷う skill は private 側に置く。public への昇格は後からできるが、逆はできない。

## Source

- `dotfiles/CLAUDE.md` — 「public / private の分担」「原則：public flake は private アクセスなしで評価できること」
- `dotfiles-private/CLAUDE.md` — 「このリポジトリは flake input ではない」「秘密の『値』はここに置かない」

## Related

- [0002 — 外部 skill は vendor + sync に統一](0002-vendor-over-nix-for-skills.md)
