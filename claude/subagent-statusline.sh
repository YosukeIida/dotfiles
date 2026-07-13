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
# → "Sonnet 5" / "Opus 4.8" / "Haiku 4.5" のようにバージョン込みの表示名に組み立てる。
# 日付サフィックス（8桁数字）は捨てる。未知のfamilyはIDをそのまま表示。
model_label() {
  local rest="${1#*claude-}"
  IFS='-' read -ra parts <<< "$rest"
  local family="${parts[0]:-}"
  local fam_disp
  case "$family" in
    opus)   fam_disp="Opus" ;;
    sonnet) fam_disp="Sonnet" ;;
    haiku)  fam_disp="Haiku" ;;
    fable)  fam_disp="Fable" ;;
    *)      echo "$1"; return ;;
  esac

  local ver=() i p
  for ((i = 1; i < ${#parts[@]}; i++)); do
    p="${parts[$i]}"
    [[ "$p" =~ ^[0-9]{8}$ ]] && continue   # 日付サフィックスは除外
    ver+=("$p")
  done

  if [ "${#ver[@]}" -gt 0 ]; then
    local ver_str
    ver_str=$(IFS=.; echo "${ver[*]}")
    echo "${fam_disp} ${ver_str}"
  else
    echo "$fam_disp"
  fi
}

echo "$input" | jq -c '.tasks // [] | .[]' | while IFS= read -r task; do
  ID=$(echo "$task" | jq -r '.id')
  MODEL=$(echo "$task" | jq -r '.model // empty')
  [ -z "$MODEL" ] && continue   # 未解決なら行を出力せずデフォルト表示に委ねる

  NAME=$(echo "$task"   | jq -r '.name // "agent"')
  TOKENS=$(echo "$task" | jq -r '.tokenCount // 0')
  CTXSZ=$(echo "$task"  | jq -r '.contextWindowSize // 0')

  DISP=$(model_label "$MODEL")

  PCT=""
  if [ "$CTXSZ" -gt 0 ] 2>/dev/null; then
    PCT=$(( TOKENS * 100 / CTXSZ ))
  fi

  # 本体側が既に status アイコン（○/●等）を表示しているので、ここでは重複させない
  LINE="$(bld)${NAME}$(rst) $(fg 183)[${DISP}]$(rst)"
  [ -n "$PCT" ] && LINE+="$(fg 245) ctx ${PCT}%$(rst)"

  jq -nc --arg id "$ID" --arg content "$LINE" '{id: $id, content: $content}'
done
