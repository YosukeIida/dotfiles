# orca-agent-team 設計ノート

intent-cli の四ロール席（design / orchestrator / implementation / review）を orca 上に配備する
skill の設計。`herdr-agent-team` の後継にあたるが、**コマンド表面も責務も作り直しになる**——
orca は worktree を第一級に扱い、メッセージバスを自前で持ち、ペイン幅の CLI 制御を持たない。

作成日: 2026-09-14 / intent-cli 0.31.0 / orca 1.4.198

---

## 0. 前提（これが崩れたら設計ごと変わる）

**この skill は「4席すべてが intent-cli の external resident である」ことを前提とする。**

intent-cli 0.29.0 の G775 external-residence contract により、配送は以下の3層に分離された：

| 層 | 担い手 | 実体 |
|---|---|---|
| 耐久記録 | intent-cli | `notify delegate/report --write` が canonical routing root に書く |
| 受信 | 各席 | `intent-cli notify collect --role <r> --since <cursor> --wait --routing-root <root>` |
| 起床 | orca（courtesy のみ） | topology に記録した `wake_command` を intent-cli が**テキストとして描画するだけ** |

intent-cli の guide は wake_command の例として **orca を名指しで挙げている**：

```
orca orchestration send --run <run-id> --to run:<run-id> --from <role> --subject {task_id} --body {summary}
```

これにより herdr も agmsg も不要になる。session-layer mode は `herdr-only` を選ぶ
（モード名は transport を指しており、実質「agmsg ブリッジを走らせない」の意味。
記録が無いときの既定は `agmsg` なので明示設定が必須）。

### 前提が崩れる条件（最優先の検証項目）

guide `design-thread` 126行目の deployment rule。文末に「This is a deployment rule, not a
recommendation」と念を押してある強制規定：

> A design seat whose agent kind has no inbound app monitor must be a recorded resident herdr
> seat with cwd `<routing-root>`. A kind with an inbound app monitor may use that external reader.

**「inbound app monitor」の定義が guide から確定できていない。** 手がかり：
orchestrator-thread 530-532行目が agmsg 文脈で「Claude Code は Monitor ツール、Codex は
bridge (beta) で caveat 付き」と書いている。これが G775 の external reader にも同じく
適用されるかは不明。

Codex がこの条件を満たさない場合の影響：

- 全席 external が成立しない → **herdr が戻ってくる**
- 回避案 A: 全席を Claude にする → G789（review 席は design と別 kind が望ましい）を犠牲にする
- 回避案 B: review 席だけ herdr resident にする → herdr 依存が残る

**したがって kind の選択は実機検証の結果で決まる。実装前に検証すること（§6 タスク①）。**

---

## 1. レイアウト

### 決定：host worktree に3席、impl チェックアウトに1席

```
host worktree（1タブ・3ペイン）              impl チェックアウト（別タブ）
┌──────────┬──────────────┬──────────┐      ┌────────────────┐
│  design  │ orchestrator │  review  │      │ implementation │
└──────────┴──────────────┴──────────┘      └────────────────┘
```

### 根拠

**review を host 側に置く**のは herdr 版（review の cwd は impl 側）からの変更。理由：

1. review の実作業は委譲で渡される `.intent-cli/worktrees/review-<unit>` で行われる。
   常設席が impl のチェックアウトに住む必要がない
2. G789 が「review 席は design の出力もレビューする」と規定しており、design と同じ画面にある方が自然
3. `worktree-layout.md` 自身が「metadata を読むロール（設計・調整・レビュー）は同じ
   metadata ブランチを要求するため、worktree 構成では原理的に1つの host を共有する」と書いている

**implementation だけ分離する**のは、git が1ディレクトリに1ブランチしか置けないからという
以上に、**権限境界**の要請が大きい。

> The implementation seat does not receive `--add-dir <host-routing-root>` and does not receive
> MyIntentHost write access. … route `.git` work to the non-sandboxed host-state role.

