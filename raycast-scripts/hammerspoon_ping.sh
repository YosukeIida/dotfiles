#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Hammerspoon: Ping
# @raycast.mode compact
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Check Hammerspoon URL handler is working

open "hammerspoon://window_manager?cmd=ping"
echo "Ping sent"
