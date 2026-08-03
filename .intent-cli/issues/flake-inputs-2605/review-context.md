# flake-inputs-2605 Review Context

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

1. **3本が揃って上がっているか** — `nixpkgs` / `nix-darwin` / `home-manager` の3つ。
   1本でも 25.11 が残っていれば中間状態なので request-update。
2. **`nixpkgs-unstable` が動いていないか（この slice で最も重要な確認点）** —
   `flake.lock` の unstable エントリの `locked.rev` に差分が無いこと。動いていると
   「26.05 で壊れたのか unstable で壊れたのか」の切り分けができなくなる。受け入れ条件に
   これを入れたのは切り分け可能性を PR の形で保証するため。
3. **stateVersion が無変更か** — `home.stateVersion` / `system.stateVersion`。
   リリース系列とは別の軸なので、一緒に動かすと失敗原因が切り分けられなくなる。
4. **build の結果が記載されているか** — `darwin-rebuild build --flake .#Yosukes-MacBook-Air`
   が完走したか、warning が出たならその内容。記載が無ければ「検証の証跡が不十分」として
   request-update。この slice ではローカルで確認できる唯一の実質的な検証手段である。
5. **範囲外の修正が混ざっていないか** — 26.05 への追随修正は条件付きで範囲内だが、
   **根拠が PR に明記されていること**が条件。根拠なき差分は request-update。

## scope 拡大の兆候（見つけたら request-update）

- `nixpkgs-unstable` の rev 変更（`nix flake update` を無指定で打った跡）。
- stateVersion の変更。
- `templates/**` / `.github/**` への差分（いずれも別 execution unit で完了済み）。
- パッケージの追加・削除、設定内容の変更。
- `darwin-switch` を実行した跡（実機適用は host 側の作業）。
- dependabot PR #8 / #9 / #12 を PR 側から close しようとしている。

## blocked が正しい場合

build 失敗の原因が設計判断を要するとき（パッケージが 26.05 で削除され代替の選択が必要、
option の意味が変わって移行方法で挙動が変わる、unstable から引いているパッケージとの整合が
崩れた等）、implementer が推測で修正するのは誤り。**blocked での報告が正しい対応**であり、
その場合はレビューではなく design の判断に回す。

## design alignment の根拠

`intents/dotfiles/operations/dependency-updates.md` が更新単位を3つに分け、本体 flake input を
「`follows` で連動するのでまとめて上げる」単位と定め、実機検証の分担も記述している。
この slice はその3単位のうち最後（本体）に対応する。承認サマリではこのノードを引用し、
連動単位を守っていること・実機適用を含んでいないことを述べること。