`.git` を触る権限を持つ席を1つに絞る設計。implementation を host と同じディレクトリに
座らせると cwd 経由で host 状態への書き込み権限が付き、この分離が崩れる。

### orca では2つの worktree を1画面に並べられない（確認済み）

- タブは worktree スコープ（skill に "the tab surface … scoped to a worktree" と明記）
- `terminal split` はタブ内分割のみ。別 worktree のターミナルを引き込むオプションは無い
- app bundle にも複数 workspace 並置を示す機能は見当たらない（`sideBySide` 系は埋め込み
  Monaco diff エディタの内部名）

上記レイアウトはこの制約を受け入れたうえで、**視覚的同居が本当に要る組み合わせ
（design ↔ review）を同じ worktree に寄せる**ことで解いている。

agent 同士は視覚的同居を必要としない（別タブの内容は `orca terminal read` で読める）。
視覚的同居が要るのは人間だけで、その実質的な用途は承認ダイアログの見落とし防止（§5-4）。

### 一時 worktree はこの skill の管轄外

実作業用の worktree は intent-cli が実行のたびに作って消す。担当は host-state ロール1つに
限定されている。

```
git worktree add .intent-cli/worktrees/<role>-<unit> <branch>   # host-state ロールが作る
git worktree remove <managed-path>                               # 同ロールが片付ける
```

規定：「One worktree per role/unit; do not reuse a dirty worktree across units」
「サンドボックス化された Codex 席は `git worktree add` を実行してはならない」。

**この skill が用意するのは常設の2チェックアウト（host / impl）と、そこに座る4席だけ。**

---

## 2. herdr 版から削除する機能（コードから確定済み・議論不要）

| 機能 | 削除理由 |
|---|---|
| `ratio` サブコマンド | `orca terminal split` に `--ratio` が無い。ペイン幅の CLI 制御が存在しない |
| `min_pane_cols` / 幅の下限検査 | 同上。幅は UI で手動調整 |
| defaults.json の `ratio` / `stack_below` / `stack_ratio` | 同上 |
| `nudge` サブコマンド | `orca terminal send --wait-submit <sec>` が構造的に置き換える（§3） |

### `nudge` が不要になる理由

herdr は「入力欄に貼るところまでで submit を保証しない」ため、未着火を**事後に検知して
Enter を送る**必要があった（herdr-agent-team には claude kind で不着火を2回再現した実測記録がある）。

orca は送信が二段階レシートを返す：

> `accepted: true` proves input acceptance, **not a started turn**. Use the receipt's
> `turn_started` stage when submission proof is needed; never resend on silence.

```bash
orca terminal send --terminal <h> --text "..." --enter --wait-submit 10 --json
```

曖昧な失敗時は `--retry-request <id>` で**冪等に**再送できる。
つまり「事後に検知して突く」から「送信時に着火を証明する」に変わる。

---

## 3. 新しく必要になる責務（herdr 版に無かったもの）

### 3-1. orchestration Run の作成と run-id の配布

wake_command の宛先 `run:<run-id>` は Run が存在しないと解決しない。

```bash
orca orchestration run-create --objective <text>    # Run を作る
orca orchestration run-use --id <run-id>            # 各席が読む前に bind
```

guide の規定：「Share the resulting `<run-id>` with every sender before anyone addresses
`run:<run-id>`」「Each sender supplies its own `--from <role>` handle; it is a sender handle,
not a routing identity」。

**Run の寿命をどうするかは要決定（§5-3）。**

### 3-2. wake_command の topology 記録

```bash
intent-cli session-layer topology update-field --domain <d> --team <t> --role <r> \
  --field wake_command --current <v|absent> --new <v|absent> --confirm-update-field --write --format json
```

run-id が変わるたびに全席の wake_command を書き換える必要がある（§5-3 と直結）。

---

