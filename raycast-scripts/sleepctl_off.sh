#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sleepctl OFF
# @raycast.mode compact
# @raycast.packageName Remote
# Optional parameters:
# @raycast.icon 🔒
# @raycast.description Restore normal sleep behavior via sleepctl (pmset -a disablesleep 0).

set -euo pipefail

if ! /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0; then
  echo "ERROR: sudo -n failed (NOPASSWD sudoers rule for pmset not active?)." >&2
  echo "Run darwin-switch (darwin-rebuild switch) first." >&2
  exit 1
fi

echo "sleepctl: OFF (SleepDisabled=0)."
