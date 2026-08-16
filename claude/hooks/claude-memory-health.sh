#!/usr/bin/env bash
# claude-memory の同期健全性を SessionStart で知らせる。
#
# 鳴らす条件は2つだけ:
#   1. status が blocked_* — 人が動かないと解けない状態
#   2. 最終成功が古い    — status が正常でも同期が届いていない
#
# **未コミットの memory では鳴らさない。** memory が dirty なのは正常な状態であり、
# 毎セッション警告すると狼少年になって他の警告まで効かなくなる（decision-002）。
#
# 状態ファイルは machine-local で、実装は private overlay にある。
# public dotfiles は private が無くても壊れてはいけないので、
# 状態ファイルが無ければ何も出さずに正常終了する。
set -uo pipefail

STATE_FILE="${CLAUDE_MEMORY_STATE_DIR:-$HOME/.local/state/claude-memory-sync}/state-v1.json"
STALE_DAYS="${CLAUDE_MEMORY_STALE_DAYS:-7}"

[ -f "$STATE_FILE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# フィールドごとに引く。1行にまとめて split すると last_error のスペースで壊れる。
jqf() { jq -r "$1" "$STATE_FILE" 2>/dev/null || printf ''; }
status="$(jqf '.status // empty')"
last_success="$(jqf '.last_success // "-"')"
ahead="$(jqf '.ahead // 0')"
behind="$(jqf '.behind // 0')"
last_error="$(jqf '(.last_error // "-") | gsub("[\\n\\r\\t]"; " ")')"
[ -n "$status" ] || exit 0

days=""
if [ "$last_success" != "-" ]; then
  then_s="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_success" +%s 2>/dev/null || printf '')"
  [ -n "$then_s" ] && days="$(( ( $(date -u +%s) - then_s ) / 86400 ))"
fi

msg=""
case "$status" in
  blocked_conflict)
    msg="claude-memory の同期が衝突で止まっています。dotfiles-private で解消してください（${last_error}）" ;;
  blocked_auth)
    msg="claude-memory の同期が認証で失敗しています（${last_error}）" ;;
  blocked_identity)
    msg="claude-memory が identity の不整合で止まっています。claude-memory.sh inventory で確認してください" ;;
esac

if [ -z "$msg" ] && [ -n "$days" ] && [ "$days" -gt "$STALE_DAYS" ]; then
  msg="claude-memory の最終同期成功が ${days} 日前です（status=${status}）。同期が届いていない可能性があります"
fi

[ -n "$msg" ] || exit 0

if [ "$last_success" != "-" ]; then
  msg="${msg}｜最終成功 $last_success"
  [ -n "$days" ] && msg="${msg}（${days}日前）"
else
  msg="${msg}｜同期成功の記録なし"
fi
msg="${msg}｜ahead $ahead / behind $behind"

printf '{"systemMessage": "⚠ %s"}\n' "$msg"
exit 0
