# ci-checkout-v7 Implementation Packet

## Goal

`.github/workflows/nix-check.yml` の `actions/checkout` ピンを2箇所とも `@v6` → `@v7` に上げる。

## Why

`operations/dependency-updates.md` の3つの更新単位のうち「CI」は独立単位であり、本体 flake
input の更新（`darwin-switch` の実機検証が必要）を待つ理由がない。dependabot PR #14 が
2026-07-01 から放置されている。

この domain の**2周目**の execution unit でもある。1周目（`templates-nixpkgs-2605`）で
初回のみ必要だった gate（ラベル11本の作成・atomic-seed・title キーの発見）が消えた状態での
所要を測る。

## Scope

- `.github/workflows/nix-check.yml` の `actions/checkout@v6` を2箇所とも `@v7` に変更。

## Out of scope

- 同ファイル内の他の action（`cachix/install-nix-action` 等）。
- 他のワークフロー、`.github/` 以外のすべて。
- 本体 flake input（別 execution unit）。
- dependabot PR #14 の close（host 側の後処理）。

## 設計判断

**この slice を intent-cli のフローに乗せる判断そのものが実測対象である。** 変更は1ファイル
2行で、素直にやれば dependabot PR #14 を merge するだけで済む。それを敢えて packet 化するのは、
OQ-2（「1行修正のような典型作業に13セクション contract は過剰か」）に答えるための計測であり、
この規模が intent-cli を通す下限かどうかを判断する材料を得ることが目的。

**検証手段は CI そのもの。** 他の slice では実装者がローカルでコマンドを走らせて確認するが、
この slice が変更するのは CI の定義自体なので、PR の CI 実行が「変更した action が実際に動く」
ことを示す唯一の証拠になる。ローカルで確認できることは grep による静的な一致だけである。

## 実装手順

```bash
# 2箇所（nix ジョブ 13行目 / secrets ジョブ 25行目）
#   - uses: actions/checkout@v6
# → - uses: actions/checkout@v7
```

## Verification

```bash
grep -n "actions/checkout@v7" .github/workflows/nix-check.yml   # 2行出る
grep -rn "actions/checkout@v6" . --exclude-dir=.git             # 空
git diff --name-only origin/main                                # 当該ファイルのみ
git diff --check
gh pr checks <n>                                                # nix / secrets が両方 green
```

## Knowledge Maintenance (G461, optional)

Captured while the design context is fresh. Answer or explicitly decline:

- Intent placement: `intents/dotfiles/operations/dependency-updates.md`（3単位のうち「CI」の最初の適用例）。
- ADR candidate: **decline**。判断は上記 operations ノードに記録済み。
- Diagram candidate: **decline**。
- Docs update: **decline**。checkout のバージョンに言及する docs は存在しない。
- Closeout learning: **write_back_required: true**。`open-questions.md` の OQ-2 に、
  最小規模（1ファイル2行）に対する contract の妥当性と、初回 gate が消えた2周目の所要を追記する。

`improve` (G456 / G460) is the later safety net; packet-time maintenance is the normal path.
