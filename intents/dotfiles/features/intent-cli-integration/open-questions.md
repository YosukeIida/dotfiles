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

#### 回答（2026-08-03、`templates-nixpkgs-2605` の1周を実測）

**contract の粒度は妥当だった。過剰ではない。** ただし必須セクションは10ではなく13だった。

実測の内容: dependabot PR #10 / #11（`templates/{node,python-uv}/nix` の nixpkgs を
26.05-darwin に上げる。両者の diff は完全一致）を1つの execution unit に統合し、
issue #20 → PR #21（squash merge `5a5e147`）まで4スレッドで回した。

妥当と判断した根拠:

- **埋めるコストは低かった。** `packet draft` が13セクションの雛形を出すので、作業は
  「白紙から書く」ではなく「埋める」だった。やり直しは1回（後述の title キー）。
- **issue が自己完結していた。** implementation は host metadata（`.intent-cli/**` /
  `intents/**`）を一度も読まずに PR を出した。issue 本文だけで実装できたということで、
  contract が目的を果たしている。
- **review が独立検証できた。** AC 5点すべてを reviewer 側で確認できた。特に
  「本体 `flake.nix` / `flake.lock` に差分がないこと」を AC に入れたことで、
  *更新単位を分割したという設計判断そのもの*が PR の形で検証された。これは
  contract を書かなければ得られなかった検証である。

**実コストは contract ではなく前段の gate にあった（いずれも初回のみ）:**

1. `publish-flow` はタイトルを**トップレベルの `title:`** から解決し、`packet draft` が
   生成する `implementation_issue_packet.issue_title` を読まない。放置すると issue 名が
   `<execution-unit> (untitled)` になる。scaffold と publish の不整合で、intent-cli 側の
   想定漏れの可能性が高い。
2. `publish-flow --write` が atomic-seed gate（G363）で fail-closed し、前段に
   `automation queue-seed-from-packet --write` が必要だった。
3. ワークフローラベル11本が repo に未作成で `automation issue-publish` が失敗。
   初回に `automation label-palette-sync --write` が必要。
4. `closeout plan` / `closeout pr` の `next_steps` が submodule pointer 同期を指示するが、
   host / impl / target が同一 repo で `submodules/` も `.gitmodules` も無く非該当
   （`state_layout=legacy-fallback` 由来の汎用ヒント）。無視して進めてよい。

**毎回発生する運用コストが1つだけ残る。これが導入可否を左右する最大要因:**

5. herdr-only の `notify delegate --write` が **Claude kind の pane では `delivered: true` を
   返しながら task block が prompt buffer に貼られたまま submit されず不着火**（2回再現）。
   Codex pane では正常に着火した。herdr 0.7.5 の `agent prompt --wait` /
   `agent_prompt_stalled` による submit 確認が adapter に入っていない。
   結果として design が毎ホップ `herdr agent send-keys <role> enter` を送る必要があり、
   **operator が席を外している間はフローが止まる**。

**判断: dotfiles で intent-cli を通す価値はある。** 3ヶ月放置されていた依存更新が、
判断基準の記述（`operations/dependency-updates.md`）と1周の実行で片付いた。
ただし 5 が解決するまで「自律運用」は成立せず、operator が着火を担う半自動運用になる。
2周目以降のコストを 1〜4 抜きで再測し、それでも重ければ timer-loop モードへの縮退を検討する。

### OQ-3 — transport は agmsg / herdr-only のどちらにするか（FR-3 / AC-3）

前提として両者は対等な選択肢であり、既定は agmsg。1チームにつき1つのみで、混在は
contract violation。切替は `intent-cli session-layer set` で可逆。

- agmsg は既に install 済み（`AGMSG_NODE` が `home.sessionVariables` に設定されている）
- herdr も install 済みで、実際に herdr 内で作業している（`HERDR_ENV=1`）

つまり**どちらも選べる状態にある**。herdr-only は preview 段階であることを踏まえて決める。

#### 回答（2026-08-03）

