#!/usr/bin/env bash
# Stop hook: dotfiles の未コミット変更を検知してリマインドする。
# ~/.claude/settings.json 等は dotfiles への symlink のため、/plugin や /model の
# 操作で live 側だけが書き換わる。「変更後は必ず commit」原則の再発防止用。
# ブロックはしない（systemMessage を表示するだけで exit 0）。

DOTFILES="$HOME/workspace/github.com/YosukeIida/dotfiles"

dirty_count=$(git -C "$DOTFILES" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ "${dirty_count:-0}" -gt 0 ]; then
  files=$(git -C "$DOTFILES" status --porcelain 2>/dev/null | head -3 | awk '{print $2}' | tr '\n' ' ')
  printf '{"systemMessage": "⚠ dotfiles に未コミット変更が %s 件あります（%s…）。symlink 管理のため commit を忘れずに。"}\n' \
    "$dirty_count" "$files"
fi

exit 0
