#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title CRD Mode ON
# @raycast.mode compact
# @raycast.packageName Remote
# Optional parameters:
# @raycast.icon 🖥️
# @raycast.description For Chrome Remote Desktop: disable system sleep (pmset disablesleep) + dim screen; restore with CRD Mode OFF
# @raycast.argument1 { "type": "text", "placeholder": "-c (default) / -b / -a", "optional": true }

set -euo pipefail

STATEFILE="${HOME}/.cache/raycast-crd-mode.state"
PIDFILE="${HOME}/.cache/raycast-crd-mode.caffeinate.pid"
mkdir -p "$(dirname "$STATEFILE")"

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

dim_brightness_to_min() {
  BRIGHTNESS_KEY_UP=""
  BRIGHTNESS_KEY_DOWN=""

  if ! detect_brightness_keycodes; then
    echo "WARN: Unable to control brightness via System Events (permission?)"
    return 0
  fi

  local prev curr i
  prev="$(read_brightness_raw || true)"
  [[ -n "${prev:-}" ]] || return 0

  for ((i=0; i<40; i++)); do
    press_keycode "${BRIGHTNESS_KEY_DOWN}" || break
    sleep 0.05
    curr="$(read_brightness_raw || true)"
    [[ -n "${curr:-}" ]] || break
    if (( curr >= prev )); then
      break
    fi
    prev="$curr"
  done
}

# ---- pmset disablesleep scope ----
SCOPE="${1:-"-c"}"
case "$SCOPE" in
  ""|"-c"|"c") SCOPE="-c" ;;
  "-b"|"b") SCOPE="-b" ;;
  "-a"|"a") SCOPE="-a" ;;
  *)
    echo "Invalid scope: '$SCOPE' (use -c, -b, or -a)"
    exit 1
    ;;
esac

if [[ -f "$STATEFILE" ]] && grep -q '^pmset\.scope=' "$STATEFILE"; then
  saved_scope="$(awk -F= '/^pmset.scope=/{print $2}' "$STATEFILE" | head -n1)"
  if [[ -n "${saved_scope:-}" && "$saved_scope" != "$SCOPE" ]]; then
    echo "CRD Mode is already ON with scope='${saved_scope}'. Ignoring requested scope='${SCOPE}'. Run CRD Mode OFF to change."
  fi
  SCOPE="${saved_scope:-"$SCOPE"}"
fi

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

ensure_caffeinate() {
  local pid=""

  if [[ -f "$PIDFILE" ]]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if is_running "$pid"; then
      echo "$pid"
      return 0
    fi
    rm -f "$PIDFILE" || true
  fi

  # Keep attached displays awake while CRD Mode is active.
  nohup caffeinate -d -i >/dev/null 2>&1 &
  pid="$!"
  echo "$pid" >"$PIDFILE"
  chmod 600 "$PIDFILE" 2>/dev/null || true
  echo "$pid"
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

write_statefile() {
  local baseline_sleepdisabled="$1"
  local enabled_power="$2"
  local baseline_brightness_raw="$3"

  umask 077
  {
    echo "pmset.scope=$SCOPE"
    echo "pmset.baseline.sleepdisabled=$baseline_sleepdisabled"
    echo "pmset.enabled.power=$enabled_power"
    echo "brightness.baseline.raw=$baseline_brightness_raw"
  } >"$STATEFILE"

  chmod 600 "$STATEFILE" 2>/dev/null || true
}

current_power="$(power_source)"
current_sleepdisabled="$(sleep_disabled)"
baseline_brightness_raw="$(read_brightness_raw || true)"
baseline_brightness_raw="${baseline_brightness_raw:-"__UNSET__"}"

if [[ -f "$STATEFILE" ]]; then
  if [[ "$current_sleepdisabled" == "1" ]]; then
    caffeinate_pid="$(ensure_caffeinate)"
    dim_brightness_to_min || true
    echo "CRD Mode: Already ON / SleepDisabled=1 / DisplayAwake=1 (pid=${caffeinate_pid})"
    exit 0
  fi

  pmset_admin "/usr/bin/pmset disablesleep 1"
  caffeinate_pid="$(ensure_caffeinate)"
  dim_brightness_to_min || true
  echo "CRD Mode: ON / SleepDisabled=1 / DisplayAwake=1 (re-enabled, pid=${caffeinate_pid})"
  exit 0
fi

# Default behavior: only allow enabling while on AC.
if [[ "$SCOPE" == "-c" && "$current_power" != "ac" ]]; then
  echo "Refusing to enable CRD Mode on battery in default (-c) mode. Use -a (or -b) to force."
  exit 1
fi

baseline_sleepdisabled="$current_sleepdisabled"

# Prevent system sleep (persists system-wide; CRD Mode OFF restores).
pmset_admin "/usr/bin/pmset disablesleep 1"

# Write state only after successful pmset change (avoid stale state on auth cancel).
write_statefile "$baseline_sleepdisabled" "$current_power" "$baseline_brightness_raw"
caffeinate_pid="$(ensure_caffeinate)"

dim_brightness_to_min || true

echo "CRD Mode: ON / SleepDisabled=1 / DisplayAwake=1 (baseline=${baseline_sleepdisabled}, scope=${SCOPE}, power=${current_power}, pid=${caffeinate_pid})"
