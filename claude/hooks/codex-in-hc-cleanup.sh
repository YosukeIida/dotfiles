#!/usr/bin/env bash
# SessionEnd hook: このセッションの端末（HC_TERMINAL_ID）から codex-in-hc で起動した Codex を閉じる。
# 端末の子を全部は閉じない。herdr-agent-team の席など、セッションより長く生きるべき子があるため、
# codex-in-hc が付ける label（codex-in-hc=1）の子だけを対象にする。
[ -n "$HC_TERMINAL_ID" ] && command -v hc >/dev/null || exit 0
hc ls --json 2>/dev/null |
  jq -r --arg p "$HC_TERMINAL_ID" '.terminals[] | select(.parent == $p) | .address' |
  while read -r t; do
    hc get "$t" --json 2>/dev/null | jq -e '.labels["codex-in-hc"] == "1"' >/dev/null && hc kill "$t" >/dev/null 2>&1
  done
exit 0
