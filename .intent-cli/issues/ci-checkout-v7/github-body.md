## Goal

`.github/workflows/nix-check.yml` が使っている `actions/checkout` のピンを `@v6` から `@v7`
に上げる。対象は同ファイル内の2ジョブ（`nix` と `secrets`）の計2行。

## Why This Slice Exists Now

`operations/dependency-updates.md` が更新単位を「本体 flake input / devshell テンプレート / CI」
の3つに分け、CI は他と連動しない独立単位と定めている。本体 flake の更新（`darwin-switch` の
実機検証が必要）を待つ理由がないので、単独で先に上げられる。

dependabot PR #14 が 2026-07-01 から open のまま放置されている。

## Current Observed State

`.github/workflows/nix-check.yml` の13行目と25行目が `- uses: actions/checkout@v6` を指している。
リポジトリ内で `actions/checkout` を参照しているのはこの2箇所だけ。

## Accepted Baseline You May Assume

- CI は `operations/dependency-updates.md` の3つの更新単位のうち独立した1つで、本体 flake input
  とは `follows` などの連動を持たない。
- ワークフローのラベル遷移は `intent-cli worker` 経由でのみ行う（生の `gh` でラベルを編集しない）。
- host metadata（`.intent-cli/**` / `intents/**`）は読まない。この issue 本文が契約の全体である。
- `intent-cli` は AI provider を起動しない。

## Target Repo / Path / Part

Repository: `YosukeIida/dotfiles`

Target paths: `.github/workflows/nix-check.yml`

Target part: `nix-check ワークフローの actions/checkout ピン（2箇所）`

## In Scope

- `.github/workflows/nix-check.yml` の `actions/checkout@v6` を2箇所とも `@v7` に変更する。

## Out Of Scope

- 同ファイル内の他の action（`cachix/install-nix-action` 等）のバージョン変更。
- 他のワークフローファイル、および `.github/` 以外のすべて。
- 本体 flake input（`nixpkgs` / `nix-darwin` / `home-manager`）の更新。別 execution unit。
- dependabot PR #14 の close。host 側の後処理として design が行う。
- ジョブ構成・トリガ条件・runner の変更。

## Standalone Child Issue Contract

この PR が届けるものは、`.github/workflows/nix-check.yml` 内の `actions/checkout@v6` を2箇所
とも `actions/checkout@v7` に置き換えた差分のみである。他のファイル・他の action には触れない。
PR の CI（`nix` と `secrets` の両ジョブ）が green であることを確認し、PR 本文に
`Closes #<issue>` を含め、base branch は `main` とする。

## Acceptance Criteria

- `.github/workflows/nix-check.yml` の `actions/checkout` 参照が2箇所とも `actions/checkout@v7`
  である。
- リポジトリ内に `actions/checkout@v6` への参照が残っていない
  （`grep -rn "actions/checkout@v6" .` が空）。
- PR の CI が green である（`nix` ジョブと `secrets` ジョブの両方）。**この slice では CI 実行
  そのものが検証手段**であり、変更した action が実際に動くことを示す唯一の証拠になる。
- `.github/workflows/nix-check.yml` 以外に差分がない。
- PR 本文に `Closes #<issue>` がある。

## Verification

```bash
# 1. 2箇所とも v7 になっていること（2行出ることが期待値）
grep -n "actions/checkout@v7" .github/workflows/nix-check.yml

# 2. v6 が残っていないこと（出力が空であることが期待値）
grep -rn "actions/checkout@v6" . --exclude-dir=.git

# 3. 差分がこのファイルだけであること
git diff --name-only origin/main

git diff --check
```

CI は PR を開いた時点で自動実行される。`gh pr checks <n>` で結果を確認し、両ジョブが green
になったことを PR に記載すること。

## Related Links

- `intents/dotfiles/operations/dependency-updates.md` — 更新単位の分割（CI は独立単位）
- 先行 slice: `templates-nixpkgs-2605`（devshell テンプレートの更新単位。issue #20 / PR #21）
- dependabot PR #14 — この slice が代替する

## Knowledge Maintenance

Optional (G461). Tells the implementer/reviewer whether intent / ADR / diagram / docs
writeback is expected for this slice. Answer or explicitly decline:

- Intent placement: `intents/dotfiles/operations/dependency-updates.md`（3単位のうち「CI」の最初の適用例）
- ADR candidate: none — 判断は上記 operations ノードに記録済み
- Diagram candidate: none
- Docs update: none — checkout のバージョンに言及する docs は存在しない
- Closeout writeback expected: yes — `open-questions.md` の OQ-2 に、最小規模（1ファイル2行）に
  対する contract の妥当性と、2周目の所要（初回 gate が消えた状態）を追記する

## Base Branch Policy

Policy: `direct-main`
Expected PR base branch: `main`

Open all child PRs against `main` directly.
