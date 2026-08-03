# intent-cli-integration — acceptance criteria

> See [overview.md](overview.md) for goals.

## Criteria

### AC-1 — dispatcher skill の配備が再現可能（FR-1）

- [ ] dispatcher skill をどう管理するか決定し、[decisions.md](decisions.md) に記録した
- [ ] `intent-cli skill list` が `claude (user): current` を返す状態を、dotfiles のコードから
      再現できる（新マシンで手作業を要しない）
- [ ] `intent-cli skill diff` による drift 検出が引き続き機能する
      （＝ vendor による二重管理で殺していない）

### AC-2 — 実作業1周の完了（FR-2）

- [ ] packet を1本 draft し、`intent-cli issue publish-flow` で GitHub issue として publish した
- [ ] その issue に対する PR が作られ、`automation base-branch-check --policy direct-main` が
      `ok` を返した（base が `main`）
- [ ] `automation pr-transition` で review-start → approved を通し、merge・`closeout pr` まで到達した
- [ ] `.intent-cli/runs.jsonl` に closeout イベントが記録されている
- [ ] **判断材料が得られている**: 10セクションの issue contract が dotfiles の粒度に対して
      妥当だったか過剰だったかを、実測にもとづいて [open-questions.md](open-questions.md) の
      OQ-2 に回答として書いた

### AC-3 — 4スレッド配置の確定（FR-3）

- [ ] review-runtime の置き場所が決まり、`intent-cli automation host-review-preflight` が通る
- [ ] child worktree が作成でき、その中に `.intent-cli/` が**存在しない**ことを確認した（G300）
- [ ] transport（agmsg / herdr-only）を決定し、`intent-cli session-layer set` で記録した

### AC-4 — 既存原則の非破壊（NFR-1〜3）

- [ ] `main` の tree に `.intent-cli/` と `intents/` が存在しない
- [ ] intent tree に秘密の値が含まれていない
- [ ] private overlay 無しでも `darwin-switch` が通る（public flake の自己完結性が保たれている）

## Verification

```bash
# AC-1
intent-cli skill list
intent-cli skill diff --target claude --scope user

# AC-3 / AC-4（host 側 = main-metadata の worktree から）
intent-cli intent host-check --domain dotfiles --format json
intent-cli intent lint-layout --domain dotfiles
intent-cli automation same-repo-metadata-preflight
intent-cli automation doctor --format json

# AC-4（main に metadata が混入していないこと）
git ls-tree -r --name-only main | grep -E '^(\.intent-cli|intents)/' && echo "NG: metadata が main に混入" || echo "OK"
```
