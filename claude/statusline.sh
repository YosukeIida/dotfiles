#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Claude Code Statusline v7
#
#  Line 1: model  │  ctx [bar] XX%
#  Line 2: 5h [bar] XX% ↻HH:MM:SS  │  7d [bar] XX% ↻HH:MM:SS
#  Line 3: repo  branch  +add -del
#
#  Pro/Max : stdin JSON の rate_limits フィールドを使用
#  Team    : keychain → /api/oauth/usage API 呼び出し（5分キャッシュ）
#  API Key : "API Key" 表示
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

input=$(cat)

# ── ANSI helpers ─────────────────────────────────────────────
fg()  { printf '\033[38;5;%dm' "$1"; }
bg()  { printf '\033[48;5;%dm' "$1"; }
rst() { printf '\033[0m'; }
bld() { printf '\033[1m'; }

# ── True color gradient (green → yellow → red) ───────────────
gradient() {
  local p=${1:-0}
  local r g
  if [ "$p" -lt 50 ]; then
    r=$(( p * 5 ))
    printf '\033[38;2;%d;200;80m' "$r"
  else
    g=$(( 200 - (p - 50) * 4 ))
    [ "$g" -lt 0 ] && g=0
    printf '\033[38;2;255;%d;60m' "$g"
  fi
}

# ── Fine Bar: sub-block + ▒ (~1% precision, width=10) ────────
bar_fine() {
  local p=${1:-0} w=10
  local BLOCKS=( ' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉' '█' )
  local steps=$(( p * w * 8 / 100 ))
  local full=$(( steps / 8 ))
  local frac=$(( steps % 8 ))
  local empty=$(( w - full - 1 ))
  local i
  printf '%s' "$(gradient "$p")"
  for ((i=0;i<full;i++)); do printf '█'; done
  printf '%s' "${BLOCKS[$frac]}"
  printf '\033[38;5;242m'
  for ((i=0;i<empty;i++)); do printf '▒'; done
  printf '%s' "$(rst)"
}

# ── Seconds remaining → HH:MM:SS ─────────────────────────────
fmt_hms() {
  local s=${1:-0}
  [ "$s" -le 0 ] && { printf 'now'; return; }
  printf '%02d:%02d:%02d' "$(( s/3600 ))" "$(( s%3600/60 ))" "$(( s%60 ))"
}

# ── Unix timestamp → HH:MM:SS remaining ──────────────────────
fmt_hms_unix() {
  local ts="$1"
  [ -z "$ts" ] || [ "$ts" = "null" ] && { printf '—'; return; }
  fmt_hms "$(( ts - $(date +%s) ))"
}

# ── ISO 8601 → HH:MM:SS remaining ────────────────────────────
fmt_hms_iso() {
  local iso="$1"
  [ -z "$iso" ] || [ "$iso" = "null" ] && { printf '—'; return; }
  local ts
  ts=$(date -jf "%Y-%m-%dT%H:%M:%S" "${iso%%.*}" "+%s" 2>/dev/null) || { printf '—'; return; }
  fmt_hms "$(( ts - $(date +%s) ))"
}

# ── 区切り文字（同一bg内で使用）─────────────────────────────
div() { printf "$(fg 240) │ $(rst)"; }


