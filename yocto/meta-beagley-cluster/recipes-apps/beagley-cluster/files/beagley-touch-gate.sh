#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SYS_INPUT_ROOT="${BEAGLEY_TOUCH_SYS_CLASS_INPUT:-/sys/class/input}"
DEV_INPUT_ROOT="${BEAGLEY_TOUCH_DEV_INPUT:-/dev/input}"
GATE_FILE="${BEAGLEY_TOUCH_GATE_FILE:-/run/beagley_touch_gate.ok}"
STATUS_FILE="${BEAGLEY_TOUCH_PROBE_STATUS_FILE:-/run/beagley_touch_gate.status}"
LOG_FILE="${BEAGLEY_TOUCH_PROBE_LOG_FILE:-/run/beagley_touch_gate.log}"
TIMEOUT_SEC="${BEAGLEY_TOUCH_GATE_TIMEOUT:-60}"
EXPLICIT_DEVICE="${BEAGLEY_TOUCH_DEVICE_PATH:-${BEAGLEY_TOUCH_DEVICE:-}}"
USB_RECOVERY="${BEAGLEY_TOUCH_USB_RECOVERY:-1}"
USB_RECOVERY_AFTER_SEC="${BEAGLEY_TOUCH_USB_RECOVERY_AFTER_SEC:-8}"
USB_RECOVERY_DELAY_SEC="${BEAGLEY_TOUCH_USB_RECOVERY_DELAY_SEC:-8}"
USB_RECOVERY_DRIVER_DIR="${BEAGLEY_TOUCH_USB_DRIVER_DIR:-/sys/bus/platform/drivers/xhci-hcd}"
USB_RECOVERY_DEVICE="${BEAGLEY_TOUCH_USB_PLATFORM_DEVICE:-xhci-hcd.5.auto}"

usage() {
  cat <<'EOF'
usage: beagley-touch-gate.sh [--write-ok <path>] [--timeout <sec>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-ok)
      GATE_FILE="${2:-}"; shift 2 ;;
    --timeout)
      TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if [[ ! "$TIMEOUT_SEC" =~ ^[0-9]+$ ]]; then
  echo "BEAGLEY_TOUCH_GATE_TIMEOUT must be numeric" >&2
  exit 2
fi
if [[ ! "$USB_RECOVERY_AFTER_SEC" =~ ^[0-9]+$ ]]; then
  echo "BEAGLEY_TOUCH_USB_RECOVERY_AFTER_SEC must be numeric" >&2
  exit 2
fi
if [[ ! "$USB_RECOVERY_DELAY_SEC" =~ ^[0-9]+$ ]]; then
  echo "BEAGLEY_TOUCH_USB_RECOVERY_DELAY_SEC must be numeric" >&2
  exit 2
fi

mkdir -p "$(dirname "$GATE_FILE")" "$(dirname "$STATUS_FILE")" "$(dirname "$LOG_FILE")"
: >"$LOG_FILE"

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

log() {
  printf '[touch-gate] %s\n' "$*" | tee -a "$LOG_FILE"
}

enabled_value() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" != "0" && "$value" != "false" && "$value" != "off" && "$value" != "no" ]]
}

attempt_usb_recovery() {
  if ! enabled_value "$USB_RECOVERY"; then
    log "USB recovery disabled"
    return 1
  fi

  if [[ ! -w "$USB_RECOVERY_DRIVER_DIR/unbind" || ! -w "$USB_RECOVERY_DRIVER_DIR/bind" ]]; then
    log "USB recovery skipped: missing writable bind controls under ${USB_RECOVERY_DRIVER_DIR}"
    return 1
  fi
  if [[ ! -e "$USB_RECOVERY_DRIVER_DIR/$USB_RECOVERY_DEVICE" ]]; then
    log "USB recovery skipped: platform device ${USB_RECOVERY_DEVICE} is not bound"
    return 1
  fi

  log "attempting USB host recovery device=${USB_RECOVERY_DEVICE}"
  if ! printf '%s' "$USB_RECOVERY_DEVICE" >"$USB_RECOVERY_DRIVER_DIR/unbind"; then
    log "USB recovery failed: unbind write failed"
    return 1
  fi
  sleep 2
  if ! printf '%s' "$USB_RECOVERY_DEVICE" >"$USB_RECOVERY_DRIVER_DIR/bind"; then
    log "USB recovery failed: bind write failed"
    return 1
  fi
  sleep "$USB_RECOVERY_DELAY_SEC"
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle --timeout=5 >/dev/null 2>&1 || true
  fi
  log "USB host recovery complete"
  return 0
}

