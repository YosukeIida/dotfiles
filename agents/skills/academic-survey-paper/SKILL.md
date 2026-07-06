---
name: academic-survey-paper
description: >
  Markdown + BibTeX で学術サーベイ論文を書き、PDF に仕上げるフル工程スキル。
  文献収集（Exa MCP）→ bib 管理 → 章別 md ドラフト → 内部整合チェック →
  CREST 等外部資金ブリッジ文書 → PDF コンパイル（pandoc + lualatex + bibtex）
  の一連を担う。以下の場面で発動せよ：
  新規サーベイ論文の立ち上げ / 章追加・改訂 / 文献追加 / PDF 生成 /
  外部資金申請書への知見転記キュー管理
  ※単発の『PDF をビルドして』『コンパイルして』は latex-devkit が担当。本 skill はサーベイ論文プロジェクトの全工程管理でのみ発動する。
---

# Academic Survey Paper（Markdown サーベイ論文工程スキル）

実証済み工程：`rs-thinking-like-me`（D×M フレームワーク、2026-05）

---

## ディレクトリ構造（テンプレート）

```
<project>/
├── CLAUDE.md                    # 運用ルール（変更禁止資産の明示など）
├── PROGRESS.md                  # 章 STATUS + ref.bib 本数 + タスク一覧
├── paper/
│   ├── metadata.yaml            # pandoc ビルド設定
│   ├── ref.bib                  # 単一集中 bib（章別分割しない）
│   ├── ref_clean.bib            # PDF ビルド用（note フィールド除去済み）
│   ├── sections/
│   │   ├── 00_abstract.md
│   │   ├── 01_intro.md
│   │   └── ...（章数分）
│   └── fig/
├── literature/<分野>/           # PDF 格納（分野サブディレクトリ）
│   └── _manual_todo.md          # 手動 DL 待ちキュー
├── notes/<bibkey>.md            # 1 論文 = 1 読解ノート
├── search_logs/YYYY-MM-DD_<topic>.md
└── crest_bridge/
    └── claims_to_propagate.md   # 外部資金申請への逆流入キュー
```

---

## Phase 0：プロジェクト立ち上げ

### 1. 論文設計（着手前に確定）

- **論点骨格（Argument Flow）**：A1→A2→...→An の論証チェーンをまず書く
- **章構成**：各章に「中心論点・引用領域・想定頁数」を割り当てる
- **最重要章の特定**：全章の中で「本論文固有の主張」が集中する章を 1 つ指定し、そこから着手する
- **記号の事前設計**：数式・略語の衝突を事前に洗い出す（例：M_i vs M）

### 2. ディレクトリ作成・stub ファイル生成

各 `sections/NN_<topic>.md` の冒頭に `<!-- STATUS: stub -->` を記述して作成。

---

## Phase 1：文献収集（Exa MCP 3 レイヤ戦略）

### 検索前に必ずやること

`search_logs/YYYY-MM-DD_<topic>.md` に**クエリの意図を先に日本語で書いてから**実行。

### 3 レイヤ

| レイヤ | 目的 | 件数目安 |
|---|---|---|
| L1 既存サーベイ | 「survey/review 2023..2026」で全体地図を把握 | 10 件 |
| L2 概念キーワード | 各章の中心概念を直接検索 | 15 件 |
| L3 隣接概念 | 意外な接続先を探す（全期間） | 10 件 |

### 採否 3 段階と DL 優先度

即採用 / 保留 / 却下 を検索ログ内で明示。

DL 優先度：
1. arXiv → 自動（abs URL → `/pdf/<id>.pdf`）
2. OpenReview / PMC / ACL Anthology → URL パターンで自動
3. 著者個人サイト → WebFetch で試行
4. IEEE / Elsevier / Springer → `_manual_todo.md` に記録してユーザに一括依頼

### bib エントリ命名規則

```
bibkey = firstauthor_year（例：mischel_1995）
PDF ファイル名も同一（例：mischel_1995_caps.pdf）
```

重複確認：`grep "firstauthor_year" ref.bib` で事前確認。

---

## Phase 2：章ドラフト執筆

### 各章 md の構造

```markdown
<!-- STATUS: stub|draft|done -->
# 第N章 タイトル

## N.1 節タイトル

本文。引用は \citep{bibkey} 形式。...

---

## 引用文献対応表（本章）

| 内容 | bibkey |
|---|---|
| 内容の説明 | \citep{bibkey} |
```

### 引用コマンド使い分け

| コマンド | 出力例 | 使い場面 |
|---|---|---|
| `\citep{key}` | (著者, 年) | 括弧引用（標準） |
| `\citet{key}` | 著者 (年) | 文中に著者名を出す |
| `\citealt{key}` | 著者, 年 | 既に括弧の中に入れる場合 |

### ref.bib の note フィールドに関する重要な注意

`note` フィールドは**読解メモ用途のみ**とし、LaTeX 数式記法（`D_i`, `M_i`, `$...$` 等）を書かない。

**理由**：plainnat スタイルは `note` フィールドを参考文献リストに出力する。数式記法が入ると `_` が数式モード外で展開されて `! Missing $ inserted` エラーになる。

→ 回避策：数式を含む読解メモは `notes/<bibkey>.md` に分離して書く。

---

## Phase 3：内部整合チェック（推敲）

### Pass 1：表記統一

