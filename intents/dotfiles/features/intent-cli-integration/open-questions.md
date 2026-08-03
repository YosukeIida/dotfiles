# intent-cli-integration — open questions

> See [../../clarifications/open.md](../../clarifications/open.md) for domain-level open questions.

## Open questions blocking this feature

### OQ-1 — dispatcher skill を dotfiles でどう管理するか（FR-1 / AC-1）

`intent-cli skill install --target claude --scope user` が
`~/.claude/skills/intent-cli/SKILL.md` に直接書き込む。既存の skill 4層管理のどれにも
該当しない第5パターンで、現状 dotfiles の管理外にある。

候補:

| 案 | 内容 | 懸念 |
|---|---|---|
| a | 現状維持（intent-cli 自身に管理させる） | 新マシンで入れ忘れる。`darwin-switch` で再現されない |
| b | `darwin-switch` の postActivation で `intent-cli skill install` を冪等実行 | plugins（`claude/install-plugins.sh`）と同じパターンで一貫する。要検証: 既にローカル編集があるとき `--force` 無しでどう振る舞うか（G573 で「ローカル編集版の上書き保護」が入っている） |
| c | vendor して `_link` で配る | [ADR 0002](../../decisions/0002-vendor-over-nix-for-skills.md) と形は揃うが、intent-cli のバージョン更新と二重管理になり、`skill diff` の drift 検出を殺す。**非推奨** |

現時点の傾向: **b**。`claude/install-plugins.sh` が `darwin-switch` 時に plugins を冪等
インストールしている前例があり、「CLI 自身が配布主体で、dotfiles は install を宣言するだけ」
という形は既存パターンと整合する。

### OQ-2 — dotfiles の作業粒度に対して issue contract は妥当か（FR-2 / AC-2）

child issue contract は10セクションを必須とする。`sync-gist-skills.sh` の1行修正のような
dotfiles の典型作業に対しては過剰に見える。

ただし緩和材料がある: `intent-cli packet draft` が10セクションの雛形を自動生成するため、
コストは「白紙から書く」ではなく「埋める」である。

**推測で決めない。** AC-2 の1周を実測してから、この欄に回答を書く。

判断の観点:

- 実際に埋めるのにかかった手間（体感と、やり直しの回数）
- 生成された issue が後から読んで役に立ったか（＝ intent を残す価値があったか）
- 過剰だった場合の対処: packet を大きめに切って複数の小変更をまとめる／
  タイマーループモードに切り替えて orchestrator を省く／dotfiles では特定種類の作業のみ
  intent-cli を通す

### OQ-3 — transport は agmsg / herdr-only のどちらにするか（FR-3 / AC-3）

前提として両者は対等な選択肢であり、既定は agmsg。1チームにつき1つのみで、混在は
contract violation。切替は `intent-cli session-layer set` で可逆。

- agmsg は既に install 済み（`AGMSG_NODE` が `home.sessionVariables` に設定されている）
- herdr も install 済みで、実際に herdr 内で作業している（`HERDR_ENV=1`）

つまり**どちらも選べる状態にある**。herdr-only は preview 段階であることを踏まえて決める。

### OQ-4 — `worktree_root` はトポロジー B で正しく機能するか（FR-3 / AC-3）

`config.toml` の `worktree_root = ".intent-cli/worktrees"` は host repo root からの相対パス。
トポロジー B では host root が orphan ブランチ `main-metadata` の worktree であるため、
child worktree が「orphan ブランチの worktree の中に、`main` から切ったブランチの worktree を
作る」という入れ子になる。

公式ガイドは「`.intent-cli/worktrees/**` の中から intent-cli コマンドを実行しないこと」を
繰り返し警告している。この配置が意図どおり動くか未検証。

代替案: child worktree を host の外（例: `~/workspace/github.com/YosukeIida/dotfiles-work-<issue>`）
に置き、`worktree_root` を変更する。
