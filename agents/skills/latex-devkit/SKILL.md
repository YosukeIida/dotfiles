---
name: latex-devkit
description: latex-devkit を使って LaTeX を Docker でビルドする操作スキル。「PDFをビルドして」「latexでコンパイルして」「ビルドして」などの表現がトリガー。外部リポジトリの papers/ 以下のプロジェクトのビルドにも対応。※既存 LaTeX プロジェクトのビルド専用。サーベイ論文の執筆工程一式（文献収集〜章ドラフト〜PDF 化）は tmllab-academic-survey-paper が担当。
allowed-tools: Bash(make:*), Bash(docker:*)
metadata:
    vendor-repo: YosukeIida/latex-devkit
    vendor-path: skills/latex-devkit/SKILL.md
    vendor-commit: 4c7a845f142974b54648d140d9c280c31f5c115b
---

# latex-devkit 操作スキル

## 前提

このスキルは [latex-devkit](https://github.com/YosukeIida/latex-devkit) を
ローカルに clone してあることを想定する。clone 先のパスを `$LATEX_DEVKIT_DIR`
として参照する（例: `~/workspace/github.com/YosukeIida/latex-devkit`）。

Docker + TeX Live によるローカルビルド環境。

## コア操作

### 内部プロジェクト（latex-devkit/projects/ 配下）

```bash
cd "$LATEX_DEVKIT_DIR"
make up                              # 初回のみ。コンテナ起動。
make build-local PROJ=<プロジェクト名> MAIN=main.tex
```

### 外部リポジトリのプロジェクトをビルドする手順

論文ファイルが別リポジトリの `papers/` 以下にある場合、
`LATEX_PROJECTS_DIR` にそのパスを渡すことで、latex-devkit 側だけでビルドできる。
`make up` は不要。`build-local` が `docker compose run --rm` でコンテナを都度起動・削除する。

```bash
export PAPERS=/path/to/your/repo/papers

cd "$LATEX_DEVKIT_DIR"
make build-local PROJ=<プロジェクト名> MAIN=main.tex LATEX_PROJECTS_DIR=$PAPERS
```

PDF は `$PAPERS/<プロジェクト名>/build/` に生成される
（プロジェクトの `latexmkrc` に `$out_dir = 'build'` を設定済みであれば）。

### 別プロジェクトを追加するとき

`papers/` 以下に新しいディレクトリを作るだけでよい。

```bash
make build-local PROJ=<新プロジェクト名> MAIN=main.tex LATEX_PROJECTS_DIR=$PAPERS
```

---

## latexmkrc について

**原則として `latexmkrc` は変更しない。**

ビルドエラーが発生しても、まず他の原因（パッケージ不足・ファイルパス・エンコーディング等）を調査する。
`latexmkrc` の変更が必要と判断した場合は、**変更内容と理由をユーザーに確認してから**行う。

典型的な日本語 LaTeX プロジェクトの `latexmkrc` 例：

```perl
$ENV{'TZ'} = 'Asia/Tokyo';
$latex     = 'platex';
$bibtex    = 'pbibtex';
$dvipdf    = 'dvipdfmx %O -o %D %S';
$makeindex = 'mendex %O -o %D %S';
$pdf_mode  = 3;
$out_dir   = 'build';
```

---

## よくあるエラーと対処

| エラー | 原因 | 対処 |
|---|---|---|
| `project not found: .../projects/<PROJ>` | LATEX_PROJECTS_DIR が未指定または間違い | `LATEX_PROJECTS_DIR=$PAPERS` を渡す |
| `platform mismatch (arm64 vs amd64)` | Apple Silicon の警告 | 無視してよい（動作する） |
| `latexmkrc not found` | プロジェクトに latexmkrc がない | latexmkrc の存在を確認 |
| `Overfull \hbox` | 行幅オーバー | 警告のみ。PDF は生成される |
