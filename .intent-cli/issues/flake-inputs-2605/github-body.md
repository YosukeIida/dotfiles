## Goal

本体 flake の `nixpkgs` / `nix-darwin` / `home-manager` を 25.11 系から 26.05 系へまとめて上げ、
`flake.lock` を更新する。3本は `follows` で連動しているため、同じ PR で一度に動かす。

## Why This Slice Exists Now

dependabot PR #8（nix-darwin）/ #9（nixpkgs）/ #12（home-manager）が 2026-05 から放置されている。
放置の原因は更新内容ではなく、**個別にマージしてよいかの判断基準が無かった**こと。
`intents/dotfiles/operations/dependency-updates.md` がその基準を定め、この3本は
「連動する1つの更新単位」であると確定した。個別にマージすると

- `flake.nix` と `flake.lock` の同じファイルを3本が触るため、1本 merge した時点で残りが conflict する
- `follows` で nixpkgs を共有しているため、どちらのリリースでもない中間状態が生まれる

## Current Observed State

`flake.nix` の inputs:

```nix
nixpkgs.url          = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";   # ref なし・常に最新
nix-darwin.url       = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
home-manager.url     = "github:nix-community/home-manager/release-25.11";
agenix.url           = "github:ryantm/agenix";                     # ref なし
```

`nix-darwin` / `home-manager` / `agenix` はいずれも `inputs.nixpkgs.follows = "nixpkgs"`。
`home.stateVersion = "25.11"`（`nix/home/default.nix`）、`system.stateVersion = 6`
（`nix/hosts/darwin/common/default.nix`）。

## Accepted Baseline You May Assume

- この3本は連動する1つの更新単位である（`operations/dependency-updates.md` の決定）。
- **`nixpkgs-unstable` はこの slice の範囲外**。ref を持たないので `nix flake update` を
  無指定で実行すると一緒に動いてしまう。input を明示して更新すること。
- **stateVersion は変更しない**。これは後方互換のマーカーであり、リリース系列の移行で
  上げるものではない。
- **検証は `darwin-rebuild build` で行う**。`build` はシステムを変更しないので、この
  worktree 内で完結する。実機適用（`switch`）は host 側の作業でこの PR の範囲外。
- ワークフローのラベル遷移は `intent-cli worker` 経由でのみ行う。
- host metadata（`.intent-cli/**` / `intents/**`）は読まない。この issue 本文が契約の全体である。

## Target Repo / Path / Part

Repository: `YosukeIida/dotfiles`

Target paths: `flake.nix flake.lock`

Target part: `本体 flake の nixpkgs / nix-darwin / home-manager のリリース系列`

## In Scope

- `flake.nix` の3つの url を 26.05 系に変更する。
  - `nixpkgs` → `github:NixOS/nixpkgs/nixpkgs-26.05-darwin`
  - `nix-darwin` → `github:nix-darwin/nix-darwin/nix-darwin-26.05`
  - `home-manager` → `github:nix-community/home-manager/release-26.05`
- `flake.lock` を**この3つの input に限って**更新する（`nix flake update nixpkgs nix-darwin home-manager`）。
- `darwin-rebuild build --flake .#Yosukes-MacBook-Air` が通ることを確認する。
- 26.05 での option 改名・パッケージ名変更に追随する修正。**ただし差分と根拠を PR に明記すること。**

## Out Of Scope

- **`nixpkgs-unstable` の更新**（ref を持たないので明示的に除外する）。
- **stateVersion の変更**（`home.stateVersion` / `system.stateVersion`）。
- `templates/**`（別 execution unit で既に 26.05 へ移行済み）。
- `.github/workflows/**`（別 execution unit で対応済み）。
- **`darwin-switch` の実行**。実機適用は host 側の作業。
- パッケージの追加・削除、設定内容の変更（リリース系列を上げるだけの slice である）。
- dependabot PR #8 / #9 / #12 の close（host 側の後処理）。

