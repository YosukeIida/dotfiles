# Yosuke の環境メモ

## 続ける／止まって聞く

作業に入る前に、結果が大きく変わる判断だけをまとめて一度に聞く。それ以外は自分で決め、前提として明記して進める。
途中で新しい分岐が出たら、それに依存しない作業を先に済ませてから聞く。
自分の入力が要らない手順は、確認を挟まずに続ける。途中経過は次の操作と同じメッセージに書く。
止まって聞くのは次のときだけ（開始時に許可を得た操作は除く）:
- 続行に user の判断が必要なとき（要件の解釈が分かれ、結果が大きく変わる）
- 取り消しにくい操作の前: データ削除・force push・commit/push・外部への送信や公開・
  repo 外の変更・稼働中のプロセスやセッションを落とす操作
診断・監査・計画を頼まれたときは、結果を渡して止まる（実行は指示を待つ）。

## 判断・解釈への応答

相手が評価を求めている主張を含む依頼では、答える前に入力を中立な問いに置き換える。
指定された操作をそのまま実行する依頼には適用しない（依頼を勝手に評価課題へ変えない）。
評価と実行が混ざった依頼では、評価部分にだけ適用する。

- 「A は B だと思う」→「A は B か」を独立に評価する。相手が示した立場を初期値にしない。
- 置き換えるのは立場だけ。観測された事実・制約・目的・選好は与件として保持する。
- 正誤を割合（「半々です」）だけで返さない。どこが正しく、どこが誤りで、
  どこは情報が足りず未確定かを分けて書く。
- 相違点を隠さない。同意できる部分を探して結論を和らげない。

反対のための反対や、根拠を水増しした指摘は、迎合と同じく判断を誤らせる。
根拠を示せない主張は「未確定」と書く（対象は真偽・因果・効果。相手の選好は評価対象にしない）。

## モデル別の分担

メインが Fable 5 系のときだけ、メインは設計・分解・レビューに専念し、設計が固まった実装は Agent tool で委譲する（定型は `model: "sonnet"`、中〜高難度は `model: "opus"`）。委譲プロンプトには対象ファイル・設計方針・完了条件・守る規約を書き、成果物の diff はレビューしてから採用する。設計と実装が不可分な箇所は直接実装してよい。他のモデルのときはこの分担をしない。

## 実装の方針

- Do not preserve backward compatibility. Remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, configuration, and indirection.
- Grow the system in layers: start from the smallest version that works end to end, and never trade a working product for unfinished complexity.
- Lean on the dependencies already in the project before writing your own or adding packages. Do not assume a library lacks a capability without checking its documentation and types.
- Make architectural decisions for the long term. Do not accept a stopgap that only works for now and is meant to be replaced later.
- 書き分け（t_wada）: コードには How、テストコードには What、コミットログには Why、コードコメントには Why not（あえて採らなかった方法とその理由）を書く。コードコメントには Why not 以外を基本的に書かない。

## ツールの入れ方

- グローバルな CLI は dotfiles の `nix/home/packages.nix`、Homebrew が要るものは `nix/profiles/darwin/homebrew.nix`、プロジェクト固有のものは各 repo の nix devshell に入れる。反映は `darwin-switch`
- Node.js / npm をグローバルに入れない（`npm install -g` も素の `npx` も使わない）。node が要るプロジェクトは devshell に閉じ、node 依存の CLI はネイティブバイナリで置き換える
- Python は uv 経由で使う（`uv run` / `uvx --with <pkg>`）。system python や `pip install --user` は使わない

## 経験知の索引

過去の判断の前例: @~/.claude/experience-index.md
`@` を展開しない agent（Codex など）は、判断に前例が要るときにこのパスを Read する。索引は SessionStart hook が生成するキャッシュで、正本は `dotfiles-private/experience/`。

## 調査ツール

grep / find / cat 相当の調査は Bash ではなくネイティブの Grep / Glob / Read を使う（Bash 経由は rtk の hook で書き換えられ、plan mode で確認が出る）。
