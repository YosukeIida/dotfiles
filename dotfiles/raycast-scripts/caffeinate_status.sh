#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Caffeinate Status
# @raycast.mode compact
# @raycast.packageName Power
# Optional parameters:
# @raycast.icon 🟡
# @raycast.description Show whether Raycast-managed caffeinate is running

set -euo pipefail

PIDFILE="${HOME}/.cache/raycast-caffeinate.pid"

PID=""
if [[ -f "$PIDFILE" ]]; then
  PID="$(cat "$PIDFILE" 2>/dev/null || true)"
fi

COUNT="$(pgrep -x caffeinate 2>/dev/null | wc -l | tr -d ' ' || true)"
if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
  echo "ON (pid=$PID) / total caffeinate=$COUNT"
else
  echo "OFF / total caffeinate=$COUNT"
fi
