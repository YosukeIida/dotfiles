#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Layout: Apply Auto (This Display)
# @raycast.mode silent
# @raycast.packageName Hammerspoon
# Optional parameters:
# @raycast.description Apply the best matching layout for the current display signature

open "hammerspoon://window_manager?cmd=layout_apply_auto"
