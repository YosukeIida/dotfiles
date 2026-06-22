#!/usr/bin/env bash
# UserPromptSubmit hook
# /branch を検知して元のセッションを新しい cmux workspace で自動的に開く

set -euo pipefail

EVENT=$(cat)

MSG=$(printf '%s' "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('message', '').strip())
" 2>/dev/null || true)

if [[ "$MSG" != "/branch" && "$MSG" != "/branch "* ]]; then
    exit 0
fi

SESSION_ID=$(printf '%s' "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('session_id', ''))
" 2>/dev/null || true)

CWD=$(printf '%s' "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('cwd', ''))
" 2>/dev/null || true)

if [[ -z "$SESSION_ID" || -z "$CWD" ]]; then
    exit 0
fi

LAUNCH_SCRIPT="$HOME/workspace/github.com/YosukeIida/dotfiles/agents/skills/cc-launch-workspace/scripts/launch_cc_workspace.sh"

# branch 完了後（3秒待機）に新 workspace で元セッションを resume
(
    sleep 3
    bash "$LAUNCH_SCRIPT" "$CWD" --resume "$SESSION_ID" \
        >> /tmp/claude_branch_workspace.log 2>&1
) &

exit 0
