# Claude Code マルチアカウント設定

複数の Claude Pro/Team アカウントを使いながら、**会話履歴・設定は一箇所に集約**するための設定。

## 設計の考え方

### `~/.claude/` の内部構造

Claude Code は `CLAUDE_CONFIG_DIR`（未設定時は `~/.claude/`）以下のファイルを読み書きする。

| ファイル/ディレクトリ | 内容 | 性質 |
|---|---|---|
| `.claude.json` | OAuth認証・アプリ状態 | **アカウント固有** |
| `session-env/` | セッショントークン | **アカウント固有** |
| `policy-limits.json` | レート制限情報 | **アカウント固有** |
| `stats-cache.json` | 使用量キャッシュ | **アカウント固有** |
| `projects/` | 会話履歴（JSONL） | **共有** |
| `settings.json` | effortLevel・プラグイン等 | **共有** |
| `settings.api.json` | API keyモード設定 | **共有**（dotfiles管理） |
| `settings.subscription.json` | サブスクモード設定 | **共有**（dotfiles管理） |
| `CLAUDE.md` | Claude への指示 | **共有**（dotfiles管理） |
| `skills/` | スキル定義 | **共有**（dotfiles管理） |
| `todos/`, `plans/` | 作業状態 | **共有** |
| `history.jsonl` | シェル履歴 | **共有** |

認証情報は `.credentials.json` ではなく `.claude.json` に格納される（OAuth方式）。

### ディレクトリ構成

```
~/.claude/          ← account 1（既存のまま、デフォルト）
~/.claude-2/        ← account 2
  .claude.json      ← account 2 の認証（/login で生成）
  projects/         → ~/.claude/projects      (symlink)
  settings.json     → ~/.claude/settings.json (symlink)
  settings.api.json → ~/.claude/settings.api.json (symlink)
  ...（その他もすべて ~/.claude/ へのsymlink）
```

`CLAUDE_CONFIG_DIR=~/.claude-2` で起動すると account 2 の認証を使いつつ、
`projects/` は `~/.claude/projects/` を参照するため会話履歴が統一される。

---

## セットアップ手順

### 1. アカウントディレクトリの作成

```bash
bash ~/workspace/github.com/YosukeIida/dotfiles/claude/setup-account.sh 2
```

3アカウント目以降も同様:

```bash
bash .../setup-account.sh 3
```

### 2. 新アカウントでログイン

```bash
CLAUDE_CONFIG_DIR=~/.claude-2 claude
```

起動後、インタラクティブセッション内で `/login` を実行。

---

## 日常の使い方

`cc` コマンドでアカウントを切り替える（zshrc に定義済み）:

```bash
cc      # account 1 に戻す（デフォルト）
cc 1    # account 1
cc 2    # account 2

claude  # 現在のアカウントで起動
```

### レート制限が来たら

```bash
cc 2 && claude
```

同じ `~/.claude/projects/` を見るため、どのアカウントから起動しても会話履歴は同じ。

---

## ファイル

| ファイル | 役割 |
|---|---|
| `setup-account.sh` | アカウントディレクトリ作成＆symlink 設定 |
| `settings.api.json` | API key モード用 settings（dotfiles管理） |
| `settings.subscription.json` | サブスクモード用 settings（dotfiles管理） |
| `get_key.sh` | API key 取得ヘルパー |
| `statusline.sh` | ステータスライン表示スクリプト |

`settings.api.json` / `settings.subscription.json` の切り替えは `claude-mode` コマンド（zshrc に定義）:

```bash
claude-mode api   # API key モードに切り替え
claude-mode sub   # サブスクリプションモードに切り替え
claude-mode       # 現在のモードを表示
```
