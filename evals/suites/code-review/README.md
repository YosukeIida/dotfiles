# code-review suite（未整備）

コードレビューのタスク。code-reviewer subagent（現在 opus 固定）が sonnet で十分かを検証する。

タスク設計方針（planted-bug 方式）:
- 既知のバグを意図的に仕込んだ diff を fixture に置き、レビューさせる
- grader は `type: script`: モデルの回答（$ANSWER_FILE）に仕込んだバグの指摘が
  含まれるかを判定（バグの行番号・種類のキーワードマッチ + 誤検出数の上限）
- **両方向をカバーする**（audit.md）: バグ入り diff だけでなく「バグなしの正常な diff」も
  タスクに含め、偽陽性（ないバグをでっち上げる）を減点できるようにする
