# herdr-app

Herdr app の自作の layout と、それが使う mod。darwin-switch が `install.sh` で `~/.config/herdr-app/` へコピーする。Herdr app 同梱の layout・mod（`main` など）には触れないので、Herdr app の中で `ctrl-shift-l`（`layout.switch`）で同梱のものと切り替えて使う。

編集はこの folder で行い、darwin-switch（または `./install.sh`）で反映する。`~/.config/herdr-app/` の側で編集した分は、次のコピーで上書きされる。

## layout

- `layouts/pasture.json`: 同梱の `main` を複製し、次の 2 か所を差し替えたもの。
  - 左の sidebar の上半分 `spaces` → `paddock`（project・worktree・agent・sub-agent の木）。下半分 `agents` → `agents-tree`
  - 右の panel の Files `files` → `activity` の `browse` の画面（Names・Contents の検索バーと、ファイルツリー。押したファイルを terminal の右の editor の pane で開く）

## 自作の mod

- `mods/confirm-close/`: cmd-w でタブを閉じる前に、ダイアログで確かめる（Enter で閉じる、Esc でやめる。ダイアログが出ている間にもう一度 cmd-w を押すと、やめる）。同梱の `tab.close` は、space の最後のタブのときしか確かめない。`install.sh` が `keys.json` の `cmd-w` を、同梱の既定の `tab.close` のときだけ `mod.open:confirm-close` に替える。layout によらず効く

- `mods/agents-tree/`: 同梱の `agents`（0.1.13）の複製。別の agent が起動した agent でペインを持つもの（herdr-agent-team の席など）を、親の行の下に通常の行として字下げして並べ、上の階層には出さない（同梱の版は、親の下の木と自分の行の 2 回出す）。同じタブに agent が複数あるときは、各行にタブ名ではなく、herdr-agent-team の席なら label の `herdr-team.role`、それ以外は hc の端末名、名前が無ければ agent のタイトルを出す。同梱の版の更新は自動では入らないので、取り込むときは `cloned_from` の版との diff を読む

## 外部の mod

| mod | upstream | rev | 扱い |
|---|---|---|---|
| `mods/paddock/` | https://github.com/choam2426/herdr-paddock の `mods/paddock/` | `8c02b94fedbf13e5654b3ef6b76c705510984434` | fork（下の変更を加えている） |
| `mods/activity/` | https://github.com/yama-lei/herdr-editor-layout の `mods/activity/` | `5220dcd` | fork（下の変更を加えている） |

どちらも Apache-2.0（各 folder の `LICENSE`）。更新は upstream の新しい rev を取り込み、diff を読んでから commit する。取り込むときは、下の変更を残す。

`paddock` に加えた変更:

- 別の agent が起動した agent でペインを持つものを、親の行の下に通常の行（`agentRow` に木の線）として並べ、自分の space の位置には出さない。hc の名前を持つ端末は、行の後半に session ではなく label の `herdr-team.role`（無ければ端末名）を出す（`agents-data.js` の `nested`・`role`、`agents.js`、`main.js` の `agentRows`）。確認は `bun tests/paddock-agents.test.mjs`
- この Mac の project・機体の行の `+` で、`space.new` に `machine: ""` を渡す（`main.js`・`overlay.js`）。upstream は機体を省いており、Herdr app はクリックで省かれた機体を「選んでいる space の機体」と解釈する。別の機体の space を選んでいると、その機体でこの Mac の folder に端末を起こそうとし、`space.new failed: cannot start a terminal` になった。upstream への PR: https://github.com/choam2426/herdr-paddock/pull/1（取り込まれたら、この変更は upstream の rev を取り込むだけで済む）
- upstream の `hooks/`（Claude Code・Codex・Pi の内部の sub-agent を label で載せる hook）は取り込んだが、settings.json には登録していない。登録しない間は、内部の sub-agent の行は出ない。`main.js` の `agentRows` は、ペインを持つ席の行（上の変更）と、upstream の内部の sub-agent の行（`joinSubs`）を両方並べる

`activity` に加えた変更:

- `browse.js` を追加した。Names（repo の全ファイルをパスで絞り込む）と Contents（`search.js`）を切り替える検索バーを、ファイルツリーの上に置く
- ファイルのアイコンを、upstream の `ficons/`（Material Icon Theme の色付きアイコン）から、`icons/` の単色の folder・file に替えた（`common.js` の `fileImage`）。`ficons/` は消した
- 各画面の見出しを大文字にしない。Explorer の見出しを Files にした
- editor の見出しから Open in VS Code を消した
- Markdown は Preview で開く。Preview・Side by side・Edit を切り替えるボタンを並べた（`common.js` の `segmented`）
- Markdown の Preview で、別の行の数式（`$$…$$`、`\[…\]`）を RaTeX の `ratex-svg` で SVG にして表示する（`math.js`）。`ratex-svg` は dotfiles の `homebrew.nix` が `yosukeiida/casks-personal/ratex` で入れる。文中の数式（`$…$`）は Unicode の文字に置き換えて表示する（`tex.js`。ギリシャ文字・記号・上付きと下付き・`\frac` を a/b に）。Herdr app の Markdown の表示は、文中の画像も `<sub>`・`<sup>` も描かないため。確認は `bun tests/tex.test.mjs`
- HTML のファイルは、開くと既定のブラウザでも開く。editor の pane にはソースと「Open in browser」のボタンを出す
- PDF のページに付けていた Ctrl+ホイールの拡大（`on_scroll_wheel`）を、ページの外側の要素に移した（`viewer.js`）。`v_virtual_list` の renderer の中で handler を付けると例外になり、PDF のページが 1 枚も描かれなかった
- Files の定期の再読み込み（`files.js` の `REFRESH`）で、開いたフォルダの中身が 1 つ前に開いたフォルダのものにずれる不具合を直した。JS が先頭に root（`""`）を渡しているのに、shell の側でも root を足しており、root の一覧が 2 回出ていた

`activity` は Linux で作られており、macOS では次の機能が動かない: Explorer の削除（`gio trash`）、file の clipboard（`wl-clipboard`・`xclip`）。PDF の表示は `pdftoppm`、画像・動画は `ffmpeg`・`ffprobe` が要る。
