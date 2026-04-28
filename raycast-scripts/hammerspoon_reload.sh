#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Hammerspoon: Reload Config
# @raycast.mode compact
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Reload Hammerspoon config

STATUS_FILE="${HOME}/.cache/hammerspoon-wm/init_loaded_at"
before=""
if [[ -f "$STATUS_FILE" ]]; then
  before="$(cat "$STATUS_FILE" 2>/dev/null | tr -dc '0-9')"
fi

trigger_reload() {
  local url="$1"
  open "$url"

  # Wait for init.lua to load and update init_loaded_at
  for _ in {1..30}; do
    sleep 0.1
    if [[ -f "$STATUS_FILE" ]]; then
      after="$(cat "$STATUS_FILE" 2>/dev/null | tr -dc '0-9')"
      if [[ -n "$after" && "$after" != "$before" ]]; then
        ts="$(date -r "$after" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$after")"
        echo "Reloaded: $ts"
        exit 0
      fi
    fi
  done

  return 1
}

trigger_reload "hammerspoon://window_manager?cmd=reload"

echo "Reload triggered, but not confirmed. Check Hammerspoon Console for errors."
