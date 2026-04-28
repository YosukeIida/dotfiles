#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Layout: Rename (Title/Desc)
# @raycast.mode compact
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Rename a numbered layout (updates file name + internal title/description)
# @raycast.argument1 { "type": "text", "placeholder": "Layout ID (e.g., 1 or 001)" }
# @raycast.argument2 { "type": "text", "placeholder": "New title", "percentEncoded": true }
# @raycast.argument3 { "type": "text", "placeholder": "Description (optional)", "optional": true, "percentEncoded": true }

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
  echo "Please provide a numeric id (e.g., 1 or 001)."
  exit 1
fi

id="$(printf "%03d" "$((10#$1))")"
title_enc="$2"
desc_enc="${3:-}"

url="hammerspoon://window_manager?cmd=layout_rename&id=$id&title=$title_enc"
if [[ -n "$desc_enc" ]]; then
  url="$url&desc=$desc_enc"
fi

open "$url"
