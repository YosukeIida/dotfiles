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

## 実機検証の分担

本体 flake input の更新は `darwin-switch` を通すまで検証が終わらない。`darwin-switch` は
flake を**絶対パス**で指すため（`nix/hosts/darwin/common/default.nix` ほか多数）、
実装用 worktree からは実行しても本番 checkout の flake を読む。

したがって本体更新の slice は、**実装 worktree では編集と PR までが範囲**であり、
`darwin-switch` による実機検証は design が本番 checkout で行う。受け入れ条件をこの分担に
合わせて書くこと。

devshell テンプレートの更新は `nix flake check` で完結するため、この制約を受けない。

## Consequences

- dependabot PR は自前 PR がマージされた後に close する。close 時にどの execution unit が
  代替したかを記録する。
- 更新単位ごとに execution unit を切る。1つの PR に複数の単位を混ぜない。
- リリース系列の更新（例 25.11 → 26.05）は実機検証を伴うため、他の slice と同時に走らせない。

## Related

- [0004 — パッケージの置き場所を用途で決める](../decisions/0004-nix-first-packages.md)
