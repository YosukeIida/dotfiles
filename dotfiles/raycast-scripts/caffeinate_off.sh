#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Caffeinate OFF
# @raycast.mode compact
# @raycast.packageName Power
# Optional parameters:
# @raycast.icon 🔴
# @raycast.description Stop the Raycast-managed caffeinate process

set -euo pipefail

PIDFILE="${HOME}/.cache/raycast-caffeinate.pid"

is_running() {
  local pid="$1"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1
}

if [[ ! -f "$PIDFILE" ]]; then
  echo "Already OFF (no pidfile)"
  exit 0
fi

PID="$(cat "$PIDFILE" 2>/dev/null || true)"

if is_running "$PID"; then
  kill "$PID" 2>/dev/null || true
  sleep 0.1
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$PIDFILE" || true
  echo "OFF (killed pid=$PID)"
else
  rm -f "$PIDFILE" || true
  echo "OFF (stale pidfile removed)"
fi
