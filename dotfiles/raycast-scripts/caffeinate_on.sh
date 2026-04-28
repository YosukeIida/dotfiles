#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Caffeinate ON
# @raycast.mode compact
# @raycast.packageName Power
# Optional parameters:
# @raycast.icon 🟢
# @raycast.description Prevent idle sleep until turned off (Raycast-managed caffeinate)

set -euo pipefail

PIDFILE="${HOME}/.cache/raycast-caffeinate.pid"
mkdir -p "$(dirname "$PIDFILE")"

is_running() {
  local pid="$1"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1
}

if [[ -f "$PIDFILE" ]]; then
  PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if is_running "$PID"; then
    echo "Already ON (pid=$PID)"
    exit 0
  fi
fi

# -i: prevent idle sleep
# (display may sleep, which is usually fine)
nohup caffeinate -i >/dev/null 2>&1 &
PID="$!"
echo "$PID" >"$PIDFILE"
echo "ON (pid=$PID)"
