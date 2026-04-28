#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Layout: Update (Replace)
# @raycast.mode compact
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Replace windows in an existing numbered layout (signature must match)
# @raycast.argument1 { "type": "text", "placeholder": "Layout ID (e.g., 1 or 001)", "required": true }

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
  echo "Please provide a numeric id (e.g., 1 or 001)."
  exit 1
fi

id="$(printf "%03d" "$((10#$1))")"
open "hammerspoon://window_manager?cmd=layout_update&id=$id"
