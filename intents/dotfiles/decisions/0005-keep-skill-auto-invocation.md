---
facets: [decider]
---

# 0005 — skill の自動発動を維持する（制御を厳しくする方向を選ばない）

- Status: **Canonical**
- Date: 2026-07-17 前後
- Scope: skill の発動スコープ設計

## Context

skill が増えて「どの階層のものか分からなくなる」「意図しない skill が発動する」問題がある。
対処として、発動を制御する仕組みがいくつか存在する。

## Decision

**skill の自動発動は維持する。制御を厳しくする方向の仕組みは採用しない。**

不採用にしたもの:

- **`disable-model-invocation: true`**（明示呼び出し専用化、Claude による自動発動を禁止する
  frontmatter 設定）→ 不採用。理由は「明示的に呼ぶのが面倒」。自動発動は問題ないと考えている。
- **ディレクトリスコープによる分離**（project-local `.claude/skills/` に置いて対象を絞る）
  → 不採用。「置き場所によって挙動が変わるのはビミョい」。

代わりに採る方向:

**命名と description で発見しやすくする。** 各 skill の description 末尾にある
「※〜は…が担当」という相互参照が、境界を明示する実際の仕組みとして機能している。
分類はフォルダ階層ではなく **3軸**（対象ジャンル × 効かせる観点 × 運用コンテキスト）で考える。

## Rationale

このユーザーは「厳密な発動制御」より「必要な時に楽に呼べること」を優先する。
自動発動の誤爆リスクより、明示呼び出し時の手間を嫌う。

## Consequences

- 今後 skill の発動スコープを相談されたときは、制御を厳しくする提案より、
  自動発動を維持しつつ命名 / description / プレフィックスで発見性を上げる方向で提案する。
- skill 名のプレフィックス（`tmllab-*` 等）は許容する。明示呼び出し時の想起に役立つため。
- 例外: intent-cli の dispatcher skill のように、CLI 自身が配布し workflow を再記述しない
  ものは、この方針とは別枠（配布元がバージョン管理と drift 検出を持っている）。

## Note

ディレクトリスコープ拒否の理由には技術的な誤解が混じっていた可能性がある。
`personal`（`~/.claude/skills/`）が `project`（リポジトリルートの `.claude/skills/`）より
**優先される**という優先順位を勘違いしていた（[Claude Code docs — Where skills live](https://code.claude.com/docs/en/skills.md)）。
方針自体は維持だが、再検討する場合はこの点を踏まえること。

## Source

- memory `skill-scoping-preference`
