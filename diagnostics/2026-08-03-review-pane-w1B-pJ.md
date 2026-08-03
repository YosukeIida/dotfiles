# review pane `w1B:pJ` が herdr の prompt を受け付けない — 診断

- 記録者: orchestrator thread
- 記録日: 2026-08-03
- 関連 task-id: `repair-review-pane-w1B-pJ` / `review-flake-inputs-2605`
- 関連 PR: https://github.com/YosukeIida/dotfiles/pull/25

この診断は `intent-cli notify` の external 経路（events.jsonl）が
6フィールド固定 schema で本文を落とすため、内容をファイルに置いて
event の `artifact` からリンクする形にしたもの。

## 結論

**codex は止まっていない。** 計算中でハングしているのではなく、空プロンプトで
idle のまま何も渡されていない状態。

- `agent_status: idle` / `state_change_seq: 889`（何度測っても不変）
- 最後の turn は2周目の `─ Worked for 2m 09s ─`（PR #23 review の完了）
- プロンプトは空入力プレースホルダ `› Run /review on my current changes` を表示
- `--source detection`（herdr が状態判定に使う面）でも実行中のスピナーや進捗表示なし

## 訂正

orchestrator が先に報告した「payload が Codex の入力 buffer に不可視で載っている
可能性が高い」は**誤り**。空入力プレースホルダが出ているので buffer は空であり、
Enter を押しても着火しない。

さらにその前に報告した「Codex pane は payload が一切届かない別種の故障」も不正確。
実因は Claude pane と同じ `agent_prompt_stalled` である。

## 問題1: 幅の修復が効いていない（review は 36桁）

`herdr pane layout` の実測値:

| role | pane | 実測幅 |
|---|---|---|
| design | `w1B:p1` | 78 |
| orchestrator | `w1B:pG` | 46 |
| implementation | `w1B:pH` | 35 |
| **review** | **`w1B:pJ`** | **36** |

領域全体は `width=195`。review は50桁のつもりが36桁で、`--source visible` では
33桁前後で折り返しており、承認ダイアログが読める下限に届いていない。

関係する split:

| split id | direction | ratio | rect width |
|---|---|---|---|
| `split_0_root` | right | 0.39999998 | 195 |
| `split_1_1` | right | 0.38930002 | 117 |
| **`split_2_11`** | right | **0.4948** | 71 |

`split_2_11` が implementation(35) と review(36) を分けている。

## 問題2: 破れた再描画の断片が残存

pane 末尾に次の断片が残っている。

```
  gpt-5.6-sol high · Cont
› Ru

  gp…
```

リサイズ後に Codex の TUI が完全に再描画していない痕跡。

## 問題3: herdr が review の interactive prompt を確立できていない

| role | agent | `interactive_ready` |
|---|---|---|
| design | claude | **null** |
| orchestrator | claude | `true` |
| implementation | claude | `true` |
| **review** | **codex** | **null** |

`interactive_ready: null` は herdr が「このペインの対話プロンプトが入力を
受け付ける状態」を確認できていないことを意味する。`notify delegate` が返す
エラーと整合する:

```
agent_prompt_stalled: agent prompt produced no observed state change
within 5000 ms; status is idle and state_change_seq remained 889
```

herdr は prompt を送出したが pane 側が状態変化を返していない。

## 推奨対処（session layer は design の所管なので orchestrator は実行しない）

1. `split_2_11` の ratio（現在 0.4948）を調整して review を50桁以上に広げる
2. pane にフォーカスして `Ctrl+L` で TUI を再描画させる
3. それでも `interactive_ready` が null のままなら
   `herdr agent start review --kind codex --pane w1B:pJ` で再 provision
   （ガイドが `agent-undetected` 系の回復手順として定める経路）

## PR #25 は待たせても劣化しない

- head `a84bef49981139a804f3ba2d2a0fa35b630cbaaa`
- CI all-green（`nix` 2m14s / `secrets` 24s）
- `mergeStateStatus: CLEAN` / `MERGEABLE`
- ラベル `intent-target` + `intent-pr-reviewing`
- AC は7点中6点を orchestrator が独立検証済み。未検証は AC4（`darwin-rebuild build`
  の成功）のみ。CI の `nix` job は `nix flake check -L` と
  `darwinConfigurations.{example,Yosukes-MacBook-Air}.config.system.build.toplevel.drvPath`
  の eval までで、derivation の realise はしていない

修復後、orchestrator が同一 task-id `review-flake-inputs-2605` で再 dispatch する。

