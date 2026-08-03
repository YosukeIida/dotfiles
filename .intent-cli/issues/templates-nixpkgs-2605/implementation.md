# templates-nixpkgs-2605 Implementation Packet

## Goal

devshell テンプレート2本（`templates/node/nix`、`templates/python-uv/nix`）の nixpkgs 参照を
`nixpkgs-25.11-darwin` から `nixpkgs-26.05-darwin` に上げ、`flake.lock` を再生成する。
本体 flake には一切触れない。

## Why

dependabot PR #10 / #11 が 2026-06-01 から放置されていた。原因は更新内容ではなく
更新単位の判断基準が不在だったことで、それを `operations/dependency-updates.md` に定めた。
その結果このテンプレート2本は本体と `follows` 連動を持たない独立単位と確定したので、
実機検証（`darwin-switch`）を要する本体更新と切り離して先に進められる。

この domain における**最初の execution unit** でもある。4スレッド運用を一周させ、
issue contract の粒度が dotfiles の規模に妥当かを実測する題材として選んだ。

## Scope

- `templates/node/nix/flake.nix` の `nixpkgs.url` を `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` へ。
- `templates/python-uv/nix/flake.nix` に同一の変更。
- 両方の `flake.lock` を再生成。
- 各テンプレートで devshell が評価できることの確認。

## Out of scope

- リポジトリ直下の `flake.nix` / `flake.lock`（本体の input 更新は別 execution unit）。
- `templates/mcp`（nix flake を持たない）。
- dependabot PR #10 / #11 の close（host 側の後処理）。
- `darwin-switch` の実行。

## 設計判断

**2つのテンプレートを1つの execution unit にまとめた。** dependabot は PR を2本に分けているが、
両者の diff は完全に一致しており（実測で確認）、変更内容は「同じ1行を2箇所に適用する」だけである。
分けると PR が2本・レビューが2回・closeout が2回になり、得られるものがない。

**`flake.lock` だけを更新しない。** dependabot の diff は `flake.nix` の `nixpkgs.url` と
`flake.lock` の `original.ref` / `locked.rev` の両方を含む。`flake.lock` だけ書き換えると
`flake.nix` の宣言と lock の実体が食い違い、次に誰かが `nix flake update` を打った時点で
25.11 系に巻き戻る。**`flake.nix` を先に書き換え、そのうえで lock を再生成する**こと。

**境界の証明を受け入れ条件に入れた。** 本体 flake に差分が出ていないことを
`git diff --name-only origin/main -- flake.nix flake.lock` が空であることで示す。
更新単位を分割した意味が、PR の形で検証できる状態になる。

## 実装手順

```bash
# 1. flake.nix を書き換える（2箇所とも）
#    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
#  → nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

# 2. それぞれの lock を再生成する（コマンド形式は導入済み nix のバージョンに従う）
cd templates/node/nix      && nix flake update
cd ../../python-uv/nix     && nix flake update
```

`nix flake update` は当該 flake の全 input を更新するが、どちらのテンプレートも input は
`nixpkgs` 1つだけなので副作用はない。

## Verification

```bash
# devshell が評価できること（どちらを使ったか PR に書く）
cd templates/node/nix      && nix flake check   # 重い場合: nix develop --command true
cd templates/python-uv/nix && nix flake check   # 同上

# 更新単位の境界（出力が空であることが期待値）
git diff --name-only origin/main -- flake.nix flake.lock

git diff --check
```

`nix flake check` は nixpkgs 26.05 の評価を伴うため初回はダウンロードで時間がかかる。
完走しない場合は `nix develop --command true` で devshell の起動を示せば受け入れ条件を満たす。
どちらを使ったかを PR に明記すること（レビュアーが同じ手段で追試する）。

## Knowledge Maintenance (G461, optional)

Captured while the design context is fresh. Answer or explicitly decline:

- Intent placement: `intents/dotfiles/operations/dependency-updates.md`（この packet と同じ wake で
  新設した。本 slice はその最初の適用例）。supporting: `decisions/0004-nix-first-packages.md`。
- ADR candidate: **decline**。更新単位の分割という判断は上記 operations ノードに記録済みで、
  横断的な ADR を起こすほどの射程を持たない。
- Diagram candidate: **decline**。
- Docs update: **decline**。`templates/node` と `templates/python-uv` に README はなく、
  nixpkgs のリリース系列に言及する docs も存在しない（`grep -rln "25.11" --include="*.md"` で確認）。
- Closeout learning: **write_back_required: true**。
  `intents/dotfiles/features/intent-cli-integration/open-questions.md` の OQ-2
  （issue contract 13セクションの粒度が dotfiles に妥当か）へ、この一周の実測をもとに回答する。

`improve` (G456 / G460) is the later safety net; packet-time maintenance is the normal path.
