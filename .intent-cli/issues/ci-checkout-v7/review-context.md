# ci-checkout-v7 Review Context

Review that this slice moves operation toward the documented intent without widening scope.

Flag findings if the implementation:

- widens scope beyond the issue contract;
- launches AI providers from `intent-cli`;
- mutates GitHub or parent state when the issue is read-only;
- skips required contract sections.

## Facet context

<!-- BEGIN GENERATED FACET CONTEXT (G530) -->
### vocabulary
- (none overlapping this packet's intent_references)
### invariant
- (none overlapping this packet's intent_references)
### decider
- (none overlapping this packet's intent_references)
### acceptance-property
- (none overlapping this packet's intent_references)
<!-- END GENERATED FACET CONTEXT (G530) -->

## Knowledge Writeback Expectation (G461)

If the packet's `closeout_learning.write_back_required` is `true`, confirm the
expected intent-tree / ADR / diagram / docs writeback landed in this PR or was
captured as a follow-up packet. If the packet declined all knowledge maintenance,
that is acceptable — note it rather than blocking.
## この slice で引用すべき packet↔PR delta

1. **2箇所とも上がっているか** — `nix` ジョブと `secrets` ジョブの両方。片方だけなら取りこぼし。
2. **v6 が残っていないか** — `grep -rn "actions/checkout@v6" . --exclude-dir=.git` が空であること。
3. **CI が green か（この slice では最重要）** — 変更対象が CI の定義そのものなので、
   CI 実行が「変更した action が実際に動く」ことを示す唯一の証拠。`gh pr checks` の結果を
   PR に記載しているかを確認し、記載がなければ「検証の証跡が不十分」として request-update。
4. **差分が当該ファイルだけか** — 他の action のバージョンを一緒に上げていないこと。

## scope 拡大の兆候（見つけたら request-update）

- 同ファイル内の他の action（`cachix/install-nix-action` 等）のバージョン変更。
- 他のワークフローファイルへの変更。
- ジョブ構成・トリガ条件・runner の変更。
- 本体 flake input への差分（別 execution unit）。
- dependabot PR #14 を PR 側から close しようとしている（host 側の後処理であり権限範囲外）。

## design alignment の根拠

`intents/dotfiles/operations/dependency-updates.md` が更新単位を3つに分け、CI を独立単位と
定めている。この slice はそのうち「CI」に対応する最初の適用例。承認サマリではこのノードを
引用し、単位の境界を越えていないことを述べること。