## Standalone Child Issue Contract

この PR が届けるものは、`flake.nix` の3つの input url を 26.05 系に書き換え、その3つに限って
`flake.lock` を更新した差分である。`nixpkgs-unstable` の locked.rev は変えない。
`darwin-rebuild build --flake .#Yosukes-MacBook-Air` が通ることを確認し、その結果を PR に記載する。
26.05 で option 名やパッケージ名が変わっていて追随が必要な場合は、その修正を含めてよいが、
変更した箇所と根拠を PR 本文に明記する。build が通らず原因が判断を要する場合は、修正を推測で
進めず blocked として報告する。PR 本文に `Closes #<issue>` を含め、base branch は `main`。

## Acceptance Criteria

- `flake.nix` の `nixpkgs.url` が `nixpkgs-26.05-darwin`、`nix-darwin.url` が `nix-darwin-26.05`、
  `home-manager.url` が `release-26.05` を指している。
- `flake.lock` でこの3つの `original.ref` が更新され、`locked.rev` が 25.11 系の値から変わっている。
- **`flake.lock` の `nixpkgs-unstable` の `locked.rev` が変わっていない**（更新範囲を絞ったことの証明）。
- `darwin-rebuild build --flake .#Yosukes-MacBook-Air` が成功する。失敗した場合は原因と切り分けを
  PR に記載する。
- `home.stateVersion` と `system.stateVersion` が変更されていない。
- `flake.nix` と `flake.lock` 以外に差分がない。ただし 26.05 での option 改名・パッケージ名変更への
  追随が必要な場合は、その差分と根拠を PR に明記すれば範囲内とする。
- PR 本文に `Closes #<issue>` がある。

## Verification

```bash
# 1. flake.nix の3つの ref
grep -nE 'nixpkgs-26\.05-darwin|nix-darwin-26\.05|release-26\.05' flake.nix   # 3行出る

# 2. nixpkgs-unstable が動いていないこと（差分に unstable の rev 変更が含まれないこと）
git diff origin/main -- flake.lock | grep -A3 -B3 'nixpkgs-unstable' || echo "unstable に差分なし"

# 3. stateVersion が無変更
git diff origin/main -- nix/home/default.nix nix/hosts/darwin/common/default.nix   # 出力が空

# 4. ビルド検証（システムは変更されない）
darwin-rebuild build --flake .#Yosukes-MacBook-Air

# 5. 差分の範囲
git diff --name-only origin/main
git diff --check
```

`darwin-rebuild build` は nixpkgs 26.05 の評価と大量のビルドを伴うため、初回は時間がかかる。
完走したかどうかと、warning が出た場合はその内容を PR に記載すること。

## Related Links

- `intents/dotfiles/operations/dependency-updates.md` — 更新単位の分割と実機検証の分担
- 先行 slice: `templates-nixpkgs-2605`（devshell テンプレート。issue #20 / PR #21）、
  `ci-checkout-v7`（CI。issue #22 / PR #23）
- dependabot PR #8 / #9 / #12 — この slice が代替する

## Knowledge Maintenance

Optional (G461). Tells the implementer/reviewer whether intent / ADR / diagram / docs
writeback is expected for this slice. Answer or explicitly decline:

- Intent placement: `intents/dotfiles/operations/dependency-updates.md`（3単位のうち「本体 flake input」の最初の適用例）
- ADR candidate: none — 判断は上記 operations ノードに記録済み
- Diagram candidate: none
- Docs update: none — リリース系列に言及する docs は存在しない
- Closeout writeback expected: yes — `operations/dependency-updates.md` の「実機検証の分担」を、
  `build`（worktree 内で完結）と `switch`（本番のみ）の区別を含む形に更新する

## Base Branch Policy

Policy: `direct-main`
Expected PR base branch: `main`

Open all child PRs against `main` directly.
