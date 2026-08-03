# intent-cli-integration — packets

> See [../../packets/](../../packets/) for domain-level packet list.

## Execution units

まだ packet を切っていない。下記は候補であり、`intent-cli packet draft` を通していない
（＝ execution unit として登録されていない）。

| 候補 | 対応 | 状態 | 備考 |
|---|---|---|---|
| dispatcher skill の配備を宣言的にする | FR-1 / AC-1 | 未着手 | **最初のスライス候補。** 範囲が小さく、OQ-1 の a/b/c から選ぶ判断だけで着手できる。実測1周（AC-2）の題材としても粒度が適切 |
| 4スレッド運用の物理配置を決める | FR-3 / AC-3 | 未着手 | OQ-3（transport）と OQ-4（worktree_root）の解決を含む。上の1本を回してから着手する方が判断材料が揃う |

## Next action

`intent-cli intent next-slice --domain dotfiles --dry-run` で候補が出るかを確認する。
`design-needed` が返る場合は intent の記述がまだ足りないということなので、
overview / requirements / acceptance を先に埋める。
