# intent-cli 四スレッド運用の遅さ 診断

- 記録者: design thread
- 記録日: 2026-08-08 〜 2026-08-09
- 対象: `~/.intent-teams/` 配下の全チーム（dotfiles / s-code / cmux / ra-workbench）
- 根拠: `.intent-cli/runs.jsonl`、`.intent-cli/events/*.jsonl`、
  `diagnostics/2026-08-03-review-pane-w1B-pJ.md`、GitHub のラベル履歴
- 発端: 「review の指摘を subagent に並列実行させれば速くなるのではないか」という
  仮説の検証。結論としてこの仮説は**実データに支持されなかった**（下記）。

---

## 結論

**遅さの原因はワークフローの形（レビュー往復・WIP=1 の直列化）ではない。**
パイプラインが正常に流れたときの実測は **1 unit あたり13分**。
遅かった2回は、いずれも**外的な障害で止まっていた時間**だった。

| 原因 | 損失 | 状態 |
|---|---|---|
| codex アカウントの rate limit（review pane が起動不能） | 約70分 ×1回 | **解決済み**（アカウント切替＋pane 再作成、rate limit も本日 08-08 で明け） |
| Claude Code の permission classifier が `gh pr merge` / `pr-transition` を拒否 | 27分 + 35分 | **未解決** ← 唯一残っている実害 |

前回議論した「レビュー指摘の並列 subagent 化」は、このどちらにも効かない。

---

## 実測: dotfiles ドメイン（唯一 unit を完走させた実績があるチーム）

| unit | issue→PR | review<br>(reviewing→approved) | approved→merge | 合計 |
|---|---|---|---|---|
| templates-nixpkgs-2605 | 11分 | **4分** | **27分** ⚠️ | 47分 |
| ci-checkout-v7 | 4分 | **2分** | 1分 | **13分** ✅ |
| flake-inputs-2605 | 10分 | **109分** ⚠️ | 0分 | 131分 |

**レビュー自体は正常時 2〜4分の一発承認。** `intent-pr-request-update` は全 PR で **0回**
（＝レビュー指摘による修正往復は一度も発生していない）。

---

## 障害1: codex アカウントの rate limit（解決済み）

flake-inputs-2605 の109分は、`diagnostics/2026-08-03-review-pane-w1B-pJ.md` に
operator が追記した真因がすべてを説明している:

> pane に `try again at Aug 8th, 2026` が出ていた（codex アカウントの rate limit）。
> 最初の turn が失敗するため `interactive_ready` が確立せず、herdr が `running=false` と
> 扱い、notify の宛先候補から漏れていた。`Ctrl+L` でも幅を50桁に戻しても直らず、
> **アカウント切替で即解決した**。

つまり:

- **herdr-only トランスポートの欠陥ではない。** orchestrator が途中で立てた
  「幅が原因」「payload が届かない別種の故障」という仮説は、診断ファイル内で
  いずれも明示的に撤回されている
- 対処として review pane を `w1B:pJ` → `w1B:pP` に作り直し、`cx labteam` で
  別アカウントに切替、`herdr agent start` で re-provision して解決
- **rate limit の解除日は "Aug 8th, 2026" = 本日**

### 派生して分かった、運用上効く知見

**`delivered: false` の半分は誤検知。**

> `notify delegate` の能動確認は「settled → working → settled の往復」を 10000ms 以内に
> 観測する必要があり、review のように作業が10秒を超えると窓が切れて `delivered: false`
> になる。

| 種類 | 判別方法 |
|---|---|
| 真に未着火 | `state_change_seq` が不変 かつ pane に payload の痕跡なし |
| false negative（着火済み） | `state_change_seq` が増加 または pane が処理中 |

**再送前に必ず `state_change_seq` と pane を見ること。** 誤検知で再送すると二重投入になる。
（08-03 の運用ではこれを知らずに「委譲不能」と2回報告し、待ち時間を伸ばしている）

なお 08-03 12:14 の「`delivered:true` を返すのに submit されない」という adapter の
偽陽性は別件の実バグで、その後の周回では `delivered:false` を返すよう**改善済み**。

---

## 障害2: permission classifier（未解決・唯一の実害）