## 4. 移植するが検証が要る機能

| 機能 | herdr での実装 | orca での想定 | 不確実性 |
|---|---|---|---|
| READY ping | `agent prompt` → `agent wait --until working` → `--until idle` | `terminal send --wait-submit` → `terminal wait --for tui-idle` | herdr が対処していた「起動直後は `interactive_ready` が false で配送が届かない」問題が orca にあるか不明。**残す方が安全** |
| doctor の承認待ち検出 | `pane read --source detection\|visible` + 正規表現 | `terminal read --screen` + 同じ正規表現 | herdr は alternate screen の codex で `recent-unwrapped` が空になるため `detection` ソースを必要とした。orca の `--screen` が rendered screen を返すなら解消するはずだが**未検証** |
| doctor の usage limit 検出 | 同上 + `usage limit\|rate limit\|quota` 等 | 同上 | 正規表現はそのまま移植可 |
| `swap`（kind 入れ替え） | `agent_status=working` なら `--force` でも拒否 → `/exit` → Enter → Ctrl+C×2 | `terminal close` + `terminal create --command` | **orca に `agent_status=working` 相当が無い。**「稼働中なら拒否」の判定方法が変わる |

---

## 5. 決定事項

### 5-1. host-state ロールは design（決定）

サンドボックス化された agent CLI は宣言外への書き込みを拒否される。guide の実測記録：

> writes outside declared roots are denied, while reads outside declared roots are not denied …
> `.git` is not writable unless `<...>`

一方で四ロールの運用には `.git` を触る作業が必ずある（worktree の作成と削除、issue publish、
label 遷移）。そこでサンドボックスの外で動く席を1つ設け、そこへ集約する。

design を選ぶ根拠は guide 1130行目：

> The orchestrator **routes and verifies**; a sandboxed Codex seat never executes these
> write-bearing commands itself.

orchestrator は依頼して結果を検証する側と明記されている。残る候補は design で、人間が
見ている席なので危険な操作の実行に人間の目が入る。

宣言コマンド：

```bash
intent-cli session-layer topology record-host-state --domain <d> --team <t> \
  --role design --envelope <named-host-state-envelope> --write --format json
```

### 5-2. `--reader` の形は herdr 版のまま（調査済み・決定事項ではない）

実機の host repo で確認した `topology record` の external 形式：

```
--resident external --reader <routing-root-relative-path> [--frontend <name>] [--wake-command <literal-template>]
```

`--reader` は routing-root 相対パス。herdr 版が使っていた `.intent-cli/events/<team>.jsonl`
方式が 0.31.0 でも有効で、当初懸念した「G775 で形が変わっている」は外れだった。

record を skill が呼ぶ点も herdr 版を踏襲する（値を渡すだけで JSON は組まない）。

**別件として発見した問題**：既存の `cmux-dev` チームの topology が 0.31.0 で読めない。
`role-pane-mapping.json`（legacy 形式）の互換読み取りが削除されたため。
`topology record` での再宣言か `topology retire-legacy` が必要。

### 5-3. Run は永続1本（決定）

wake_command には run-id が文字列として焼き込まれる。

```
orca orchestration send --run <run-id> --to run:<run-id> --from <role> --subject {task_id} --body {summary}
```

`up` のたびに `run-create` すると、毎回4席ぶんの wake_command を `topology update-field` で
書き換えることになる。このコストを避けるため、Run は1本を作って使い続ける。

- run-id は team 設定ファイルに保存する
- `up` は `orca orchestration run-use --id <run-id>` で bind するだけ

Run が消えた場合の影響は起床の停止に留まる。耐久記録は無事なのでメッセージの取りこぼしは
起きず、各席が `notify collect --wait` のタイムアウト待ちになる。`run-create` し直して
wake_command を更新すれば復帰する。

### 5-4. 承認ダイアログは2段構え（決定）