**herdr-only を採る。** `templates-nixpkgs-2605` の1周を herdr-only で完走した
（issue #20 → PR #21 → closeout）。

herdr-only を選ぶ実利が1つ確認できた: **identity が pane 単位なので、同じディレクトリに
複数ロールの pane を置ける。** agmsg では identity が folder-scoped（G521）で、
1ロール1フォルダが強制される。metadata を読むロール（design / orchestrator / review）は
同じ metadata ブランチを要求するため、agmsg だとロールごとに clone が必要になる。
herdr-only では `host` worktree 1つを3ロールで共有できる（[FR-3 の物理配置](requirements.md) 参照）。

代償は OQ-2 の回答に挙げた実測材料5（Claude pane で submit されない）で、これは
transport の選択を覆すほどではない。agmsg に切り替えても Claude Code への配送は
同じ経路を通らない代わりに、folder-scoped identity の制約で clone が増える。
**adapter の submit 確認漏れとして intent-cli 側に報告するのが正しい対処**であり、
transport を変える理由にはしない。

### OQ-4 — `worktree_root` はトポロジー B で正しく機能するか（FR-3 / AC-3）

`config.toml` の `worktree_root = ".intent-cli/worktrees"` は host repo root からの相対パス。
トポロジー B では host root が orphan ブランチ `main-metadata` の worktree であるため、
child worktree が「orphan ブランチの worktree の中に、`main` から切ったブランチの worktree を
作る」という入れ子になる。

公式ガイドは「`.intent-cli/worktrees/**` の中から intent-cli コマンドを実行しないこと」を
繰り返し警告している。この配置が意図どおり動くか未検証。

代替案: child worktree を host の外（例: `~/workspace/github.com/YosukeIida/dotfiles-work-<issue>`）
に置き、`worktree_root` を変更する。

#### 回答（2026-08-03）

**入れ子は発生しなかった。代替案の側（child worktree を host の外に置く）を採ったため。**
`worktree_root` の設定は変更していない。

確定した物理配置:

```
~/workspace/github.com/YosukeIida/dotfiles   [main]           本番。日常編集・darwin-switch
~/.intent-teams/dotfiles/host                [main-metadata]  design + orchestrator + review
~/.intent-teams/dotfiles/impl                (detached HEAD)  implementation
```

`host` と `impl` はどちらも本番 checkout の worktree で、**新規 clone はゼロ**。
`impl` を `host` の中ではなく兄弟に置いたので、`impl` から親を辿っても `.intent-cli/` に
当たらず、G300（実装リポジトリに `.intent-cli/` が存在してはならない）が
`--github-only` の宣言ではなく**構造で**担保される。

実測で確定した3点:

- **`impl` は detached HEAD でなければならない。** base ブランチ（`main`）は本番 checkout が
  保持しており、git は同一ブランチの二重 checkout を禁じる。detached なら制約に当たらず、
  そこから `switch -c` で作業ブランチを切れる（implementation が実際にそうした）。
  detached では `git pull` が使えないので `git fetch origin <base> && git reset --hard origin/<base>`
  を使う。これは公式 child-loop 手順とそのまま一致する。
- **一時 worktree にはローカルブランチ名ではなく remote-tracking ref を渡す。**
  implementation が作業ブランチを `impl` に持っている間、同じブランチ名を別 worktree に
  出すと `fatal: already used by worktree` で失敗する。`origin/<branch>` を渡せば
  `worktree.guessRemote` 未設定（既定 false）なら自動 detached で成功する。
  `gh pr checkout` はローカルブランチを作るので使わない。
- **`worktree_root` は結局使われなかった。** review は host cwd から `gh` と canonical
  コマンドで完結し、一時 worktree を切る必要がなかった。設定は review が必要になった場合の
  ための待機状態にある（`.gitignore` 済み）。

なお本体 flake input の更新（dependabot #8 / #9 / #12）は `darwin-switch` による実機検証を
要し、flake が絶対パスで本番 checkout を指すため `impl` worktree からは検証できない。
この分担は [operations/dependency-updates.md](../../operations/dependency-updates.md) に記述済み。