2 unit で再現、いずれも orchestrator が実行できず operator の手動待ちになった:

| 時刻 | 拒否されたコマンド | 損失 |
|---|---|---|
| 08-03 12:31 | `gh pr merge` | 27分（approve 済み・CI green・closeout-plan ready の状態で放置） |
| 08-03 16:17 | `intent-cli automation pr-transition --transition approved --write` | 35分 |

`gh pr merge` については既知（保存済みメモ `gh-pr-merge-classifier-blocked`）。

### 仕組み: allow ルールは classifier より先に解決する

公式ドキュメント（`code.claude.com/docs/en/permission-modes`、"How the classifier
evaluates actions"）の判定順序:

> Each action goes through a fixed decision order. **The first matching step wins**:
> 1. Actions matching your allow, ask, or deny rules **resolve immediately.**
>    Writes to protected paths route to the classifier even when an allow rule matches. …
> 2. Read-only actions and file edits in your working directory are auto-approved…
> 3. **Everything else goes to the classifier.**

つまり `permissions.allow` にマッチした時点で確定し、classifier には行かない。
auto mode でも同じ。ただし2つの例外がある:

**例外1 — auto mode 突入時に落とされる allow ルール**

> On entering auto mode, **broad allow rules that grant arbitrary code execution are dropped**:
> - Blanket `Bash(*)` or `PowerShell(*)`
> - Wildcarded interpreters like `Bash(python*)`
> - Package-manager run commands
> - `Agent` allow rules
>
> **Narrow rules like `Bash(npm test)` carry over.**

`Bash(intent-cli:*)` / `Bash(gh pr merge:*)` はいずれも該当せず、carry over する。

**例外2 — `autoMode.classifyAllShell`**

> Default: `false`. When `true`, **suspends every Bash and PowerShell allow rule**
> while auto mode is active

現在 `claude/settings.json` に `autoMode` キー自体が無いので default の `false`。影響なし
（Claude Code 2.1.226 で確認）。

### なぜ `gh pr merge` が拒否されたのか — classifier は誤作動していない

`claude auto-mode defaults` の BLOCK ルールに該当項目がある:

> **Merge Without Review** [named+specifics — must name: merging without review]:
> **Merging a PR before any human has approved it.**

このドメインの承認は**ラベルベース**で、GitHub の native review はゼロ:

| PR | `latestReviews` | `reviewDecision` | 結果 |
|---|---|---|---|
| #21 | `[]` | `""` | MERGED |
| #23 | `[]` | `""` | MERGED |

**「人間の承認が1つも無い PR を merge しようとしている」という判定は事実として正しい。**
メモにあった「ユーザーが明示指示すると通る」も、このルールの `[named+specifics]` バー
（ユーザーが merge を名指しすると解除）で説明がつく。

### 対処

**入れる — `permissions.allow` に1行:**

```json
"Bash(intent-cli:*)"
```

ラベル遷移・queue 更新・notify・publish-flow をすべてカバーする。intent-cli は
read-only by default で `--write` 必須、AI provider を起動しない、破壊的操作を持たない
（`guide model` の hard rules）。step 1 で確定するので classifier を通らない。

**入れない — `Bash(gh pr merge:*)`**

技術的には通るが、それは「レビュー無し merge」の安全網を外すことそのもの。

**本筋の解 — review pane を別 GitHub アカウントにする**

診断ファイルによれば native approve は `Review Can not approve your own pull request`
で失敗している（reviewer = PR author = `YosukeIida`）。**別アカウントで native APPROVE が
入れば Merge Without Review ルールは自然にクリアされ**、classifier をいじらずに
orchestrator が merge できるようになる。診断ファイル自身も「独立性を求めるなら別 reviewer
account が必要」を残論点に挙げている。

それまでの当面は、orchestrator が blocked を上げたら design / operator が代行する
（メモ `gh-pr-merge-classifier-blocked` の運用）が正しい形。

### 無人 pane で効いてくる仕様

> If the classifier blocks an action **3 times in a row or 20 times total, auto mode pauses**
> and Claude Code resumes prompting.