write_status() {
  local status="$1"
  local detail="$2"
  local device="${3:-}"
  local name="${4:-}"
  local reason="${5:-}"

  {
    printf 'status=%s\n' "$status"
    printf 'timestamp_utc=%s\n' "$(utc_now)"
    printf 'detail=%s\n' "$detail"
    [[ -n "$device" ]] && printf 'device=%s\n' "$device"
    [[ -n "$name" ]] && printf 'name=%s\n' "$name"
    [[ -n "$reason" ]] && printf 'reason=%s\n' "$reason"
  } >"$STATUS_FILE"
}

write_gate() {
  local device="$1"
  local name="$2"
  local reason="$3"

  {
    printf 'status=pass\n'
    printf 'timestamp_utc=%s\n' "$(utc_now)"
    printf 'device=%s\n' "$device"
    printf 'name=%s\n' "$name"
    printf 'reason=%s\n' "$reason"
  } >"$GATE_FILE"
  write_status "pass" "touch input ready" "$device" "$name" "$reason"
}

event_name() {
  local event_dir="$1"
  cat "$event_dir/device/name" 2>/dev/null || printf 'unknown'
}

property_file_has_touch() {
  local event_dir="$1"
  local props_file

  for props_file in "$event_dir/device/properties" "$event_dir/device/uevent" "$event_dir/properties"; do
    [[ -r "$props_file" ]] || continue
    if grep -Eq '(^|[[:space:]])ID_INPUT_(TOUCHSCREEN|TABLET)=1($|[[:space:]])' "$props_file"; then
      return 0
    fi
  done
  return 1
}

udev_has_touch() {
  local dev="$1"

  command -v udevadm >/dev/null 2>&1 || return 1
  udevadm info --query=property --name="$dev" 2>/dev/null \
    | grep -Eq '^ID_INPUT_(TOUCHSCREEN|TABLET)=1$'
}

name_has_touch_hint() {
  local name
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$name" =~ (touch|touchscreen|digitizer|goodix|maxtouch|ft5|edt-ft|ili2|egalax) ]]
}

is_touch_event() {
  local event_dir="$1"
  local dev="$2"
  local name="$3"

  if udev_has_touch "$dev"; then
    printf 'udev'
    return 0
  fi
  if property_file_has_touch "$event_dir"; then
    printf 'property'
    return 0
  fi
  if name_has_touch_hint "$name"; then
    printf 'name'
    return 0
  fi
  return 1
}

find_touch_device() {
  local event_dir event dev name reason

  if [[ -n "$EXPLICIT_DEVICE" ]]; then
    if [[ -e "$EXPLICIT_DEVICE" ]]; then
      event="$(basename "$EXPLICIT_DEVICE")"
      event_dir="$SYS_INPUT_ROOT/$event"
      name="configured"
      [[ -d "$event_dir" ]] && name="$(event_name "$event_dir")"
      printf '%s\t%s\tconfigured\n' "$EXPLICIT_DEVICE" "$name"
      return 0
    fi
    return 1
  fi

  for event_dir in "$SYS_INPUT_ROOT"/event*; do
    [[ -d "$event_dir" ]] || continue
    event="$(basename "$event_dir")"
    dev="$DEV_INPUT_ROOT/$event"
    [[ -e "$dev" ]] || continue
    name="$(event_name "$event_dir")"
    if reason="$(is_touch_event "$event_dir" "$dev" "$name")"; then
      printf '%s\t%s\t%s\n' "$dev" "$name" "$reason"
      return 0
    fi
  done
  return 1
}

start_time=$SECONDS
deadline=$((SECONDS + TIMEOUT_SEC))
usb_recovery_done=0
log "waiting for touchscreen input device timeout=${TIMEOUT_SEC}s"

while :; do
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle --timeout=3 >/dev/null 2>&1 || true
  fi

  if result="$(find_touch_device)"; then
    IFS=$'\t' read -r device name reason <<<"$result"
    log "touch input ready device=${device} name=${name} reason=${reason}"
    write_gate "$device" "$name" "$reason"
    exit 0
  fi

  if (( SECONDS >= deadline )); then
    break
  fi

  if (( usb_recovery_done == 0 && SECONDS - start_time >= USB_RECOVERY_AFTER_SEC )); then
    usb_recovery_done=1
    attempt_usb_recovery || true
    continue
  fi

  sleep 1
done

log "no touchscreen input device found under ${SYS_INPUT_ROOT}"
if (( usb_recovery_done == 1 )); then
  write_status "fail" "no touchscreen input device found after USB recovery"
else
  write_status "fail" "no touchscreen input device found"
fi
exit 1
