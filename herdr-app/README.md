# herdr-app

Herdr app の自作の layout と、それが使う mod。darwin-switch が `install.sh` で `~/.config/herdr-app/` へコピーする。Herdr app 同梱の layout・mod（`main` など）には触れないので、Herdr app の中で `ctrl-shift-l`（`layout.switch`）で同梱のものと切り替えて使う。

編集はこの folder で行い、darwin-switch（または `./install.sh`）で反映する。`~/.config/herdr-app/` の側で編集した分は、次のコピーで上書きされる。

## layout

- `layouts/pasture.json`: 同梱の `main` を複製し、次の 2 か所を差し替えたもの。
  - 左の sidebar の上半分 `spaces` → `paddock`（project・worktree・agent・sub-agent の木）。下半分の `agents` は同梱のまま
  - 右の panel の Files `files` → `activity` の `browse` の画面（Names・Contents の検索バーと、ファイルツリー。押したファイルを terminal の右の editor の pane で開く）

## 外部の mod

| mod | upstream | rev | 扱い |
|---|---|---|---|
| `mods/paddock/` | https://github.com/choam2426/herdr-paddock の `mods/paddock/` | `540e3d20d7b960ac325fd5a5401f905b40e93953` | vendor（手で編集しない） |
| `mods/activity/` | https://github.com/yama-lei/herdr-editor-layout の `mods/activity/` | `5220dcd` | fork（下の変更を加えている） |

どちらも Apache-2.0（各 folder の `LICENSE`）。更新は upstream の新しい rev を取り込み、diff を読んでから commit する。`activity` は、取り込むときに下の変更を残す。

`activity` に加えた変更:

- `browse.js` を追加した。Names（repo の全ファイルをパスで絞り込む）と Contents（`search.js`）を切り替える検索バーを、ファイルツリーの上に置く
- ファイルのアイコンを、upstream の `ficons/`（Material Icon Theme の色付きアイコン）から、`icons/` の単色の folder・file に替えた（`common.js` の `fileImage`）。`ficons/` は消した
- 各画面の見出しを大文字にしない。Explorer の見出しを Files にした
- editor の見出しから Open in VS Code を消した
- Markdown は Preview で開く。Preview・Side by side・Edit を切り替えるボタンを並べた（`common.js` の `segmented`）
- Markdown の Preview で、別の行の数式（`$$…$$`、`\[…\]`）を RaTeX の `ratex-svg` で SVG にして表示する（`math.js`）。`ratex-svg` は dotfiles の `homebrew.nix` が `yosukeiida/casks-personal/ratex` で入れる。文中の数式（`$…$`）は、Herdr app の Markdown の表示が文中の画像を描かないので、生の TeX のまま残る
- HTML のファイルは、開くと既定のブラウザでも開く。editor の pane にはソースと「Open in browser」のボタンを出す

`activity` は Linux で作られており、macOS では次の機能が動かない: Explorer の削除（`gio trash`）、file の clipboard（`wl-clipboard`・`xclip`）。PDF の表示は `pdftoppm`、画像・動画は `ffmpeg`・`ffprobe` が要る。
