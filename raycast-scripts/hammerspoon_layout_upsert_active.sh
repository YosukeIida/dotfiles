#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Layout: Upsert Active Window (By ID)
# @raycast.mode compact
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Upsert only the focused window into a numbered layout (signature must match)
# @raycast.argument1 { "type": "text", "placeholder": "Layout ID (e.g., 1 or 001)", "required": true }

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
  echo "Please provide a numeric id (e.g., 1 or 001)."
  exit 1
fi

id="$(printf "%03d" "$((10#$1))")"
open "hammerspoon://window_manager?cmd=layout_upsert_active&id=$id"
