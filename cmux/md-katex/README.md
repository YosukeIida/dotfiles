# cmux-md-katex

`.md` ファイルを **cmux のブラウザペイン**で数式込みプレビューするツール。
VSCode の Markdown プレビューと同じ仕組み（`markdown-it` + KaTeX）を、cmux の
WKWebView ペインで再現する。保存のたびに自動で再レンダリングされる。

ターミナルそのもの（Claude Code などの TUI）には数式を描画できない（TUI は文字
グリッドで、Claude Code 側がインライン画像未対応）。そのため**別ペインの本物の
ブラウザ**を使う、という切り分け。

## 使い方

```bash
mdkatex path/to/note.md          # ブラウザペインで開き、保存ごとに自動更新
mdkatex note.md --no-watch       # 一度だけ描画して終了
mdkatex note.md --regen          # viewer.html を強制再生成
```

`mdkatex` は `zsh/zshrc` で定義した関数。**cmux ワークスペースのシェル**で実行する
こと（`$CMUX_WORKSPACE_ID` と cmux ソケットが必要）。Ctrl-C で監視を終了。

## 仕組み

1. **viewer.html を生成**（`gen_viewer.py`、初回と陳腐化時のみ）
   - KaTeX 一式（css/js）と **20 個の woff2 フォントを base64 で CSS に埋め込み**、
     完全自己完結・オフライン可・`file://` クロスオリジン制約に非依存の単一 HTML に。
   - KaTeX は `nixpkgs#katex` から取得（リポジトリにフォントを抱えない）。
   - `markdown-it` と `markdown-it-katex` は `vendor/` に同梱（nixpkgs に無いため）。
   - 生成物は `~/.cache/cmux-md-katex/viewer.html`。
2. **ブラウザペインで一度だけ開く**（`cmux browser open`）。surface ref をキャッシュ。
3. **更新は eval で push**：md ファイルを base64 化し
   `cmux browser <ref> eval "window.__render(window.__b64('<b64>'))"` を送る。
   ページ再読込なし＝ちらつきゼロ。base64 なのでシェルのエスケープ問題も起きない。
4. ファイルの mtime をポーリング（0.5 秒）して変更を検知（fswatch 等に非依存）。

## 構成

```
cmux/md-katex/
├── cmux-md-katex             # 起動スクリプト（zshrc の mdkatex 関数が呼ぶ）
├── gen_viewer.py             # 自己完結 viewer.html ジェネレータ
├── vendor/
│   ├── markdown-it.min.js    # markdown-it 14.x
│   └── markdown-it-katex.js  # markdown-it-katex 2.0.3（CommonJS / ページ内でシム）
└── README.md
```

## メンテナンス

- KaTeX のバージョンは flake の nixpkgs に追従。store パスが変わると次回起動時に
  viewer.html を自動再生成する。
- `markdown-it` を更新するときは `vendor/` のファイルを差し替えて `--regen`。
