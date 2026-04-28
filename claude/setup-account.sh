#!/usr/bin/env bash
# Claude Code マルチアカウントセットアップ
# 使い方: ./setup-account.sh [アカウント番号]
# 例:     ./setup-account.sh 2
set -euo pipefail

N=${1:-2}
BASE="$HOME/.claude"
DIR="$HOME/.claude-$N"

# 共有するファイル・ディレクトリ（source が存在するものだけ symlink する）
SHARED=(
  projects
  settings.json
  settings.api.json
  settings.subscription.json
  CLAUDE.md
  skills
  get_key.sh
  statusline.sh
  todos
  plans
  history.jsonl
)

echo "Setting up: $DIR"
mkdir -p "$DIR"

for item in "${SHARED[@]}"; do
  src="$BASE/$item"
  dst="$DIR/$item"
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "  skip (not found): $item"
    continue
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "  skip (already exists): $item"
    continue
  fi
  ln -s "$src" "$dst"
  echo "  linked: $item -> $src"
done

echo ""
echo "Done. Next: log in with account $N"
echo "  CLAUDE_CONFIG_DIR=$DIR claude /login"
