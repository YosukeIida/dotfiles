#!/usr/bin/env bash
# launchd から定期的に呼ぶ。~/.claude/projects の transcript のうち、更新が IDLE 秒以上
# 止まっていて未処理の行があるものを knowledge-digest に流す。
# 作業中のセッションを読まないのは、途中の結論を knowledge に書かないため。
set -u

K="${KNOWLEDGE_DIR:-}"
[ -n "$K" ] && [ -d "$K/.git" ] || { echo "$(date +%FT%T) KNOWLEDGE_DIR が無いので何もしない"; exit 0; }
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/knowledge-digest"
IDLE="${KNOWLEDGE_DIGEST_IDLE_SEC:-1800}"
MIN_BYTES=51200
mkdir -p "$STATE"

# 前の回がまだ動いていたら何もしない
lock="$STATE/sweep.lock"
mkdir "$lock" 2>/dev/null || { echo "$(date +%FT%T) 前の回が動いているので飛ばす"; exit 0; }
trap 'rmdir "$lock"' EXIT

# 入れた時点より前に止まったセッションは対象にしない。
# ponytail: 入れる前からあるセッションを再開すると、未処理の記録が無いので先頭から読む。費用は 7 日の上限で抑える
since="$STATE/since"
[ -f "$since" ] || touch "$since"

# ほかの Mac が書いた分を先に取り込み、同じノートを別々に書き直すのを避ける
git -C "$K" pull -q --rebase --autostash || { echo "$(date +%FT%T) pull に失敗したので止める" >&2; exit 1; }

now=$(date +%s)
for f in "$HOME"/.claude/projects/*/*.jsonl; do
  [ -f "$f" ] && [ "$f" -nt "$since" ] || continue
  [ $((now - $(stat -f%m "$f"))) -ge "$IDLE" ] || continue
  [ "$(stat -f%z "$f")" -ge "$MIN_BYTES" ] || continue
  "$(dirname "$0")/knowledge-digest.sh" "$f" < /dev/null
  rc=$?
  [ "$rc" -eq 3 ] && break
  [ "$rc" -ne 0 ] && echo "$(date +%FT%T) 失敗: $f (rc=$rc)" >&2
done

# 書いた分を push して、両方の Mac の knowledge を揃える。衝突したら止めて人に渡す
if [ -n "$(git -C "$K" log --oneline @{u}..HEAD 2>/dev/null)" ]; then
  if ! git -C "$K" pull -q --rebase --autostash; then
    git -C "$K" rebase --abort 2>/dev/null
    echo "$(date +%FT%T) rebase で衝突したので push しない。手で解消する" >&2
    exit 1
  fi
  git -C "$K" push -q || { echo "$(date +%FT%T) push に失敗した" >&2; exit 1; }
fi
exit 0
