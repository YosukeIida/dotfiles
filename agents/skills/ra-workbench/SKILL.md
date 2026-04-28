---
name: ra-workbench
description: >
  RA（リサーチアシスタント）の月次書類自動生成ツール ra-workbench の操作スキル。
  「今月の export して」「reschedule して」「何時間入ってる？」「計画を見直したい」など
  ra-workbench に関する操作・確認・生成依頼があったときに発動する。
  作業ディレクトリは ~/workspace/github.com/YosukeIida/ra-workbench。
---

# ra-workbench 操作スキル

## コマンドリファレンス

### export（毎月）

```bash
# xlsx のみ
uv run ra-workbench export --year YYYY --month MM

# PDF も生成（macOS/Windows: Excel を使用）
uv run ra-workbench export --year YYYY --month MM --pdf

# PDF も生成（LibreOffice を使用: Docker 等）
uv run ra-workbench export --year YYYY --month MM --pdf --libreoffice

# 年またぎ（1〜3月）は --fy を明示（省略時は自動判定）
uv run ra-workbench export --year 2027 --month 1 --fy 2026 --pdf
```

PDF バックエンド:
- `--pdf` のみ → Excel（xlwings 経由、macOS: AppleScript / Windows: COM）
- `--pdf --libreoffice` → LibreOffice headless

### reschedule（計画修正）

```bash
uv run ra-workbench reschedule --fy YYYY --start-month MM
uv run ra-workbench reschedule --fy YYYY --start-month MM --end-month MM
```

- `submission_source` の reference ファイルを直接上書き（start_month 以前は変更しない）
- `--remaining-hours` 省略で `max_hours - スキップ月実績` を自動計算
- `--end-month` で特定月以降を空けられる（例: `--end-month 2` で3月は空）

### plan（年初1回）

```bash
uv run ra-workbench plan --fy YYYY
```

テンプレートから `output/3-RA勤務時間計画書_YYYY_自動入力済.xlsx` を生成。
事務提出 → 署名付きで返送 → reference に配置 → `submission_source` に設定。

### init（新年度セットアップ）

```bash
uv run ra-workbench init --fy YYYY
```

`data/example/config.toml` を `data/YYYY/config.toml` にコピー。

---

## reference ファイルの入力状況を確認する

```python
uv run python - <<'EOF'
import openpyxl
from src.ra_workbench.core.plan import _read_used_hours_from_sheet
from src.ra_workbench.core.config import load_config
from pathlib import Path

config = load_config(Path("data/2026/config.toml"))
wb = openpyxl.load_workbook(str(config.paths.submission_source), data_only=True)
total = 0.0
for sheet in wb.sheetnames:
    if "月" in sheet:
        h = _read_used_hours_from_sheet(wb[sheet])
        total += h
        print(f"  {sheet}: {h:.0f}h")
print(f"合計: {total:.0f}h / {config.fiscal_year.max_hours:.0f}h")
EOF
```

---

## よくある操作パターン

### 今月の書類を PDF 付きで出力（macOS ローカル）

```bash
uv run ra-workbench export --year 2026 --month 5 --pdf
```

### 5月以降を再計算（3月は空ける）

```bash
uv run ra-workbench reschedule --fy 2026 --start-month 5 --end-month 2
# max_hours - 4月実績 を自動計算して5月〜2月に均等配分
```

### 年初フロー（年度最初の一連の作業）

```bash
uv run ra-workbench init --fy 2027
# config.toml を編集...
uv run ra-workbench plan --fy 2027
# → output/ の xlsx を事務に提出
# → 署名入りファイルが返送されたら reference/ に配置
# → config.toml の submission_source に設定
uv run ra-workbench reschedule --fy 2027 --start-month 5 --end-month 2
```

---

## ファイルパス早見表

| パス | 内容 |
|---|---|
| `data/2026/config.toml` | 個人設定（gitignore） |
| `data/2026/reference/` | 事務返送ファイル・原本 |
| `data/2026/output/` | 生成物（gitignore） |
| `data/templates/` | Excel テンプレート |
| `data/example/config.toml` | 設定サンプル |

## config.toml キー早見表

| キー | 説明 |
|---|---|
| `fiscal_year.max_hours` | 年間上限時間 |
| `fiscal_year.allocation` | 月配分モード（`even` / `front_load` / `mixed`） |
| `fiscal_year.front_load_months` | mixed 時に前詰めにする月（例: `[4]`） |
| `fiscal_year.month_fill_mode` | 月内分散（`spread` 推奨 / `front`） |
| `paths.submission_source` | 署名入り reference ファイルのパス |
| `avoid_dates` | 勤務しない日（`["YYYY-MM-DD", ...]`） |
