#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Set Menu Bar Spacing
# @raycast.description Set macOS menu bar icon spacing & selection padding
# @raycast.mode compact
# @raycast.packageName Menu Bar Tweaks
# @raycast.icon 🔧
# @raycast.argument1 { "type": "text", "placeholder": "Spacing (e.g., 6)" }
# @raycast.argument2 { "type": "text", "placeholder": "Padding (e.g., 6)" }

spacing="$1"
padding="$2"

re='^-?[0-9]+$'
if ! [[ $spacing =~ $re && $padding =~ $re ]]; then
  echo "Please provide two integers (e.g., 6 6)."
  exit 1
fi

defaults -currentHost write -globalDomain NSStatusItemSpacing -int "$spacing"
defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int "$padding"
killall SystemUIServer >/dev/null 2>&1

echo "Menu bar updated: spacing=$spacing, padding=$padding."

