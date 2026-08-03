# intent-cli-integration — design decisions

> See [overview.md](overview.md) for goals and [../../decisions/](../../decisions/) for cross-domain ADRs.

## Decisions

### D-1 — install は self-contained binary の nix derivation で行う（2026-08-03）

公式ドキュメント `docs/en/01-install.md` は `dotnet tool install -g` を第一推奨としている
（"The basic path is the .NET global tool from NuGet.org (requires a .NET 10 SDK)"）。
これを**採らず**、公式が代替として配布している osx-arm64 self-contained binary を
`nix/home/packages.nix` の custom derivation として取り込んだ。

理由: `dotnet tool install -g` は `npm install -g` / `pip install --user` と同じ
「nix 管理外のグローバル状態」を作る（[ADR 0004](../../decisions/0004-nix-first-packages.md)）。
`dotnet` SDK 自体も不要になる。

実測メモ: tarball の中身が単一バイナリ（ディレクトリなし）のため、stdenv デフォルトの
`unpackPhase` が `sourceRoot` 自動推定に失敗する（"unpacker appears to have produced no
directories"）。`unpackPhase = "tar xzf $src"` を明示して回避した。

### D-2 — トポロジー B（同一 repo + metadata ブランチ）を採用（2026-08-03）

公式には2つのトポロジーがある。

- A: host を専用の別リポジトリにする
- B: 同一リポジトリで、host metadata を専用ブランチ（`main-metadata`）に置く

**B を採用した。** 理由:

- 管理するリポジトリを増やしたくない（既に dotfiles / dotfiles-private /
  personal-agent-skills の3本を運用している）
- 公式の比較表が「すでに単一リポジトリがあり intent-cli を追加したい」に対して
  B を推している（移行コストが低い）

B を選ぶ動機として公式が挙げているのは、**実装 PR が `main` を対象にしながら metadata を
含まないようにする**ことである。`.intent-cli/` を `main` に commit すると、`main` から
切ったすべての実装ブランチが `.intent-cli/` を含み、child-worker の禁止事項
（"The implementation repo MUST NOT contain a `.intent-cli/` directory", G300）に
構造的に反する。

トレードオフとして受け入れたこと: metadata ブランチは public リポジトリ上で誰にでも見える
（公式の比較表にも明記されている）。intent tree に秘密の値を書かないことで担保する（NFR-2）。

実装: `git worktree add --orphan -b main-metadata <path>` で orphan ブランチとして作成し、
`.intent-cli/config.toml` に `metadata_source_branch` / `metadata_write_branch = "main-metadata"`
を設定した。orphan にしたのは、metadata ブランチが `main` とマージ関係を持つ必要がないため。
（※公式ドキュメントは orphan か main 派生かを明記していない。orphan は当方の判断。）

### D-3 — `project_type: infrastructure` を選択（2026-08-03）

`intent-cli intent init-tree --project-type` の4択のうち `infrastructure` を選んだ。
`product/` を持たず `environments/` と `runbooks/` を持つ構成で、マシン環境そのものを
対象とする dotfiles に合う。

### D-4 — 旧フラットレイアウトを廃棄（2026-08-03）

`intent-cli intent init` は `intents/<domain>/intent-tree/00-map.md` という旧フラット形式を
作る。`intent lint-layout` がこれを `MISSING-MANIFEST` / `tree-domain: False` として警告し、
`init-tree` による tree-v1 化を促す。両方を残すと二重管理になるため、
`intent-tree/00-map.md`（内容は placeholder のまま未使用）を削除した。

初回セットアップは `intent init` → `intent init-tree --write` の**2段構え**が正しい手順である
（公式 docs の G441 補足）。`init` 単独では bindings が無く `next-slice` が
`missing-domain-bindings` を報告する。

## Open

dispatcher skill の管理方式（FR-1）は未決。[open-questions.md](open-questions.md) の OQ-1 を参照。
