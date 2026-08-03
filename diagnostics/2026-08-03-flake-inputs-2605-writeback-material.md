# flake-inputs-2605 の knowledge write-back 材料

- 記録者: orchestrator thread
- 記録日: 2026-08-03
- 関連 task-id: `writeback-flake-inputs-2605`
- declared write-back target: `intents/dotfiles/operations/dependency-updates.md`
- 関連 PR: https://github.com/YosukeIida/dotfiles/pull/25 (MERGED, `c0afa20`)
- 関連 issue: https://github.com/YosukeIida/dotfiles/issues/24 (CLOSED)

`intent-cli notify` の external 経路は6フィールド schema で本文を落とすため、
材料をこのファイルに置いて event の `artifact` からリンクする。

## packet が宣言した問い

> 本体 flake の移行で `darwin-rebuild build` が実装用 worktree 内の検証手段として
> 実際に機能したかを記録する。機能したなら operations/dependency-updates.md の
> 「実機検証の分担」を build/switch の区別を含む形に更新する（現在の記述は switch
> のみを前提にしており、build が worktree 内で使えることを反映していない）。

## 答え: 機能した。しかも2回、独立に

| 実行者 | 場所 | 結果 |
|---|---|---|
| implementation | `/Users/yosuke/.intent-teams/dotfiles/impl`（実装用 worktree） | 成功（自己申告） |
| review | 同一 head `a84bef49` の一時 clone（`/tmp` 配下、実行後 Trash に移動） | **exit 0**（独立に裏取り） |

review は orchestrator が「AC4 は自己申告で未検証」と明示して委譲したのを受け、
`darwin-rebuild build --flake .#Yosukes-MacBook-Air` を自分で回して裏取りした。
つまり `build` は「実装者の自己申告」に留まらず、**第三者が再現できる検証手段**
として成立している。

## build は CI では代替できない

`.github/workflows/nix-check.yml` の `nix` job が実行するのは:

```
nix flake check -L
nix eval .#darwinConfigurations.example.config.system.build.toplevel.drvPath
nix eval .#darwinConfigurations.Yosukes-MacBook-Air.config.system.build.toplevel.drvPath
```

いずれも **evaluation（drvPath の算出）まで**で、derivation の realise（実ビルド）は
していない。したがって:

- CI green は「評価が通る」ことしか保証しない
- 26.05 系への移行で実際にビルドが通るかは、`darwin-rebuild build` を回すまで分からない
- この slice では結果的に option 改名・パッケージ名変更への追随は不要だったが、
  それを**確認できたのは build を回したからであって CI ではない**

## したがって提案する記述の変更

`operations/dependency-updates.md` の「実機検証の分担」は現在 switch のみを
前提にしている。次の3層に分けるのが実測に合う。

| 層 | 何を保証するか | 誰が / どこで |
|---|---|---|
| CI (`nix flake check` + `drvPath` eval) | 評価が通る。realise は保証しない | GitHub Actions、PR ごとに自動 |
| `darwin-rebuild build` | derivation が実際にビルドできる。システムは変更しない | **agent が実装用 worktree / 一時 clone 内で実行可能**（implementation と review の両方が実施済み） |
| `darwin-rebuild switch` | 実機に適用される | **host 側の operator 作業**。agent は実行しない |

現在の記述が反映していないのは中段である。`build` が worktree 内で完結し
システムを変更しないため、**agent に委譲できる検証**であることを明記したい。

## 3周目で判明したその他の実測（参考）

`diagnostics/2026-08-03-review-pane-w1B-pJ.md` に詳細があるが、
dependency-updates.md に関係しうるものだけ挙げる。

- 本体 flake の3本（nixpkgs / nix-darwin / home-manager）を1 unit にまとめる判断は
  正しかった。`follows` で連動するため個別更新は中間状態を生み、dependabot PR
  #8 / #9 / #12 は同じファイルを触るので1本 merge すると残りが conflict する
- `nix flake update` を無指定で実行すると ref を持たない `nixpkgs-unstable` が
  一緒に動く。input を明示して更新する必要がある（AC3 がこれを検証している）
- `flake.lock` には同名の推移的依存ノードが混在する。`home-manager`（bare、
  agenix 経由）と `home-manager_2`（root の入力）があり、**`nodes.root.inputs` の
  マッピングを辿らないと誤判定する**。orchestrator は実際に一度誤読した
- 2周目の OQ-2 閾値（設計判断を含む slice は intent-cli を通す / 単一の機械的更新は
  通さない）に照らすと、この slice は「3本の統合判断」があるため通す側で正しかった
