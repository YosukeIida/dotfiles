#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sleepctl Status
# @raycast.mode compact
# @raycast.packageName Remote
# Optional parameters:
# @raycast.icon 🟡
# @raycast.description Show sleepctl (pmset disablesleep) state and whether the
# lid-close watcher agent (sleepctl-watcher) is loaded.

set -euo pipefail

sleep_disabled="$(/usr/bin/pmset -g 2>/dev/null | /usr/bin/awk '$1=="SleepDisabled"{print $2; found=1} END{if(!found) print "0"}')"

mode="OFF"
[[ "$sleep_disabled" == "1" ]] && mode="ON"

watcher_state="not loaded"
if /bin/launchctl print "gui/$(id -u)/com.yosuke.sleepctl-watcher" >/dev/null 2>&1; then
  watcher_state="loaded"
fi

echo "sleepctl: ${mode} / SleepDisabled=${sleep_disabled} / sleepctl-watcher=${watcher_state}"
