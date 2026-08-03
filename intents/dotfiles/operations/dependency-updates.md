---
facets: [decider]
---

# 依存更新の運用

- Status: **Canonical**
- Date: 継続的な運用方針
- Scope: flake input・devshell テンプレート・CI の依存更新

## Context

dependabot が flake input と GitHub Actions の更新を PR として上げる。
2026-08-03 時点で6本が最古 2026-05 から放置されていた。放置の原因は更新自体の難しさではなく、
**個別にマージしてよいかどうかの判断基準が記述されていなかった**こと。

`flake.nix` は本体の input を次のように結線している。

```nix
nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
home-manager.inputs.nixpkgs.follows = "nixpkgs";
agenix.inputs.nixpkgs.follows = "nixpkgs";
```

## Decision

**dependabot は検知に使う。マージは「連動する単位」ごとにまとめて自前 PR で行う。**

更新単位は3つあり、互いに独立している。

| 単位 | 対象 | 内部の連動 | 検証手段 |
|---|---|---|---|
| 本体 flake input | `flake.nix` の `nixpkgs` / `nix-darwin` / `home-manager` | **連動する**（`follows` で nixpkgs を共有） | `darwin-switch`（実機） |
| devshell テンプレート | `templates/*/nix/flake.nix` | 独立（テンプレートごとに別 flake） | `nix flake check` |
| CI | `.github/workflows/*` | 独立 | CI 実行 |

**本体 flake input を個別にマージしない。** `follows` があるため、`nixpkgs` だけを 26.05 に上げて
`nix-darwin` を 25.11 に残すと、どちらのリリースでもない中間状態が生まれる。リリース系列は
3本まとめて動かす。

devshell テンプレートと CI は本体と連動しないので、独立した execution unit として先に進めてよい。

## 実機検証の分担 — `build` と `switch` を分ける

**検証の大半は実装用 worktree 内で完結する。** `darwin-rebuild build` と
`darwin-rebuild switch` を区別すること。

| コマンド | システムを変えるか | どこで実行できるか |
|---|---|---|
| `darwin-rebuild build --flake <path>#<host>` | **変えない**（評価とビルドのみ） | `--flake` が引数なので**任意の checkout**。実装用 worktree 内で完結する |
| `darwin-switch`（= `darwin-rebuild switch`） | **変える**（世代が進む） | 本番 checkout（design の作業） |

したがって本体更新の slice は、**実装 worktree で `build` まで検証し**、
`switch` による実機適用だけを design が本番 checkout で行う。受け入れ条件には
`build` の成功を入れ、`switch` は out of scope とする。

`switch` が失敗しても `darwin-rebuild --rollback` で前の世代に戻せる。

> **2026-08-03 実測**: `flake-inputs-2605`（nixpkgs / nix-darwin / home-manager を
> 25.11 → 26.05）で、実装用 worktree からの `darwin-rebuild build --flake .#Yosukes-MacBook-Air`
> が **exit 0** で完走し、受け入れ条件の1つを worktree 内で満たした。
> 同日 `intent-cli` 0.8.1 → 0.9.1 でも同じ方法で事前検証している。
> 以前この節は「`darwin-switch` を通すまで検証が終わらない」と書いていたが、
> それは `build` と `switch` を区別していなかったための誤り。

なお flake が**絶対パス**で本番 checkout を指す箇所は残る
（`nix/hosts/darwin/common/default.nix` の postActivation ほか）。これは `switch` で
配備される symlink の宛先であり、`build` の評価には影響しない。

devshell テンプレートの更新は `nix flake check` で完結するため、この制約を受けない。

## Consequences

- dependabot PR は自前 PR がマージされた後に close する。close 時にどの execution unit が
  代替したかを記録する。
- 更新単位ごとに execution unit を切る。1つの PR に複数の単位を混ぜない。
- リリース系列の更新（例 25.11 → 26.05）は実機検証を伴うため、他の slice と同時に走らせない。

## Related

- [0004 — パッケージの置き場所を用途で決める](../decisions/0004-nix-first-packages.md)
