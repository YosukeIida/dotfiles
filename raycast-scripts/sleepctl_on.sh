#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sleepctl ON
# @raycast.mode compact
# @raycast.packageName Remote
# Optional parameters:
# @raycast.icon 🖥️
# @raycast.description Disable system sleep via sleepctl (pmset -a disablesleep 1,
# NOPASSWD sudoers rule in nix/hosts/darwin/yosuke-macbook-air.nix). Useful for
# remote access (e.g. Chrome Remote Desktop) and long-running local jobs.
# Restore with Sleepctl OFF. NOTE: closing the lid triggers the sleepctl-watcher
# launchd agent, which blanks the display — keep the lid open for screen-sharing
# sessions.

set -euo pipefail

if ! /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1; then
  echo "ERROR: sudo -n failed (NOPASSWD sudoers rule for pmset not active?)." >&2
  echo "Run darwin-switch (darwin-rebuild switch) first." >&2
  exit 1
fi

echo "sleepctl: ON (SleepDisabled=1). Keep the lid open for screen-sharing sessions."
