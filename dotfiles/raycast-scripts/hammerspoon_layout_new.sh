#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Layout: New (Auto ID)
# @raycast.mode compact
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Create a new numbered layout (001__monitors__title.lua) for the current display setup
# @raycast.argument1 { "type": "text", "placeholder": "Title (e.g., work)", "percentEncoded": true }
# @raycast.argument2 { "type": "text", "placeholder": "Description (optional)", "optional": true, "percentEncoded": true }

url="hammerspoon://window_manager?cmd=layout_new&title=$1"
if [[ -n "${2:-}" ]]; then
  url="$url&desc=$2"
fi

open "$url"
