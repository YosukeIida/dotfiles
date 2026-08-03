# templates-nixpkgs-2605 Review Context

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
- `operations/dependency-updates` [decider] 依存更新の運用 — `intents/dotfiles/operations/dependency-updates.md`
### acceptance-property
- (none overlapping this packet's intent_references)
<!-- END GENERATED FACET CONTEXT (G530) -->

## この slice で引用すべき packet↔PR delta

レビューの承認サマリで、以下を具体的に引用すること。

1. **更新単位の境界（この slice で最も重要な確認点）** — `git diff --name-only origin/main -- flake.nix flake.lock`
   が空であること。この slice は「本体 flake input（`follows` で連動する3本）とテンプレート
   （独立）は別の更新単位である」という判断そのものを検証している。本体に1行でも差分が出ていれば、
   分割した意味が失われるので request-update とする。
2. **`flake.nix` と `flake.lock` の整合** — `flake.nix` の `nixpkgs.url` と `flake.lock` の
   `original.ref` が両方 `nixpkgs-26.05-darwin` を指していること。lock だけが更新されていて
   `flake.nix` が 25.11 のままなら、次の `nix flake update` で巻き戻るので不合格。
   逆に `flake.nix` だけ更新されて lock が古いままでも不合格。
3. **2ディレクトリ両方に適用されていること** — `templates/node/nix` と `templates/python-uv/nix`。
   片方だけなら scope の取りこぼし。
4. **検証手段の明示と追試** — 実装者が `nix flake check` と `nix develop --command true` の
   どちらを使ったかが PR に書かれていること。書かれていなければ「tests-pass の証跡が不十分」
   として request-update。書かれていれば同じ手段で追試する。

## scope 拡大の兆候（見つけたら request-update）

- リポジトリ直下の `flake.nix` / `flake.lock` への差分。
- `templates/mcp` への変更（nix flake を持たないので対象外）。
- dependabot PR #10 / #11 を PR 側から close しようとしている（host 側の後処理であり、
  implementation の権限範囲外）。
- テンプレートが提供するパッケージ構成そのものの変更（リリース系列を上げるだけの slice である）。
- `darwin-switch` の実行や、本番環境に触れる操作。

## design alignment の根拠

`intents/dotfiles/operations/dependency-updates.md`（上の facet context に列挙されている
decider ノード）が、更新単位を「本体 flake input / devshell テンプレート / CI」の3つに分ける
根拠と、それぞれの検証手段を定めている。この slice はそのうち2番目の単位に対応する最初の適用例。
承認サマリではこのノードを引用し、slice が単位の境界を守っていることを述べること。

## Knowledge Writeback Expectation (G461)

If the packet's `closeout_learning.write_back_required` is `true`, confirm the
expected intent-tree / ADR / diagram / docs writeback landed in this PR or was
captured as a follow-up packet. If the packet declined all knowledge maintenance,
that is acceptable — note it rather than blocking.