impl 席は別タブなので、承認待ちで止まっていても人間が気づかない。

**第1段：発生自体を減らす。** 席ごとの権限と承認モードを事前に宣言する。

```bash
intent-cli session-layer topology record-profile --domain <d> --team <t> --profile-name <n> \
  --kind <kind> --sandbox-mode <mode> --approval-mode <mode> --roots-policy <policy> \
  [--writable-root <path>]... --network-access <value> --transport-mode <mode> --evidence <text> ...
```

guide の釘刺しを守る。全許可で黙らせるのは禁じ手：

> `approval_policy=never` / `danger-full-access` is NOT a substitute for safe routing or cleanup design.

**第2段：残りを doctor で拾う。** `terminal read --screen` に herdr 版の検出正規表現をかける。

```
(y/n|\[y/N\]|approve|permission|do you trust|trust the contents|do you want|allow\?|press enter to continue|^ *›? *1\. )
```

### 5-5. agent kind の割り当て（implementation のみ確定）

| role | kind | model | effort | 状態 |
|---|---|---|---|---|
| design | claude | opus | high | §0 の検証待ち |
| orchestrator | claude | opus | high | §0 の検証待ち |
| implementation | codex | gpt-5.6-luna | **max** | 確定 |
| review | codex | gpt-5.6-sol | high | §0 の検証待ち |

`max` が codex の有効値であることは確認済み
（`~/.codex/config.toml` の `enabled-reasoning-efforts = ["low", "medium", "high", "xhigh", "ultra", "max"]`）。

design / orchestrator / review は §0 の検証結果に依存する。Codex が external になれない場合、
review 席の kind または residence を変更する（§0 の回避案 A/B）。

---

## 6. 実機検証タスク（実装前に潰す）

dotfiles には `.intent-cli` が無く G299 で fail-closed するため、**host repo で実施する必要がある**。

| # | 検証内容 | 失敗時の影響 | 状態 |
|---|---|---|---|
| ① | Codex 席が external resident になれるか（「inbound app monitor」条件） | 設計の前提が崩れる。kind か residence を変更（§0） | 未 |
| ② | `topology record --resident external` が要求する値の形 | herdr 版のコピーが通らない | **済**（§5-2。`--reader` は routing-root 相対パスのまま） |
| ③ | pane resident ゼロ（全席 external）の topology が herdr-only モードで受理されるか | 1席だけ herdr にする混成か、agmsg モードに退避 | 未 |
| ④ | `notify collect --wait` ↔ `orca orchestration send` の往復が実際に通るか | 起床経路の作り直し | 未 |
| ⑤ | `terminal read --screen` が codex の alternate screen を正しく返すか | doctor の承認待ち検出が効かない（§4） | 未 |
| ⑥ | `record-profile` / `record-host-state` の `--envelope` `--sandbox-mode` 等が取りうる値 | §5-1 / §5-4 の第1段が書けない | 未 |

検証環境として使える host repo が手元に3つある：

```
~/workspace/github.com/TMLlaboratory/timesheet-workbench/.intent-cli
~/.intent-teams/s-code/host/.intent-cli
~/.intent-teams/cmux/host/.intent-cli
```

---

## 7. 却下した案

### 却下：herdr-agent-team の構造をそのまま移植する

herdr 版 1091行のうち、幅制御に関わる部分が丸ごと無効になる。`orca terminal split` が受ける
フラグは `--direction horizontal|vertical` と `--command` の2つだけで、`--ratio` に相当する
ものが無い。`herdr pane resize --amount` に対応するコマンドも存在しない。したがって
defaults.json の `ratio` / `stack_below` / `stack_ratio`、`min_pane_cols` の下限検査、
`ratio` サブコマンド（herdr 版では分割ノードのローカル幅を分母に反復収束させていた）は
すべて宛先を失う。`nudge` も `--wait-submit` に吸収される。移植すると、呼び出す先が無い
ラッパーが4機能ぶん残る。