merge がブロックされ続けると orchestrator pane が auto mode から落ちてプロンプト待ちになり、
そのまま停止する。08-03 の停滞にこれが混ざっていた可能性がある。

---

## 障害3（軽微・上流課題）: pane 再作成のたびに手作業が発生する

診断ファイルより:

> `session-layer topology record` に上書き手段が無く conflict で拒否されるため、
> operator が `role-pane-mapping.json` の review エントリを手で外してから record し直す
> 必要があった。pane を作り直すと `pane_id` は必ず変わるので、この経路は再 provision の
> たびに発生する。

rate limit・クラッシュ・アカウント切替のたびに踏むので、intent-cli 側に
`topology record --force` 相当が欲しい。upstream 案件。

---

## 他チームの状況

### s-code（TMLlaboratory/s-code）

- 4ロールの pane マッピング完備、session-layer は herdr-only（08-03 18:00 に切替）
- **`runs.jsonl` 空、queue-state 空、GitHub の PR に intent ラベルが1つも無い**
- → **まだ1 unit も流れていない。** 遅い以前に起動していない

### cmux（YosukeIida/cmux）

- 4ロール完備、herdr-only（08-03 15:54 切替）、events は 08-04〜08-05 に5件
- **`runs.jsonl` 空、queue-state 空、リポジトリに PR が1件も無い**
- events の内容:
  > 「implementation 完了・ブランチと2コミットを検証。CI red/green・dogfood・PR は未実施で **design 判断待ち**」
  > 「hover 下線/インジケータの完全パス表示は **design 設計待ち**」
- → 詰まっているのは **design の判断**。orchestration の速度の問題ではない
- → 実装は進むが PR にならず queue にも乗らないので、intent-cli 側の記録がすべて空のまま

### ra-workbench

- `~/.intent-teams/ra-workbench/` には **`impl/` しか無い（`host/` も `.intent-cli` も無い）**
- → **intent-cli の四スレッドを通していない。** 素の Claude Code 作業
- 本日の PR #6（9分）、#7（37分・11コミット）はいずれも intent ラベル無し・review 無し
- **比較基準としては有用**: 同種の作業が四スレッド無しで 9〜37分

---

## 推奨する順番

1. **permission classifier を潰す**（唯一残っている実害。最大27分/回）
   - `Bash(intent-cli:*)` を `claude/settings.json` の `permissions.allow` に追加 → 確実に効く
   - `gh pr merge` は allow を足さない。別 reviewer アカウントで native APPROVE を
     入れるのが本筋。当面は design / operator が代行
2. **codex アカウントの rate limit を監視対象にする**
   - review pane が codex 固定なので、limit に当たるとチーム全体が止まる
   - `cx` の複数アカウント切替は既にあるので、`interactive_ready: null` を見たら
     まず rate limit を疑う（幅や adapter を疑わない）
3. **`delivered:false` を見たら再送する前に `state_change_seq` を見る**
   - 08-03 の待ち時間の一部はこの誤検知による自己ブロック
4. ここまでで **1 unit 13分が再現するか確認する**
5. **s-code / cmux は「遅い」ではなく「起動していない / design 待ち」** — 別問題
   - cmux は特に、実装が PR にならないまま design 判断で滞留している構造を先に見るべき
6. **レビュー指摘の並列 subagent 化は 4 の後**
   - 現状の PR は指摘0件・1コミット。並列化する対象がまだ存在しない
   - 指摘が10件単位で出る規模の PR が実際に発生してから判断すればよい

---

## 本セッション中に自分が出した誤り（記録）

1. 「指摘1件ごとの往復が最大のレバー」→ **実データに往復は0回**。仮説を検証前に断定した
2. 「herdr-only adapter の欠陥が着火失敗の原因、agmsg に戻すべき」→ **真因は codex の
   rate limit**。events の途中経過だけを読み、同じリポジトリの `diagnostics/` に
   operator が追記した解決記録を読まずに結論を出した
3. 「`gh pr merge` は classifier 判定なので allow ルールでは通らない」→ **誤り**。
   allow ルールは判定順序の step 1 で classifier より先に確定する。公式ドキュメントを
   読まずにメモの観測（allow ルールが無い状態での挙動）から一般化した
