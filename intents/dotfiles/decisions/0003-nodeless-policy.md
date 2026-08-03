---
facets: [invariant]
---

# 0003 — Node.js / npm をローカルに常設しない

- Status: **Canonical**
- Date: 2026-07-13〜14（方針確立）／2026-07-29 に例外1件
- Scope: パッケージ導入方針

## Context

CLI ツールの多くが Node/TypeScript で書かれており、素朴に入れると `node` と `npm` の
グローバルインストールが必要になる。

## Decision

**メイン Mac に Node.js / npm を常設しない。** Node 製ツールを使いたい場合は、次の順で解決する。

1. upstream が **プリコンパイル済みネイティブバイナリ**を配布していないか確認する。
   npm パッケージでも `optionalDependencies` で `<pkg>-darwin-arm64` のような per-platform
   ネイティブバイナリを配布しているケースが多い（実例: `backlog.md`。JS の `bin` エントリは
   薄い dispatcher shim で、実体は Bun コンパイル済みの単体バイナリ）。
2. 配布バイナリが無い場合は、**公式配布の bun バイナリを一時ダウンロード**して
   `bun build --compile` で単体バイナリ化する（使用後に削除。永続 install にしない）。
3. brew でバージョン管理を維持したい場合は、個人 tap
   （`yosukeiida/casks-personal`）にネイティブバイナリを install するだけの formula を書き、
   `homebrew.nix` の `brews` を tap-qualified 名で指す。

## Rationale

`~/.claude/CLAUDE.md` の Python 方針（system Python を汚さない、`uvx` / `uv run` で使い捨てる）と
同じ思想。言語ランタイムのグローバル汚染を避け、ツールごとに閉じたランタイム / バイナリで済ませる。

**nixpkgs の bun でコンパイルしてはいけない**（実測された破壊）: nix ICU にリンクした生成物を
`install_name_tool` + スタブ dylib 同梱で延命する方式は、スタブ自体が nix store の実体 dylib 群を
reexport しているため GC で壊れる。実例として `cctag-spoke` が 2026-07-14 にこれで起動不能に
なった。公式 bun はシステムの `/usr/lib/libicucore.A.dylib` にリンクするため、生成バイナリが
nix store に一切依存せず GC 耐性が根本的に確保される。

## Consequences

- `darwin-switch` に guard がある。`nix/hosts/darwin/scripts/check-node-deps.sh` が
  `homebrew.nix` の `brews` を nix eval し、tap-qualified 名で `brew deps --for-each` して
  runtime 依存に node が混入していたら警告する。新しい node 依存ツールを追加すると次回の
  `darwin-switch` で警告が出る。
- `--include-build` は使わない。ビルド時のみの node 依存は bottle install では無関係なため
  （実例: `hunk` はビルド時のみ node 依存で、実インストールに影響なし）。
- 裸の formula 名で `brew deps` を呼ぶと同名の core formula に解決されてしまうので、
  常に tap-qualified 名を使う（実機確認済みの Homebrew の挙動）。

## Known exception

2026-07-29、herdr-browser プラグイン用に nixpkgs の `bun` を `home.packages` に追加した。
プラグインは同日中にアンインストールしたが、ユーザーの明示判断で `bun` は維持している。
用途が「`bun run` で TypeScript を直接実行する」であり「単体バイナリへの compile」では
ないため上記の ICU リンク問題を直接踏まないが、**この nix bun で何かを compile して単体
バイナリを作ろうとする場合は、上記の教訓を思い出すこと**。

## Source

- memory `nodeless-policy`（実例と実測の記録）
- `dotfiles/CLAUDE.md` — 「`npm install -g` は使わない」

## Related

- [0004 — パッケージは nix / homebrew / devshell に分けて宣言する](0004-nix-first-packages.md)
