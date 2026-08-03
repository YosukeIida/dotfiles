---
facets: [decider]
---

# 0004 — パッケージの置き場所を用途で決める（言語別グローバル install を使わない）

- Status: **Canonical**
- Date: 継続的な運用方針
- Scope: パッケージ導入先の判断

## Context

ツールを入れる手段が複数ある（nix / homebrew / devshell / 言語別パッケージマネージャの
グローバル install）。場当たりに選ぶと、環境がどこから来たか追跡できなくなる。

## Decision

**用途で置き場所を決める。言語別のグローバル install は使わない。**

| 用途 | 置き場所 |
|---|---|
| グローバル CLI ツール | `nix/home/packages.nix` の `home.packages` |
| GUI アプリ・nix に無い formula | `nix/profiles/darwin/homebrew.nix` の `brews` / `casks` |
| プロジェクト固有のツール | そのプロジェクトの `flake.nix`（nix devshell） |
| 一時的な Python スクリプト実行 | `uvx --with <pkg>` / `uv run --with <pkg>` |
| プロジェクト内の Python 依存 | `uv add` して `uv run` |

**禁止**:

- `npm install -g <pkg>` → `npx` か devshell に追加する
- `pip install <pkg>` / `python3 -m pip install --user <pkg>` → macOS の system Python
  （Xcode 由来）と `~/Library/Python/` には何も入れない

## Rationale

nix に置いたものは `darwin-switch` で収束し、内容が sha256 で検証され、GC の対象として
一貫して扱える。言語別グローバル install はこのどれも満たさず、「いつ誰が入れたか」が
記録に残らない。

nixpkgs に無いツールは custom derivation を書けば nix の管理下に入れられる。実例:
`figma-console-mcp`（`buildNpmPackage`）、`intent-cli`（release binary を `fetchurl` +
sha256 検証 + 明示 `unpackPhase`）。**公式が dotnet SDK 経由の install を第一推奨としていても、
self-contained binary が配布されているならそちらを nix で取り込む方を選ぶ**（2026-08-03、
intent-cli で実際にこの判断をした）。

## Consequences

- nixpkgs stable に無い新しいパッケージは `pkgsUnstable` から個別に引く（実例: `agent-browser`）。
- custom derivation は version と sha256 を手で更新する必要がある。リリース頻度の高いツールでは
  この更新が定期作業になる。
- 追加後は `darwin-switch` が必要。

## Source

- `~/.claude/CLAUDE.md` — 「パッケージ管理の方針」「Python 環境の方針」
- `dotfiles/CLAUDE.md`

## Related

- [0003 — Node.js / npm をローカルに常設しない](0003-nodeless-policy.md)
