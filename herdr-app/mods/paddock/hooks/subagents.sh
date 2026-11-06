#!/bin/sh
# Paddock's subagent hook for Claude Code and Codex (`subagents.sh claude|codex`):
# puts each running subagent on the agent's own herdr-core terminal as a label, so
# the sidebar can list it under the agent. Both send the same fields.
#   SubagentStart  paddock.sub.<app>.<agent_id>={"app","type","at","s"}  (s: the session)
#   SubagentStop   removes it, a moment later (StopFailure too: an API error can end a
#                  subagent with only that)
#   SessionStart   (startup or resume, not compact/clear/fork) removes every
#                  paddock.sub.<app>.* label left over from an earlier session
#   SessionEnd     removes this session's labels
# Registered with "async": true, so the agent never waits for it. It reads the hook's
# JSON from stdin and keeps only the event name, session, agent id and type; it opens
# no file except Codex's session_index.jsonl (below) and uses no network. It prints
# nothing and always exits 0: it can't change what the agent does.
#
# Which terminal: HC_TERMINAL_ID when the agent runs its hooks itself (Claude Code).
# Codex usually runs them from its shared background server, started outside Herdr,
# so for Codex the hook finds its terminal: the live Codex terminal whose title holds
# the thread's name (from $CODEX_HOME/session_index.jsonl), else the only live Codex
# terminal in the session's folder. When that's ambiguous it does nothing.

export LC_ALL=C
app=$(printf '%s' "${1:-claude}" | tr -cd 'a-z0-9-' | cut -c1-16)
[ -n "$app" ] || exit 0
command -v hc >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null)
have_jq=; command -v jq >/dev/null 2>&1 && have_jq=1
# A top-level string field of the input.
field() {
  if [ -n "$have_jq" ]; then printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // empty | strings' 2>/dev/null | tr -d '\r' | head -n 1
  else printf '%s' "$input" | tr -d '\r\n' | sed -n "s/^[[:space:]]*{.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1; fi
}

event=$(field hook_event_name)
# Ids, types and sessions are plain words; anything else is dropped rather than quoted.
id=$(field agent_id | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
type=$(field agent_type | tr -cd 'A-Za-z0-9_:. -' | cut -c1-48)
sid=$(field session_id | tr -cd 'A-Za-z0-9_-' | cut -c1-64)
source=$(field source)

# This session's terminal, for Codex when it runs hooks outside Herdr.
codex_terminal() {
  ls=$(hc ls --json 2>/dev/null) || return 0
  if [ -n "$have_jq" ]; then
    list=$(printf '%s' "$ls" | jq -r '.terminals[] | select(.agent == "codex" and .state == "live") | .address' 2>/dev/null | tr -d '\r')
  else
    list=$(printf '%s' "$ls" | grep -o '{"address":"[^"]*","agent":"codex","cwd":"[^"]*","state":"live"' | sed 's/^{"address":"\([^"]*\)".*/\1/')
  fi
  [ -n "$list" ] || return 0
  index="${CODEX_HOME:-$HOME/.codex}/session_index.jsonl"
  name=
  [ -n "$sid" ] && [ -f "$index" ] && name=$(grep "\"id\":\"$sid\"" "$index" 2>/dev/null | tail -n 1 | sed -n 's/.*"thread_name":"\([^"]*\)".*/\1/p')
  hits=; n=0
  for t in $list; do
    one=$(hc get "$t" --json 2>/dev/null)
    if [ -n "$name" ]; then
      if [ -n "$have_jq" ]; then title=$(printf '%s' "$one" | jq -r '.title // ""' 2>/dev/null | tr -d '\r')
      else title=$(printf '%s' "$one" | sed -n -E 's/.*,"template":(null|"[^"]*"),"title":"([^"]*)".*/\2/p'); fi
      case "$title" in *"$name"*) hits=$t; n=$((n + 1));; esac
    else
      cwd=$(field cwd)
      if [ -n "$have_jq" ]; then tcwd=$(printf '%s' "$one" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')
      else tcwd=$(printf '%s' "$one" | sed -n 's/^{.*"cwd":"\([^"]*\)","die_with_parent".*/\1/p'); fi
      [ -n "$cwd" ] && [ "$tcwd" = "$cwd" ] && { hits=$t; n=$((n + 1)); }
    fi
  done
  [ "$n" = 1 ] && printf '%s' "$hits"
}

term=$HC_TERMINAL_ID
[ -z "$term" ] && [ "$app" = codex ] && term=$(codex_terminal)
[ -n "$term" ] || exit 0
key="paddock.sub.$app.$id"

# This app's labels on the terminal, one "name value" per line (values have no spaces).
labels() {
  hc get "$term" --json 2>/dev/null | grep -o "\"paddock\\.sub\\.$app\\.[A-Za-z0-9_-]*\":\"[^\"]*\\(\\\\\"[^\"]*\\)*\"" | sed 's/^"\([^"]*\)":"\(.*\)"$/\1 \2/'
}

case "$event" in
  SubagentStart)
    [ -n "$id" ] || exit 0
    hc label "$term" "$key={\"app\":\"$app\",\"type\":\"$type\",\"at\":$(date +%s)000,\"s\":\"$sid\"}" >/dev/null 2>&1
    ;;
  SubagentStop|StopFailure)
    [ -n "$id" ] || exit 0
    # A Stop can arrive before a slow Start for a subagent that ends at once.
    sleep 2
    hc label "$term" "$key=" >/dev/null 2>&1
    ;;
  SessionStart)
    case "$source" in startup|resume|"") ;; *) exit 0;; esac
    labels | while read -r k _; do hc label "$term" "$k=" >/dev/null 2>&1; done
    ;;
  SessionEnd)
    [ -n "$sid" ] || exit 0
    labels | while read -r k v; do
      case "$v" in *"s\\\":\\\"$sid\\\""*|*"\"s\":\"$sid\""*) hc label "$term" "$k=" >/dev/null 2>&1;; esac
    done
    ;;
esac
exit 0