- STATUS を `stub` → `draft` に更新する前に全章で確認
- 軸数・章番号・数式記号の統一（例：8 軸 → 6 軸への改訂が発生した場合は全章一括置換）
- `\citep{}` 未変換の生 bibkey を grep で探す：`grep -r "bibkey" sections/` ではなく具体的に `grep -r "mischel_1995[^}]" sections/`

### Pass 2：記号・略語の初出定義チェック

読み手目線で全章を通読し、以下を確認する：

- **略語**：初出で必ず展開（例：`CAPS（Cognitive-Affective Processing System）`）
- **記号衝突**：同一文字が異なる意味を持つ場合、初出時に明示注記（例：$M_i$ はメタ認知効率、$M$ は意思決定写像）
- **数式の検索空間**：$\mathcal{D}$, $\mathcal{M}$ 等は初出時に「〇〇の集合」と定義する
- **節番号の参照**：「§N で示した」の N が実際の節番号と一致しているか

### PROGRESS.md の更新タイミング

- ref.bib のエントリ数が変わったとき
- 推敲 Pass が完了したとき
- STATUS が変わったとき

---

## Phase 4：外部資金ブリッジ文書

`crest_bridge/claims_to_propagate.md` に論文の進捗から「申請書に転記すべき知見」を蓄積する。

### CLAIM 単位の構造

```markdown
## CLAIM N — タイトル（様式番号・節番号）

**内容**：
（数式・表・箇条書き）

**様式への反映箇所**：
- 様式X「節タイトル」：具体的な書き換え指示
```

**運用ルール**：
- 3 項目たまったら申請書の該当様式を更新する（担当：PI）
- **論文プロジェクトから申請書ファイルを直接編集しない**（CLAUDE.md に明記）
- 誤記（著者名・数値・bibkey）は論文本文と同時に CLAIM も修正する

---

## Phase 5：PDF コンパイル

### 事前準備：ref_clean.bib の生成

`note` フィールドを除去した PDF ビルド専用 bib を生成する：

```python
import re

with open('ref.bib', 'r') as f:
    content = f.read()

cleaned = re.sub(r'\n\s*note\s*=\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)?\}[,]?', '', content)

with open('ref_clean.bib', 'w') as f:
    f.write(cleaned)
```

### metadata.yaml（日本語 A4 論文用）

```yaml
---
title: "論文タイトル"
subtitle: "サブタイトル（ドラフト・YYYY-MM-DD）"
author: "著者名（所属）"
date: "YYYY-MM-DD"
documentclass: ltjsarticle
classoption:
  - a4paper
  - 11pt
geometry: "top=25mm, bottom=25mm, left=25mm, right=25mm"
toc: true
toc-depth: 2
numbersections: false
natbib: true
header-includes:
  - \usepackage{amsmath}
  - \usepackage{amssymb}
  - \usepackage{booktabs}
  - \usepackage{longtable}
  - \usepackage{array}
  - \usepackage{hyperref}
  - \hypersetup{colorlinks=true, linkcolor=blue, citecolor=blue, urlcolor=blue}
  - \setlength{\parskip}{0.5em}
  - \setlength{\parindent}{1em}
---
```

### ビルド手順（4 ステップ）

```bash
cd paper/

# Step 1: pandoc で完全な standalone .tex を生成
pandoc metadata.yaml sections/0*.md \
  --pdf-engine=lualatex \
  --natbib \
  --bibliography=ref_clean.bib \
  --standalone \
  -o draft_YYYYMMDD.tex

# Step 2〜4: lualatex → bibtex → lualatex × 2
lualatex -interaction=nonstopmode draft_YYYYMMDD.tex
bibtex   draft_YYYYMMDD
lualatex -interaction=nonstopmode draft_YYYYMMDD.tex
lualatex -interaction=nonstopmode draft_YYYYMMDD.tex
```

### よくあるエラーと対処

| エラー | 原因 | 対処 |
|---|---|---|
| `! Missing $ inserted` at `.bbl` | ref.bib の `note` に数式記法 | `ref_clean.bib`（note 除去）で再ビルド |
| `Citation 'key' undefined` | bibtex が走っていない or bib パス誤り | Step 2 の bibtex を手動実行 |
| `\bibliography` が .tex に未挿入 | `--standalone` なしで `-o .tex` した | `--standalone` フラグを追加 |
| 参考文献が `?` のまま | bibtex → lualatex の pass が 1 回しかない | lualatex を計 3 回実行 |
| 表が幅をはみ出す | longtable の列幅設定なし | 表を横にして `\small` を追加 or 内容を短縮 |

---

## 読解ノートのテンプレート（`notes/<bibkey>.md`）

```markdown
# <bibkey>
- 出典: <full citation>
- PDF: literature/<分野>/<bibkey>_<短縮タイトル>.pdf
- 読了日: YYYY-MM-DD

## 要旨（3-5 行）

## 本研究との接続
- 引用する章：第 N 章 §N.M
- 引用する主張：「...」

## 反証可能性・留意点

## 引用優先度：A / B / C
```

---

## チェックリスト（章完成の判定）

- [ ] `<!-- STATUS: draft -->` に更新済み
- [ ] 節番号の参照（§N）がすべて正しい
- [ ] 略語・記号が初出時に展開されている
- [ ] `\citep{}` が生 bibkey でなく正しい形式
- [ ] 章末の「引用文献対応表」が本文の引用と整合
- [ ] ref.bib に対応エントリが存在する（`grep "bibkey" ref.bib`）
- [ ] PROGRESS.md を更新した
