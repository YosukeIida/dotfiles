#!/usr/bin/env bash
# SessionStart hook
# /branch で作られた新セッション起動時に、元セッションを新しい cmux workspace で開く

set -euo pipefail

EVENT=$(cat)

SOURCE=$(printf '%s' "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('source', ''))
" 2>/dev/null || true)

# branch 時は source='resume' で来る（通常の resume も同じなので後で forkedFrom で区別する）
if [[ "$SOURCE" != "resume" ]]; then
    exit 0
fi

TRANSCRIPT_PATH=$(printf '%s' "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('transcript_path', ''))
" 2>/dev/null || true)

CWD=$(printf '%s' "$EVENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('cwd', ''))
" 2>/dev/null || true)

if [[ -z "$TRANSCRIPT_PATH" || -z "$CWD" ]]; then
    exit 0
fi

# トランスクリプトから forkedFrom.sessionId を読む（書き込み待ちのためリトライ）
PARENT_SESSION=""
for i in $(seq 1 10); do
    PARENT_SESSION=$(python3 - "$TRANSCRIPT_PATH" << 'PYEOF'
import json, sys

path = sys.argv[1]
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                ff = obj.get('forkedFrom')
                if ff and isinstance(ff, dict) and ff.get('sessionId'):
                    print(ff['sessionId'])
                    sys.exit(0)
            except Exception:
                pass
except Exception:
    pass
PYEOF
    )
    if [[ -n "$PARENT_SESSION" ]]; then
        break
    fi
    sleep 0.3
done

# forkedFrom がなければ通常の resume → 何もしない
if [[ -z "$PARENT_SESSION" ]]; then
    exit 0
fi

LAUNCH_SCRIPT="$HOME/workspace/github.com/YosukeIida/dotfiles/agents/skills/cc-launch-workspace/scripts/launch_cc_workspace.sh"

(
    sleep 2
    bash "$LAUNCH_SCRIPT" "$CWD" --resume "$PARENT_SESSION" \
        >> /tmp/claude_branch_workspace.log 2>&1
) &

exit 0
