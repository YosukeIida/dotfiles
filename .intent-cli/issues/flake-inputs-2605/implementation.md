# flake-inputs-2605 Implementation Packet

## Goal

本体 flake の `nixpkgs` / `nix-darwin` / `home-manager` を 25.11 系から 26.05 系へまとめて上げる。

## Why

dependabot #8 / #9 / #12 が 2026-05 から放置されていた。3本は `follows` で連動しており、
個別 merge は (a) 同一ファイルの conflict、(b) どちらのリリースでもない中間状態、の2つを招く。
`operations/dependency-updates.md` がこれを「連動する1つの更新単位」と定めた。

3つの更新単位（本体 / テンプレート / CI）のうち、**最後に残った本体**にあたる。
テンプレート（`templates-nixpkgs-2605`）と CI（`ci-checkout-v7`）は既に完了している。

## Scope

- `flake.nix` の3つの url を 26.05 系に。
- `flake.lock` を**その3つに限って**更新。
- `darwin-rebuild build` で検証。
- 26.05 での option / パッケージ名変更への追随（差分と根拠を PR に明記する条件付き）。

## Out of scope

- `nixpkgs-unstable` の更新、stateVersion の変更、`templates/**`、`.github/**`、
  `darwin-switch` の実行、dependabot PR の close。

## 設計判断

**3本を1つの execution unit にした。** `nix-darwin.inputs.nixpkgs.follows = "nixpkgs"` と
`home-manager.inputs.nixpkgs.follows = "nixpkgs"` があるため、リリース系列は3本セットで
動かす以外に整合する状態がない。dependabot が3本に分けているのはツールの都合であり、
更新単位の実体ではない。

**`nixpkgs-unstable` を明示的に除外した。** この input は ref を持たず常に最新を指すので、
`nix flake update` を無指定で打つと一緒に動く。そうなると「26.05 への移行で壊れたのか、
unstable が動いて壊れたのか」の切り分けができなくなる。受け入れ条件に
「unstable の locked.rev が変わっていないこと」を入れたのは、この切り分け可能性を
PR の形で保証するため。

**stateVersion を触らない。** `home.stateVersion` と `system.stateVersion` は
「この設定がどのバージョンの既定を前提に書かれたか」を示す後方互換のマーカーで、
リリース系列とは別の軸。上げると既定値の変更が一斉に効いて、移行の失敗原因が
リリース系列か stateVersion か切り分けられなくなる。

**検証を `build` にした。** `darwin-rebuild build` はシステムを変更せず、評価と
ビルドだけを行う。`--flake <path>` は引数なので、この worktree の flake を指定して
実行できる。実機適用（`switch`）だけが本番 checkout の作業として残る。
`operations/dependency-updates.md` の現在の記述は switch のみを前提にしているので、
この slice の closeout でその区別を書き足す。

## 実装手順

```bash
# 1. flake.nix の3行を書き換える
#   nixpkgs.url      → github:NixOS/nixpkgs/nixpkgs-26.05-darwin
#   nix-darwin.url   → github:nix-darwin/nix-darwin/nix-darwin-26.05
#   home-manager.url → github:nix-community/home-manager/release-26.05

# 2. lock を「この3つに限って」更新する（nix 2.31.5 なので input 指定が使える）
nix flake update nixpkgs nix-darwin home-manager

# 3. ビルド検証（システムは変わらない）
darwin-rebuild build --flake .#Yosukes-MacBook-Air
```

## build が失敗した場合の扱い

26.05 で option が改名された・パッケージ名が変わった、という類の失敗は**この slice の
範囲内**なので修正してよい。ただし変更箇所と根拠（26.05 の release notes / nixpkgs の
該当 commit など）を PR 本文に明記すること。

一方、**修正に設計判断が必要な場合は推測で進めず blocked で報告する。** 例:

- あるパッケージが 26.05 で削除され、代替の選択が必要になった
- option の意味が変わり、どう移行するかで挙動が変わる
- unstable から引いているパッケージ（`agent-browser` 等）との整合が崩れた

これらは「リリース系列を上げる」slice の範囲を超えており、design の判断が必要。

## Verification

```bash
grep -nE 'nixpkgs-26\.05-darwin|nix-darwin-26\.05|release-26\.05' flake.nix   # 3行
git diff origin/main -- flake.lock | grep 'nixpkgs-unstable' || echo "unstable 無変更"
git diff origin/main -- nix/home/default.nix nix/hosts/darwin/common/default.nix  # 空
darwin-rebuild build --flake .#Yosukes-MacBook-Air
git diff --name-only origin/main
git diff --check
```

## Knowledge Maintenance (G461, optional)

- Intent placement: `intents/dotfiles/operations/dependency-updates.md`（3単位のうち「本体」）。
- ADR candidate: **decline**。判断は上記 operations ノードに記録済み。
- Diagram candidate: **decline**。
- Docs update: **decline**。リリース系列に言及する docs は無い。
- Closeout learning: **write_back_required: true**。`operations/dependency-updates.md` の
  「実機検証の分担」を、`build`（worktree 内で完結）と `switch`（本番のみ）の区別を含む
  形に更新する。現在の記述は switch のみを前提にしている。

`improve` (G456 / G460) is the later safety net; packet-time maintenance is the normal path.
