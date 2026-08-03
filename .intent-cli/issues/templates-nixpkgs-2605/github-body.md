## Goal

devshell テンプレート2本（`templates/node/nix` と `templates/python-uv/nix`）の nixpkgs を
`nixpkgs-25.11-darwin` から `nixpkgs-26.05-darwin` に上げる。テンプレートから新規プロジェクトに
配る devshell が、現行のリリース系列を指すようになる。

## Why This Slice Exists Now

dependabot PR #10 / #11 が 2026-06-01 から3ヶ月間 open のまま放置されている。放置の原因は
更新内容の難しさではなく、「どの単位でマージしてよいか」の判断基準が記述されていなかったこと。
その判断基準を `intents/dotfiles/operations/dependency-updates.md` に定めた結果、
**このテンプレート2本は本体 flake と `follows` による連動を持たない独立した更新単位**である
ことが確定したので、本体の更新（実機検証が必要でリスクが高い）を待たずに単独で進められる。

## Current Observed State

- `templates/node/nix/flake.nix` と `templates/python-uv/nix/flake.nix` の両方が
  `nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin"` を指している。
- それぞれの `flake.lock` は `original.ref = nixpkgs-25.11-darwin`、
  `locked.rev = 40c50ee301a50280389c4673f021fc24e639f141` に固定されている。
- dependabot PR #10 と #11 が同一の変更を提案している（両者の diff を取ると完全に一致する）。

## Accepted Baseline You May Assume

- `templates/*/nix` の flake はリポジトリ直下の `flake.nix` とは独立しており、`follows` による
  input 共有を持たない。テンプレート側だけを更新しても本体には影響しない。
- 本体の flake input（`nixpkgs` / `nix-darwin` / `home-manager`）の更新は別の execution unit に
  分離済み。この issue で触る必要はない。
- ワークフローのラベル遷移は `intent-cli worker` 経由でのみ行う（生の `gh` でラベルを編集しない）。
- host metadata（`.intent-cli/**` / `intents/**`）は読まない。この issue 本文が契約の全体である。
- `intent-cli` は AI provider を起動しない。

## Target Repo / Path / Part

Repository: `YosukeIida/dotfiles`

Target paths: `templates/node/nix templates/python-uv/nix`

Target part: `devshell テンプレート2本の flake input（本体 flake は対象外）`

## In Scope

- `templates/node/nix/flake.nix` の `nixpkgs.url` を `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` に変更する。
- `templates/python-uv/nix/flake.nix` に同じ変更を適用する。
- 両方の `flake.lock` を再生成する（`nix flake update`）。
- 各テンプレートで devshell が評価できることを確認する。

## Out Of Scope

- **リポジトリ直下の `flake.nix` / `flake.lock`**。本体の input 更新は別 execution unit であり、
  ここで触ると更新単位の境界を壊す。
- `templates/mcp`（nix flake を持たない）。
- dependabot PR #10 / #11 の close。これは host 側の後処理として design が行う。
- `darwin-switch` の実行。このテンプレート更新は本番環境に影響しない。
- テンプレートが提供するパッケージ構成の変更（バージョン系列を上げるだけで、内容は変えない）。

## Standalone Child Issue Contract

この PR が届けるものは、`templates/node/nix` と `templates/python-uv/nix` の2つのディレクトリ内で、
`flake.nix` の nixpkgs 参照を `nixpkgs-26.05-darwin` に書き換え、対応する `flake.lock` を
再生成した差分のみである。両テンプレートで devshell が評価できることを確認し、その出力を PR に
記載する。リポジトリ直下の `flake.nix` / `flake.lock` には一切差分を出さない。PR 本文に
`Closes #<issue>` を含め、base branch は `main` とする。

## Acceptance Criteria

- `templates/node/nix/flake.nix` と `templates/python-uv/nix/flake.nix` の `nixpkgs.url` が
  `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` を指している。
- 両方の `flake.lock` で nixpkgs の `original.ref` が `nixpkgs-26.05-darwin` に更新され、
  `locked.rev` が `40c50ee301a50280389c4673f021fc24e639f141` から変わっている。
- 各テンプレートディレクトリで `nix flake check` が成功する（評価が重すぎる場合は
  `nix develop --command true` が成功することを示してもよい）。どちらを使ったかを PR に書く。
- リポジトリ直下の `flake.nix` と `flake.lock` に差分がない。
- PR 本文に `Closes #<issue>` がある。

## Verification

```bash
# 1. 各テンプレートで devshell が評価できること（どちらか一方を使い、使った方を PR に記載）
cd templates/node/nix       && nix flake check   # 重い場合: nix develop --command true
cd templates/python-uv/nix  && nix flake check   # 同上

# 2. 更新単位の境界を越えていないこと（何も出力されないことが期待値）
git diff --name-only origin/main -- flake.nix flake.lock

# 3. 差分の衛生
git diff --check
```

## Related Links

- `intents/dotfiles/operations/dependency-updates.md` — 依存更新の運用方針（更新単位の分割根拠）
- `intents/dotfiles/decisions/0004-nix-first-packages.md` — パッケージの置き場所の方針
- dependabot PR #10（`templates/node/nix`）と #11（`templates/python-uv/nix`）— この slice が代替する

## Knowledge Maintenance

Optional (G461). Tells the implementer/reviewer whether intent / ADR / diagram / docs
writeback is expected for this slice. Answer or explicitly decline:

- Intent placement: `intents/dotfiles/operations/dependency-updates.md`（この slice の最初の適用例）
- ADR candidate: none — 判断は上記の operations ノードに記録済みで、横断 ADR は起こさない
- Diagram candidate: none
- Docs update: none — `templates/node` と `templates/python-uv` に README はなく、nixpkgs の
  リリース系列に言及する docs も存在しない（grep で確認済み）
- Closeout writeback expected: yes — `intents/dotfiles/features/intent-cli-integration/open-questions.md`
  の OQ-2（issue contract の粒度が dotfiles に妥当か）に、この一周の実測をもとに回答する

## Base Branch Policy

Policy: `direct-main`
Expected PR base branch: `main`

Open all child PRs against `main` directly.