# ═══════════════════════════════════════════════════════════════
# Extract data from stdin JSON
# ═══════════════════════════════════════════════════════════════
MODEL=$(echo "$input" | jq -r '.model.display_name // "—"')
CWD=$(echo "$input"   | jq -r '.workspace.current_dir // ""')
CTX=$(echo "$input"   | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[ -z "$CTX" ] || [ "$CTX" = "null" ] && CTX=0

REPO=$(basename "${CWD:-.}" 2>/dev/null || echo "—")

# Git: branch + 実際の変更行数
BR=""; GIT_ADD=0; GIT_DEL=0
if command -v git &>/dev/null && [ -n "$CWD" ]; then
  if git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
    BR=$(git -C "$CWD" branch --show-current 2>/dev/null)
    if [ -n "$BR" ]; then
      while IFS=$'\t' read -r a d _; do
        [[ "$a" =~ ^[0-9]+$ ]] && GIT_ADD=$(( GIT_ADD + a ))
        [[ "$d" =~ ^[0-9]+$ ]] && GIT_DEL=$(( GIT_DEL + d ))
      done < <(
        git -C "$CWD" diff --numstat 2>/dev/null
        git -C "$CWD" diff --cached --numstat 2>/dev/null
      )
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Rate limits — Pro/Max: stdin JSON, Team: API fallback
# ═══════════════════════════════════════════════════════════════
F5=0; F5T="—"; S7=0; S7T="—"
RATE_SOURCE="none"

HAS_RL=$(echo "$input" | jq -r '.rate_limits // empty')

if [ -n "$HAS_RL" ]; then
  F5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
  S7=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
  F5R=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  S7R=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  [ -z "$F5" ] || [ "$F5" = "null" ] && F5=0
  [ -z "$S7" ] || [ "$S7" = "null" ] && S7=0
  F5T=$(fmt_hms_unix "$F5R")
  S7T=$(fmt_hms_unix "$S7R")
  RATE_SOURCE="stdin"
else
  _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if jq -e '.apiKeyHelper' "$_cfg" >/dev/null 2>&1; then
    RATE_SOURCE="apikey"
  else
    RATE_SOURCE="api"
    _cfg_dir="${CLAUDE_CONFIG_DIR:-}"
    if [ -z "$_cfg_dir" ]; then
      _keychain_svc="Claude Code-credentials"
    else
      _suffix=$(python3 -c "import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])" "$_cfg_dir" 2>/dev/null)
      _keychain_svc="Claude Code-credentials-${_suffix}"
    fi

    _cache_key=$(echo "$_keychain_svc" | tr -dc 'a-zA-Z0-9')
    _cache_dir="${TMPDIR:-/tmp}/claude-sl"
    _cache_file="${_cache_dir}/${_cache_key}.json"
    _ttl=300

    _need_fetch=true
    if [ -f "$_cache_file" ]; then
      _age=$(( $(date +%s) - $(stat -f%m "$_cache_file" 2>/dev/null || echo 0) ))
      [ "$_age" -lt "$_ttl" ] && _need_fetch=false
    fi

    if [ "$_need_fetch" = true ]; then
      _tok=$(security find-generic-password -s "$_keychain_svc" -w 2>/dev/null \
        | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [ -n "$_tok" ]; then
        mkdir -p "$_cache_dir"
        _resp=$(curl -s --max-time 4 \
          -H "Authorization: Bearer $_tok" \
          -H "anthropic-beta: oauth-2025-04-20" \
          "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if echo "$_resp" | jq -e '.five_hour and .seven_day' >/dev/null 2>&1; then
          echo "$_resp" > "$_cache_file"
        fi
      fi
    fi

    if [ -f "$_cache_file" ]; then
      F5=$(jq -r '.five_hour.utilization // 0' "$_cache_file" 2>/dev/null | cut -d. -f1)
      S7=$(jq -r '.seven_day.utilization // 0' "$_cache_file" 2>/dev/null | cut -d. -f1)
      F5R=$(jq -r '.five_hour.resets_at // empty' "$_cache_file" 2>/dev/null)
      S7R=$(jq -r '.seven_day.resets_at // empty' "$_cache_file" 2>/dev/null)
      [ -z "$F5" ] || [ "$F5" = "null" ] && F5=0
      [ -z "$S7" ] || [ "$S7" = "null" ] && S7=0
      F5T=$(fmt_hms_iso "$F5R")
      S7T=$(fmt_hms_iso "$S7R")
    else
      RATE_SOURCE="none"
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Account / Org info from .claude.json
# ═══════════════════════════════════════════════════════════════
_cfg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
_claude_json="$_cfg_dir/.claude.json"
ORG=""
if [ -f "$_claude_json" ]; then
  ORG=$(python3 - "$_claude_json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    oa = d.get("oauthAccount") or {}
    name = oa.get("organizationName") or oa.get("emailAddress") or ""
    print(name)
except Exception:
    pass
PY
2>/dev/null)
fi

# ═══════════════════════════════════════════════════════════════
# Line 1 —  model  │  ctx [bar] XX%
# ═══════════════════════════════════════════════════════════════
BG1=237
L1="$(bg $BG1)"
L1+="$(fg 183)$(bld) ${MODEL} $(rst)"
L1+="$(bg $BG1)$(div)"
L1+="$(bg $BG1)$(fg 245) ctx "
L1+="$(bar_fine "$CTX")$(rst)"
L1+="$(bg $BG1)$(gradient "$CTX")$(bld) ${CTX}%$(rst)"
L1+="$(bg $BG1) $(rst)"

# ═══════════════════════════════════════════════════════════════
# Line 2 —  5h [bar] XX% ↻HH:MM:SS  │  7d [bar] XX% ↻HH:MM:SS
# ═══════════════════════════════════════════════════════════════
TERM_W=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f2)
[ -z "$TERM_W" ] || [ "$TERM_W" = "0" ] && TERM_W=$(tput cols 2>/dev/null)
[ -z "$TERM_W" ] || [ "$TERM_W" = "0" ] && TERM_W=${COLUMNS:-80}
BG2=236
L2="$(bg $BG2)"

# TERM_W < 60: バー省略コンパクト表示（~36 chars）
# TERM_W >= 60: バーありフル表示（~58 chars）
if [ "$RATE_SOURCE" = "stdin" ] || [ "$RATE_SOURCE" = "api" ]; then
  L2+="$(fg 245) 5h "
  L2+="$(bar_fine "$F5")$(rst)"
  L2+="$(bg $BG2)$(gradient "$F5")$(bld) ${F5}%$(rst)"
  L2+="$(bg $BG2)$(fg 243) ↻${F5T}$(rst)"
  L2+="$(bg $BG2)$(div)"
  L2+="$(bg $BG2)$(fg 245)7d "
  L2+="$(bar_fine "$S7")$(rst)"
  L2+="$(bg $BG2)$(gradient "$S7")$(bld) ${S7}%$(rst)"
  L2+="$(bg $BG2)$(fg 243) ↻${S7T}$(rst)"
elif [ "$RATE_SOURCE" = "apikey" ]; then
  L2+="$(fg 245) API Key$(rst)"
else
  L2+="$(fg 75) Team$(rst)"
fi
if [ -n "$ORG" ]; then
  L2+="$(bg $BG2)$(div)"
  L2+="$(bg $BG2)$(fg 183) ${ORG}$(rst)"
fi
L2+="$(bg $BG2) $(rst)"

# ═══════════════════════════════════════════════════════════════
# Line 3 —  repo  branch  +add -del
# ═══════════════════════════════════════════════════════════════
BG3=235
L3="$(bg $BG3)"
L3+="$(fg 75)$(bld) ${REPO}$(rst)"
if [ -n "$BR" ]; then
  L3+="$(bg $BG3)$(div)"
  L3+="$(bg $BG3)$(fg 114) ${BR}$(rst)"
  if [ "$(( GIT_ADD + GIT_DEL ))" -gt 0 ]; then
    L3+="$(bg $BG3)$(fg 240)  "
    [ "$GIT_ADD" -gt 0 ] && L3+="$(fg 114)+${GIT_ADD}"
    [ "$GIT_ADD" -gt 0 ] && [ "$GIT_DEL" -gt 0 ] && L3+="$(fg 240) "
    [ "$GIT_DEL" -gt 0 ] && L3+="$(fg 203)-${GIT_DEL}"
    L3+="$(rst)"
  fi
fi
L3+="$(bg $BG3) $(rst)"

# ═══════════════════════════════════════════════════════════════
# 各行を TERM_W 可視列で切り詰め（折り返し防止）
printf '%b\n%b\n%b' "$L1" "$L2" "$L3" | python3 -c "
import sys, re
def trunc(s, w):
    out, cols, i = [], 0, 0
    while i < len(s):
        m = re.match(r'\x1b\[[0-9;:]*[mK]', s[i:])
        if m:
            out.append(m.group())
            i += len(m.group())
        else:
            if cols < w:
                out.append(s[i])
                cols += 1
            i += 1
    return ''.join(out)
w = int(sys.argv[1])
for line in sys.stdin:
    print(trunc(line.rstrip('\n'), w))
" "$TERM_W"