### 却下：4席すべてを別々の orca worktree に置く

orca の `worktree create --agent` は「separate checkout」用途と skill が明示している。
4席に4 worktree を割ると4タブに分散し、design ↔ review の見比べができなくなる。
実作業用の worktree は intent-cli がユニットごとに作るので、常設席を分ける意味も薄い。

### 却下：agmsg モードを使う

0.22.0 時点ではこれが唯一のオンコントラクト経路だったが、G775（0.29.0）により不要になった。
agmsg を足すと常駐プロセスまたは Stop-hook の設定が全席に必要になる。

### 却下：`orca orchestration` を直接使って intent-cli の `notify` を迂回する

guide が明示的に禁じている（「never bypass notify with a handwritten transport call」）。
`--dry-run` は pending record を書かないため、`notify status` / stalled-work / dispose の
帳簿が委譲を認識しなくなる。

### 却下：ターミナル出力を長文の受け渡しに使う

**実測：orca の端末保持量は 2,000 行。**50,000行を出力させたところ
`oldestCursor=48002 / latestCursor=50002` で、それ以前は回復不能だった。
`--limit 60000` を指定しても 2,000 行しか返らない（`limited: false`）。
cursor paging は保持窓の中をページングする仕組みで、保持量を超えて遡る手段ではない。

保持量を変える設定は CLI にも設定ファイルにも存在しない（アプリ内部の定数）。

長文の行き先は**委譲の時点で決める**しかない。出力が終わってから判断したのでは、
判断した時点で頭が消えている。

- 判定・ステータス・要約（〜数十行） → メッセージ本文
- 成果物（レビュー全文・diff・ログ） → ファイルに書かせ、パスだけメッセージに載せる

intent-cli は `notify delegate --expected-artifact <value>` を必須フラグにしており、
委譲時にアーティファクトの宣言を強制している。orca 側も
`orchestration send --report-path <path>` で同じ形を用意している。

---

## 8. 責務境界（herdr 版の boundaries.md を踏襲）

### 持つもの

常設チェックアウト（host / impl）の用意、タブとペインの構成、各席の agent 起動、
role → worktree / terminal handle / kind のマッピング、生存確認、撤収、
orchestration Run の作成と run-id の配布。

### 持たないもの

| 領域 | 正本 |
|---|---|
| 委譲の作法・完了判定・wake 源の設計 | `intent-cli guide orchestrator-thread` |
| 配送トポロジーの形式 | `intent-cli session-layer topology`（値を渡すだけ。JSON は組まない） |
| packet / issue / PR / label / closeout | `intent-cli guide ...` |
| ユニットごとの worktree の作成・削除 | intent-cli の host-state ロール |
| orca の一般操作 | orca 公式 skill `orca-cli` / `orchestration` |

判断の指針：「これは orca に何かを**させる**機能か、intent-cli の**作法を説明する**機能か」。
後者は足さず `guide` を呼ぶよう促すだけにする。

### 命名と description

skill 名 `orca-agent-team`。今日配備した orca 公式 skill `orchestration` と description が
近接するため、分界を明記する：

> intent-cli の四ロール席を orca 上に配備する。委譲・レビュー・publish の作法は
> intent-cli guide が、orca の一般操作は orca-cli / orchestration が担当する。

---

## 9. 進め方

1. ~~設計ノートのレビューと §5 の判断~~ → 完了（2026-09-14）
2. 実機検証 ①③④⑤⑥（②は完了）
3. 検証結果を反映して設計を確定
4. 実装

**§6 が片付くまで実装に入らない。** 特に §0 の前提（Codex が external になれるか）が崩れると
kind の選択が変わる。

### 別件として残る作業

`cmux-dev` チームの topology が 0.31.0 で読めない状態にある（§5-2）。
このチームを使う前に `topology record` での再宣言か `topology retire-legacy` が必要。
