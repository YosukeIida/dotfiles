#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title CRD Mode OFF
# @raycast.mode compact
# @raycast.packageName Remote
# Optional parameters:
# @raycast.icon 🔒
# @raycast.description Restore pmset disablesleep + brightness saved by CRD Mode ON

set -euo pipefail

STATEFILE="${HOME}/.cache/raycast-crd-mode.state"
PIDFILE="${HOME}/.cache/raycast-crd-mode.caffeinate.pid"

read_brightness_raw() {
  ioreg -r -d 1 -w0 -c AppleARMBacklight 2>/dev/null | sed -nE 's/.*"brightness"=\{"min"=[0-9]+,"max"=[0-9]+,"value"=([0-9]+)\}.*/\1/p' | head -n 1 || true
}

press_keycode() {
  local code="$1"
  osascript -e "tell application \"System Events\" to key code ${code}" >/dev/null 2>&1
}

detect_brightness_keycodes() {
  local before after
  before="$(read_brightness_raw || true)"
  [[ -n "${before:-}" ]] || return 1

  # Probe which keycode increases/decreases brightness. (The probe changes brightness by one step.)
  if press_keycode 145; then
    sleep 0.05
    after="$(read_brightness_raw || true)"
    if [[ -n "${after:-}" && "$after" != "$before" ]]; then
      if (( after < before )); then
        BRIGHTNESS_KEY_DOWN=145
        BRIGHTNESS_KEY_UP=144
      else
        BRIGHTNESS_KEY_UP=145
        BRIGHTNESS_KEY_DOWN=144
      fi
      return 0
    fi
  fi

  if press_keycode 144; then
    sleep 0.05
    after="$(read_brightness_raw || true)"
    if [[ -n "${after:-}" && "$after" != "$before" ]]; then
      if (( after < before )); then
        BRIGHTNESS_KEY_DOWN=144
        BRIGHTNESS_KEY_UP=145
      else
        BRIGHTNESS_KEY_UP=144
        BRIGHTNESS_KEY_DOWN=145
      fi
      return 0
    fi
  fi

  return 1
}

restore_brightness_to_raw() {
  local target="$1"

  BRIGHTNESS_KEY_UP=""
  BRIGHTNESS_KEY_DOWN=""

  if ! detect_brightness_keycodes; then
    echo "WARN: Unable to control brightness via System Events (permission?)"
    return 0
  fi

  local curr prev i
  curr="$(read_brightness_raw || true)"
  [[ -n "${curr:-}" ]] || return 0

  for ((i=0; i<40; i++)); do
    if (( curr == target )); then
      break
    fi

    if (( curr < target )); then
      prev="$curr"
      press_keycode "${BRIGHTNESS_KEY_UP}" || break
      sleep 0.05
      curr="$(read_brightness_raw || true)"
      [[ -n "${curr:-}" ]] || break

      # Stop if keypress didn't move.
      if (( curr <= prev )); then
        break
      fi

      # If we overshot, step back if that gets closer.
      if (( curr > target )); then
        if (( (curr - target) > (target - prev) )); then
          press_keycode "${BRIGHTNESS_KEY_DOWN}" >/dev/null 2>&1 || true
          sleep 0.05
          curr="$(read_brightness_raw || true)"
        fi
        break
      fi
    else
      prev="$curr"
      press_keycode "${BRIGHTNESS_KEY_DOWN}" || break
      sleep 0.05
      curr="$(read_brightness_raw || true)"
      [[ -n "${curr:-}" ]] || break

      if (( curr >= prev )); then
        break
      fi

      if (( curr < target )); then
        if (( (target - curr) > (prev - target) )); then
          press_keycode "${BRIGHTNESS_KEY_UP}" >/dev/null 2>&1 || true
          sleep 0.05
          curr="$(read_brightness_raw || true)"
        fi
        break
      fi
    fi
  done
}

pmset_admin() {
  local cmd="$1"
  osascript <<APPLESCRIPT
do shell script "$cmd" with administrator privileges
APPLESCRIPT
}

is_running() {
  local pid="$1"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1
}

stop_caffeinate() {
  local pid=""

  if [[ ! -f "$PIDFILE" ]]; then
    return 0
  fi

  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if is_running "$pid"; then
    kill "$pid" 2>/dev/null || true
    sleep 0.1
    if is_running "$pid"; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$PIDFILE" || true
}

is_int() {
  [[ "${1:-}" =~ ^-?[0-9]+$ ]]
}

sleep_disabled() {
  pmset -g 2>/dev/null | awk '$1=="SleepDisabled"{print $2; found=1} END{if(!found) print "0"}'
}

if [[ ! -f "$STATEFILE" ]]; then
  stop_caffeinate || true
  echo "CRD Mode: Already OFF (no saved state)"
  exit 0
fi

baseline="$(awk -F= '/^pmset.baseline.sleepdisabled=/{print $2}' "$STATEFILE" | head -n1)"
scope="$(awk -F= '/^pmset.scope=/{print $2}' "$STATEFILE" | head -n1)"
enabled_power="$(awk -F= '/^pmset.enabled.power=/{print $2}' "$STATEFILE" | head -n1)"
baseline_brightness_raw="$(awk -F= '/^brightness.baseline.raw=/{print $2}' "$STATEFILE" | head -n1)"

scope="${scope:-"-"}"
enabled_power="${enabled_power:-"-"}"
baseline_brightness_raw="${baseline_brightness_raw:-"__UNSET__"}"

# Backward compatibility with older statefiles.
if [[ -z "${baseline:-}" ]]; then
  pm_c="$(awk -F= '/^pmset.ac.disablesleep=/{print $2}' "$STATEFILE" | head -n1)"
  pm_b="$(awk -F= '/^pmset.battery.disablesleep=/{print $2}' "$STATEFILE" | head -n1)"
  if [[ -n "${pm_c:-}" ]]; then
    baseline="$pm_c"
  elif [[ -n "${pm_b:-}" ]]; then
    baseline="$pm_b"
  fi
fi

if [[ -z "${baseline:-}" ]]; then
  echo "CRD Mode: OFF / refused to restore pmset (missing saved baseline)"
  exit 1
fi

if ! is_int "$baseline"; then
  echo "CRD Mode: OFF / refused to restore pmset (invalid saved baseline: '$baseline')"
  exit 1
fi

current="$(sleep_disabled)"
if [[ "$current" == "$baseline" ]]; then
  if [[ "$baseline_brightness_raw" != "__UNSET__" ]] && is_int "$baseline_brightness_raw"; then
    restore_brightness_to_raw "$baseline_brightness_raw" || true
  fi
  stop_caffeinate || true
  rm -f "$STATEFILE"
  echo "CRD Mode: OFF / already restored (SleepDisabled=${current}, DisplayAwake=0, scope=${scope}, enabled_power=${enabled_power})"
  exit 0
fi

# Restore system-wide disablesleep.
pmset_admin "/usr/bin/pmset disablesleep ${baseline}"

if [[ "$baseline_brightness_raw" != "__UNSET__" ]] && is_int "$baseline_brightness_raw"; then
  restore_brightness_to_raw "$baseline_brightness_raw" || true
fi

stop_caffeinate || true
rm -f "$STATEFILE"

echo "CRD Mode: OFF / restored (SleepDisabled=${baseline}, DisplayAwake=0, scope=${scope}, enabled_power=${enabled_power})"
