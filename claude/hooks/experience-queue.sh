#!/usr/bin/env bash
# SessionEnd / PreCompact hook: wrap-up されていないセッションの transcript を
# $EXPERIENCE_DIR/.queue.tsv に記録する（LLM 呼び出しなし・1秒未満）。
# 通知は experience-inject.sh が索引の冒頭に1行足すことで行う。
# 消し込みは /wrap-up skill が担当する。
set -u
[ -n "${EXPERIENCE_DIR:-}" ] && [ -d "${EXPERIENCE_DIR:-}" ] || exit 0

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$sid" ] || exit 0

# 小さい transcript（headless の一発実行・雑談）は積まない。全セッションを積むと
# 通知が数日で壁紙化する（Obsidian 調査で確認済みの失敗型）。閾値は 50KB。
if [ -n "$tp" ] && [ -f "$tp" ]; then
  sz=$(stat -f%z "$tp" 2>/dev/null || echo 0)
  [ "${sz:-0}" -lt 51200 ] && exit 0
fi

q="$EXPERIENCE_DIR/.queue.tsv"
# 同一セッションの重複（PreCompact→SessionEnd 等）は1行に保つ
grep -q "^$sid	" "$q" 2>/dev/null && exit 0
printf '%s\t%s\t%s\t%s\n' "$sid" "$tp" "$cwd" "$(date +%Y-%m-%dT%H:%M)" >> "$q"
exit 0
