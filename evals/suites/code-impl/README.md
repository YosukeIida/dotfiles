# code-impl suite（未整備）

コード実装・リファクタのタスク。implementer-sonnet / implementer-opus の使い分け境界を実測で決める。

タスク設計方針:
- 実リポジトリの過去の実装タスクを縮小して fixture 化（テスト付き）
- grader は `type: script` でテスト実行（pytest / npm test 等）。exit 0 = pass
- 難易度を混ぜる: 定型（ボイラープレート・リネーム）〜非自明（複数ファイル・エッジケース）