## 解決（2026-08-03 追記）— 真因は codex アカウントの rate limit

上記の「問題1: 幅」は**真因ではなかった**。operator が確認した実際の原因:

- pane に `try again at Aug 8th, 2026` が出ていた（codex アカウントの rate limit）
- 最初の turn が失敗するため `interactive_ready` が確立せず、herdr が
  `running=false` と扱い、notify の宛先候補から漏れていた
- `Ctrl+L` でも幅を50桁に戻しても直らず、**アカウント切替で即解決した**

つまり `interactive_ready: null` は正しい観測だったが、その原因を幅と結び付けた
本書の推論は誤りだった。幅は読みにくさの問題であって配送不能の原因ではない。

対処として実施されたこと:

- review pane を `w1B:pJ` → **`w1B:pP`** に作り直し、`cx labteam` で別アカウントに切替
- `herdr agent start` で logical role 名を付け、READY ping を送って running を確立
- topology を record し直し（`review` は `w1B:pP` / `codex`）

幅の方針は変更された: skill の下限判定を team config の `min_pane_cols` で
変えられるようにし **30** に設定。MacBook のディスプレイ幅（領域195桁）では
元の割合（design 0.40 / orch 0.24 / impl 0.18 / review 0.18）を維持する運用とし、
**review は 36桁のまま**とする。pane を読むときは狭いことを前提にする。

### CLI 側に手段が無い制約として認識されたこと

`session-layer topology record` に上書き手段が無く conflict で拒否されるため、
operator が `role-pane-mapping.json` の review エントリを手で外してから
record し直す必要があった。pane を作り直すと `pane_id` は必ず変わるので、
この経路は再 provision のたびに発生する。

## 追記: `delivered: false` は false negative にもなる

復旧後の再 dispatch（`w1B:pP` 宛て）も `delivered: false` を返したが、これは
**誤検知**だった。pane では Codex が `working` に遷移して task block を処理して
おり（`state_change_seq` 889 → 969）、実際には配送されていた。

`notify delegate` の能動確認は「settled → working → settled の往復」を
10000ms 以内に観測する必要があり、review のように作業が10秒を超えると窓が
切れて `delivered: false` になる。

つまり `delivered: false` には2種類ある:

| 種類 | 判別方法 |
|---|---|
| 真に未着火 | `state_change_seq` が不変 かつ pane に payload の痕跡なし |
| false negative（着火済み） | `state_change_seq` が増加 または pane が処理中 |

**再送前に必ず `state_change_seq` と pane を見ること。** false negative で再送すると
実行中の作業に二重投入する。

## 追記: label 承認と GitHub native APPROVE の関係

PR #25 の review は判定 APPROVE（指摘なし）を出したが、GitHub の native
APPROVE 送信が `Review Can not approve your own pull request` で拒否され
`blocked` を報告した。active GitHub account (`YosukeIida`) が PR author だから。

ただしこの domain の workflow 承認は**ラベルベース**であり native review を
要件としていない。実測（`gh pr view --json reviewDecision,latestReviews`）:

| PR | `latestReviews` | `reviewDecision` | label | 結果 |
|---|---|---|---|---|
| #21 | `[]` | `""` | `intent-pr-approved` | MERGED |
| #23 | `[]` | `""` | `intent-pr-approved` | MERGED |

1周目・2周目とも native review はゼロで merge されている。したがって native
APPROVE の不可は intent-cli workflow を止めない。正しい記録手段は
`intent-cli automation pr-transition --pr <n> --transition approved --write`。

**ただし残る論点**: チーム全体が単一の GitHub identity で動いているため、
ラベル承認は GitHub レベルで独立した reviewer を持たない。これは2周分すでに
そう運用されてきた既存の性質であって今回導入されたものではないが、独立性を
求めるなら別 reviewer account が必要になる。判断は operator / design に属する。

## 付随して判明した transport の制約

`intent-cli notify delegate --to <external role>` は task block を
events.jsonl の6フィールド schema
（`timestamp` / `team` / `kind` / `unit` / `summary` / `artifact`）に
圧縮する。複数の `--input` を渡しても `summary` に objective、`artifact` に
1本目の input が入るだけで、残りは配送されない。

herdr pane 宛ての配送では task block 全文が渡るため、この非対称は
external recipient を使う場合に情報を落とす。詳細を渡したい場合は本書のように
ファイルを成果物として置き、`artifact` にそのパスを載せる必要がある。
