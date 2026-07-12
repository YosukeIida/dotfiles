# academic suite（未整備）

学術系（校正・翻訳）のタスク。ja-prose-polish / en-paper-translate 等の実行時モデル選択に使う。

**タスク実体はここには置かない。** 論文原稿は private なので
`~/workspace/github.com/YosukeIida/dotfiles-private/evals/academic/tasks/` に置き、
実行時は run.py の suite ディレクトリを差し替えるか symlink で参照する。

タスク設計方針:
- grader は `type: llm_rubric`（開放的タスクのため）。check は atomic に分割する
  （例: 「指定された誤字がすべて修正されているか」「原文にない主張が追加されていないか」
  「LaTeX コマンドが壊れていないか」を独立の check に）
- 導入時に数件を手動ラベルと突き合わせて judge を較正する（audit.md §4）
- 既知の誤答（空文字列・的外れな回答）を judge が fail できることを先に確認する
