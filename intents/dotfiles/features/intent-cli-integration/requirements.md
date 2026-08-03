# intent-cli-integration — requirements

> See [overview.md](overview.md) for goals.

## Functional requirements

### FR-1 — dispatcher skill の配備を再現可能にする

`intent-cli skill install --target claude --scope user` は
`~/.claude/skills/intent-cli/SKILL.md` に**直接ファイルを書き込む**。これは既存の
skill 4層管理（自作 public = personal-agent-skills repo / 自作 private = dotfiles-private /
外部 lab = vendor + sync / 外部 gist = vendor + sync）の**どれにも該当しない第5パターン**で、
現状 dotfiles の管理外にある。新マシンのセットアップで入れ忘れる経路が存在する。

満たすべきこと:

- `darwin-switch` 後に dispatcher skill が存在する状態が、dotfiles のコードから再現できる
- ただし [ADR 0002](../../decisions/0002-vendor-over-nix-for-skills.md) の vendor 方式を
  機械的に適用してはならない。この skill は CLI 本体に埋め込まれており、
  `intent-cli skill diff` で drift 検出できる。vendor すると intent-cli のバージョン更新と
  二重管理になる（`skill list` が `current` / `update-available` を判定する仕組みを殺す）

### FR-2 — 実作業1周を通して粒度を実測する

dotfiles の実作業に対して packet を1本切り、issue → 実装 → PR → review → merge → closeout を
1周させる。目的は機能ではなく**判断材料の獲得**: child issue contract が要求する10セクション
（Goal / Why This Slice Exists Now / Current Observed State / Accepted Baseline You May Assume /
Target Repo・Path・Part / In Scope / Out Of Scope / Acceptance Criteria / Verification /
Related Links）が dotfiles の作業粒度に対して過剰かどうかを、推測ではなく実測で判断する。

### FR-3 — 4スレッド運用の物理配置を決める

現在 design host（`main-metadata` の worktree）のみ存在する。公式の役割分担では
review-runtime は独立した checkout を持ち、child は per-issue worktree として作られる。

満たすべきこと:

- review-runtime をどこに置くか決まっている
- child worktree の作成場所が決まっている（`config.toml` の
  `worktree_root = ".intent-cli/worktrees"` は host 側の相対パスであり、
  トポロジー B で orphan ブランチ上にあることの帰結を確認する必要がある）
- transport（agmsg / herdr-only）をどちらにするか決まっている

## Non-functional requirements

- **NFR-1（[ADR 0001](../../decisions/0001-public-private-split.md) の保全）**:
  public flake は private アクセスなしで評価できる状態を保つ。intent-cli 導入によって
  この性質を壊さない。
- **NFR-2（[ADR 0001](../../decisions/0001-public-private-split.md) の保全）**: host metadata は
  public ブランチ `main-metadata` に置かれ、誰にでも見える。秘密の値を intent tree に書かない
  （秘密は agenix に集約する）。
- **NFR-3**: `main` に metadata が混入しない。実装 PR の diff に `.intent-cli/` や `intents/` が
  現れてはならない（トポロジー B を採用した理由そのもの）。
- **NFR-4**: intent-cli のバージョン更新が手順として成立している。custom derivation は
  version と sha256 を手で上げる必要があり、リリース頻度が高い（v0.7.0 → v0.8.1 が数日）。
