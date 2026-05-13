#!/usr/bin/env bash
# Claude Code マルチアカウントセットアップ
# 使い方: ./setup-account.sh [アカウント番号]
# 例:     ./setup-account.sh 2
set -euo pipefail

N=${1:-2}
BASE="$HOME/.claude"
DIR="$HOME/.claude-$N"
DOTFILES_CLAUDE="$HOME/workspace/github.com/YosukeIida/dotfiles/claude"

# dotfiles から直接 symlink（各アカウント独立）
DOTFILES_LINKS=(settings.api.json settings.subscription.json get_key.sh statusline.sh CLAUDE.md)

# account 1 (~/.claude) から共有する項目
SHARED_FROM_BASE=(projects skills todos plans history.jsonl)

echo "Setting up: $DIR"
mkdir -p "$DIR"

for item in "${DOTFILES_LINKS[@]}"; do
  src="$DOTFILES_CLAUDE/$item"
  dst="$DIR/$item"
  if [[ ! -e "$src" ]]; then
    echo "  skip (not in dotfiles): $item"
    continue
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "  skip (exists): $item"
    continue
  fi
  ln -s "$src" "$dst"
  echo "  linked (dotfiles): $item"
done

for item in "${SHARED_FROM_BASE[@]}"; do
  src="$BASE/$item"
  dst="$DIR/$item"
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "  skip (not found): $item"
    continue
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "  skip (exists): $item"
    continue
  fi
  ln -s "$src" "$dst"
  echo "  linked (shared): $item"
done

# settings.json → 同ディレクトリ内の subscription に向ける（連鎖しない）
if [[ ! -e "$DIR/settings.json" && ! -L "$DIR/settings.json" ]]; then
  ln -s "$DIR/settings.subscription.json" "$DIR/settings.json"
  echo "  linked: settings.json -> settings.subscription.json"
fi

if [[ ! -f "$DIR/anthropic.env" ]]; then
  echo ""
  echo "  [INFO] API モードを使う場合は以下を作成:"
  echo "  echo 'export ANTHROPIC_API_KEY=\"sk-ant-...\"' > $DIR/anthropic.env"
  echo "  chmod 600 $DIR/anthropic.env"
fi

echo ""
echo "Done. Next: log in with account $N"
echo "  CLAUDE_CONFIG_DIR=$DIR claude /login"
