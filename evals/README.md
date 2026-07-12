# evals — データ駆動なモデル選択のための軽量 eval ハーネス

自分が繰り返しやるタスクを suite 化し、**model × effort のグリッドで実測**して
「どのタスクはどのモデル/effort で十分か」を経験則ではなくデータで決めるための仕組み。

方法論は Anthropic の Code w/ Claude 2026 ワークショップ
[Picking the Right Model](https://github.com/anthropics/cwc-workshops/tree/main/rightmodel)
に従う。チェックリストと sweep の設計原則は取り込んだ skill を参照：
`agents/skills/eval-audit-and-sweep/`（audit.md = eval 健全性、sweep.md = スイープ設計）。

## 構成

```
evals/
├── run.py        # sweep runner（headless claude -p、stdlib のみ）
├── grade.py      # grader（script 判定 / atomic LLM rubric）
├── plot.py       # 集計・3プロット・HTML レポート（uv 経由で matplotlib）
├── suites/
│   ├── nix-config/   # nix 設定編集タスク（プログラマティック判定）
│   ├── code-impl/    # コード実装・リファクタ（未整備）
│   ├── code-review/  # planted-bug 方式のレビュー（未整備）
│   └── academic/     # 校正・翻訳。タスク実体は dotfiles-private 側（未整備）
└── results/<suite>/  # trial<t>.jsonl + transcripts/ + プロット（git 管理外）
```

## 使い方

```bash
cd ~/workspace/github.com/YosukeIida/dotfiles

# 1. スイープ実行（trial を変えて3回が標準。完了セルはスキップされ resume 可能）
python3 evals/run.py --suite nix-config --trial 1
python3 evals/run.py --suite nix-config --trial 2
python3 evals/run.py --suite nix-config --trial 3

# グリッドを絞る場合
python3 evals/run.py --suite nix-config --models haiku,sonnet --efforts low,high --trial 1

# 2. 集計・プロット
uv run --with matplotlib python3 evals/plot.py --suite nix-config
open evals/results/nix-config/sweep_report.html
```

主要メトリクスは **cost_per_success**（総コスト ÷ 成功数）と **secs_per_success**。
「呼び出し単価が1/3でも成功率が半分なら実質高い」を1つの数字に畳んだもの（sweep.md §2）。

## タスクの書き方

```
suites/<suite>/tasks/<task-id>/
├── task.json     # {"id", "allowed_tools", "grader": {...}}
├── prompt.md     # モデルに渡すプロンプト（成功基準が機械的に決まる書き方をする）
├── fixture/      # 一時 workspace にコピーされる入力ファイル（編集タスク用）
└── grade.sh      # grader type=script のとき。workspace を cwd に実行、exit 0 = pass
```

grader は2種類:

- `{"type": "script", "script": "grade.sh"}` — プログラマティック判定（優先）。
  `$ANSWER_FILE` にモデルの最終テキストのパスが入る。
  exit code 規約: **0 = pass / 1 = fail / それ以外・timeout = grader_error**
  （grader 自体の故障。status に昇格して pass rate から除外され、resume で再実行される）
- `{"type": "llm_rubric", "checks": [{"id": "...", "question": "..."}]}` —
  開放的なタスク用。check ごとに独立した judge 呼び出し（atomic、audit.md §4）。
  judge は `--judge-model`（デフォルト opus）で被験セルと独立に固定する

## 運用ルール

1. **新しい suite を書いたらまず audit**: Claude Code でこのリポジトリを開いて
   「eval-audit-and-sweep skill でこの eval suite（evals/suites/<name>）を audit して」
2. **grader は必ず既知の正解と既知の誤答でテストする**（oracle ≈ pass / 誤答 = fail）。
   これを通らない grader でスイープしても数字は信用できない
3. スイープ結果は `CLAUDE.md` の委譲ルールと `agents/subagents/*.md` の
   `model:` frontmatter に反映する
4. **living suite として運用する**: 実務で委譲先モデルの失敗を見つけたら、
   それを新しいタスクとして追加する
5. 結果を読むときは noise floor に注意（タスク4件 × 3 trial なら1件 ≈ 8pt。
   それ未満の差は意味がない）。レポートに自動で表示される

## 既知の制約

- Claude Code 経由なので thinking on/off は独立に振れない（effort に畳まれる）。
  API 直叩きのスイープが必要になったら sweep.md の元の手順に戻る
- LLM judge も Anthropic モデルなので self-preference バイアスは完全には消せない。
  導入時に数件を手動ラベルと突き合わせて較正すること（audit.md §4）
- 各呼び出しに system prompt のキャッシュ書き込み（~15k tokens）が乗る。
  セル間では同条件なので比較は成立するが、絶対コストは実運用より高めに出る
- transcript は最終メッセージ + 計測値のみで、途中のツールコール列は残らない
  （深掘りが必要なら `--output-format stream-json` への切り替えを検討）
- グローバル CLAUDE.md / plugins は各 run に読み込まれるため、それらを大きく変えると
  過去 trial との比較可能性が落ちる。スイープをまたぐ比較は同時期の trial 同士で行う
- タスクの scaffold（allowed_tools / prompt）を変えたら、変更前の trial とは比較しない。
  suite を丸ごと再実行する
