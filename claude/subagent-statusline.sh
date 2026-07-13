#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Claude Code Subagent Statusline
#
#  agent panel の各 task 行に resolved model 名 + context% を表示する。
#  subagentStatusLine の入力: {columns, tasks: [{id,name,type,status,
#  description,label,startTime,model,contextWindowSize,tokenCount,
#  tokenSamples,cwd}, ...], ...common hook fields}
#
#  出力契約: task ごとに {"id": "<id>", "content": "<行の中身>"} を
#  1行のJSONとしてstdoutへ。id を省略した task はデフォルト表示
#  （name · description · token count）のまま残る。
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

input=$(cat)

fg()  { printf '\033[38;5;%dm' "$1"; }
rst() { printf '\033[0m'; }
bld() { printf '\033[1m'; }

# resolved model ID (例: claude-sonnet-5, claude-opus-4-8, claude-haiku-4-5-20251001)
# → 表示名。未知のIDはそのまま表示（将来の新モデルにも安全に対応）
model_label() {
  case "$1" in
    *opus*)   echo "Opus" ;;
    *sonnet*) echo "Sonnet" ;;
    *haiku*)  echo "Haiku" ;;
    *fable*)  echo "Fable" ;;
    *)        echo "$1" ;;
  esac
}

status_icon() {
  case "$1" in
    running)   echo "▸" ;;
    completed) echo "✓" ;;
    failed)    echo "✗" ;;
    *)         echo "•" ;;
  esac
}

echo "$input" | jq -c '.tasks // [] | .[]' | while IFS= read -r task; do
  ID=$(echo "$task" | jq -r '.id')
  MODEL=$(echo "$task" | jq -r '.model // empty')
  [ -z "$MODEL" ] && continue   # 未解決なら行を出力せずデフォルト表示に委ねる

  NAME=$(echo "$task"   | jq -r '.name // "agent"')
  STATUS=$(echo "$task" | jq -r '.status // ""')
  TOKENS=$(echo "$task" | jq -r '.tokenCount // 0')
  CTXSZ=$(echo "$task"  | jq -r '.contextWindowSize // 0')

  DISP=$(model_label "$MODEL")
  ICON=$(status_icon "$STATUS")

  PCT=""
  if [ "$CTXSZ" -gt 0 ] 2>/dev/null; then
    PCT=$(( TOKENS * 100 / CTXSZ ))
  fi

  LINE="$(fg 245)${ICON}$(rst) $(bld)${NAME}$(rst) $(fg 183)[${DISP}]$(rst)"
  [ -n "$PCT" ] && LINE+="$(fg 245) ctx ${PCT}%$(rst)"

  jq -nc --arg id "$ID" --arg content "$LINE" '{id: $id, content: $content}'
done
