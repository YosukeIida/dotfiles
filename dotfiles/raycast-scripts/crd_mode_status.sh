#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title CRD Mode Status
# @raycast.mode compact
# @raycast.packageName Remote
# Optional parameters:
# @raycast.icon 🟡
# @raycast.description Show CRD Mode status (pmset disablesleep + brightness)

set -euo pipefail

STATEFILE="${HOME}/.cache/raycast-crd-mode.state"
PIDFILE="${HOME}/.cache/raycast-crd-mode.caffeinate.pid"

read_brightness_raw() {
  ioreg -r -d 1 -w0 -c AppleARMBacklight 2>/dev/null | sed -nE 's/.*"brightness"=\{"min"=[0-9]+,"max"=[0-9]+,"value"=([0-9]+)\}.*/\1/p' | head -n 1 || true
}

power_source() {
  local line
  line="$(pmset -g ps 2>/dev/null | head -n 1 || true)"
  if echo "$line" | grep -qi "AC Power"; then
    echo "ac"
  elif echo "$line" | grep -qi "Battery Power"; then
    echo "battery"
  else
    echo "unknown"
  fi
}

sleep_disabled() {
  pmset -g 2>/dev/null | awk '$1=="SleepDisabled"{print $2; found=1} END{if(!found) print "0"}'
}

is_running() {
  local pid="$1"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1
}

display_assertion_active() {
  pmset -g assertions 2>/dev/null | awk '$1=="PreventUserIdleDisplaySleep"{print $2; found=1} END{if(!found) print "0"}'
}

power="$(power_source)"
current_sleepdisabled="$(sleep_disabled)"
display_awake="$(display_assertion_active)"
current_brightness_raw="$(read_brightness_raw || true)"
current_brightness_raw="${current_brightness_raw:-"-"}"

caffeinate_pid="-"
if [[ -f "$PIDFILE" ]]; then
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if is_running "$pid"; then
    caffeinate_pid="$pid"
  fi
fi

saved="no"
if [[ -f "$STATEFILE" ]]; then
  saved="yes"
fi

mode="OFF"
if [[ "$saved" == "yes" ]]; then
  mode="ON"
fi

saved_scope="-"
if [[ -f "$STATEFILE" ]] && grep -q '^pmset\.scope=' "$STATEFILE"; then
  saved_scope="$(awk -F= '/^pmset.scope=/{print $2}' "$STATEFILE" | head -n1)"
fi

baseline="-"
if [[ -f "$STATEFILE" ]] && grep -q '^pmset\.baseline\.sleepdisabled=' "$STATEFILE"; then
  baseline="$(awk -F= '/^pmset.baseline.sleepdisabled=/{print $2}' "$STATEFILE" | head -n1)"
fi

brightness_baseline="-"
if [[ -f "$STATEFILE" ]] && grep -q '^brightness\.baseline\.raw=' "$STATEFILE"; then
  brightness_baseline="$(awk -F= '/^brightness.baseline.raw=/{print $2}' "$STATEFILE" | head -n1)"
fi

echo "CRD Mode: ${mode} / power=${power} / SleepDisabled=${current_sleepdisabled} / DisplayAwake=${display_awake} / caffeinate_pid=${caffeinate_pid} / baseline=${baseline} / brightness=${current_brightness_raw} (baseline=${brightness_baseline}) / scope=${saved_scope} / saved=${saved}"

if [[ "$saved" == "yes" && "$current_sleepdisabled" != "1" ]]; then
  echo "WARN: statefile exists but SleepDisabled is not enabled (stale or auth-cancel?)."
fi

if [[ "$saved" == "no" && "$current_sleepdisabled" == "1" ]]; then
  echo "WARN: SleepDisabled is enabled but CRD Mode statefile is missing (enabled elsewhere?)."
fi
