#!/usr/bin/env bash
set -euo pipefail

RUN_MARKER="/run/beagley-diagnostic.mode"
STATE_ROOT="/var/lib/beagley-cluster/diagnostic"
STAGE_ROOT="${STATE_ROOT}/stages"
SNAPSHOT_ROOT="${STATE_ROOT}/snapshots"
BOOT_DIR_NAME="beagley-diag"
BOOT_MOUNT_ROOT="/run/beagley-diagnostic/boot"
BOOT_MOUNTED_TEMP=0

diag_mode_enabled() {
  grep -Eq '(^| )beagley\.diag=1($| )' /proc/cmdline || [[ -f "$RUN_MARKER" ]]
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

stage_slug() {
  printf '%s' "${1:-unknown}" | tr -cs 'A-Za-z0-9._-' '-'
}

log_diag() {
  printf '[beagley-diag] %s\n' "$*"
}

find_existing_boot_mount() {
  local boot_dev

  boot_dev="$(blkid -L boot 2>/dev/null || true)"
  [[ -n "$boot_dev" ]] || return 0

  findmnt -rn -S "$boot_dev" -o TARGET 2>/dev/null | head -n 1 || true
}

resolve_boot_mount() {
  local existing_mount boot_dev

  existing_mount="$(find_existing_boot_mount)"
  if [[ -n "$existing_mount" ]]; then
    printf '%s\n' "$existing_mount"
    return 0
  fi

  boot_dev="$(blkid -L boot 2>/dev/null || true)"
  if [[ -z "$boot_dev" ]]; then
    return 1
  fi

  mkdir -p "$BOOT_MOUNT_ROOT"
  mount "$boot_dev" "$BOOT_MOUNT_ROOT"
  BOOT_MOUNTED_TEMP=1
  printf '%s\n' "$BOOT_MOUNT_ROOT"
}

cleanup_boot_mount() {
  if [[ "$BOOT_MOUNTED_TEMP" -eq 1 ]]; then
    umount "$BOOT_MOUNT_ROOT" >/dev/null 2>&1 || true
    rmdir "$BOOT_MOUNT_ROOT" >/dev/null 2>&1 || true
  fi
}

write_boot_file() {
  local relative_path="$1"
  local source_path="$2"
  local boot_mount target_path

  boot_mount="$(resolve_boot_mount || true)"
  [[ -n "$boot_mount" ]] || return 0

  mkdir -p "$boot_mount/${BOOT_DIR_NAME}/$(dirname "$relative_path")"
  target_path="$boot_mount/${BOOT_DIR_NAME}/${relative_path}"
  cp "$source_path" "$target_path"
}

mark_stage() {
  local stage_name="$1"
  local slug timestamp stage_file latest_file history_file

  diag_mode_enabled || return 0

  slug="$(stage_slug "$stage_name")"
  timestamp="$(utc_now)"
  stage_file="${STAGE_ROOT}/${slug}.env"
  latest_file="${STATE_ROOT}/latest-stage.txt"
  history_file="${STATE_ROOT}/stage-history.log"

  mkdir -p "$STAGE_ROOT"

  {
    printf 'stage=%s\n' "$slug"
    printf 'timestamp_utc=%s\n' "$timestamp"
    printf 'cmdline=%s\n' "$(cat /proc/cmdline)"
  } >"$stage_file"

  printf '%s %s\n' "$timestamp" "$slug" >>"$history_file"
  {
    printf 'stage=%s\n' "$slug"
    printf 'timestamp_utc=%s\n' "$timestamp"
  } >"$latest_file"

  write_boot_file "latest-stage.txt" "$latest_file"
  write_boot_file "stages/${slug}.env" "$stage_file"
  log_diag "recorded stage ${slug} at ${timestamp}"
}

collect_snapshot() {
  local stage_name="$1"
  local slug timestamp snapshot_dir model_file summary_file failed_units_file input_file event_node event_name

  diag_mode_enabled || return 0

  slug="$(stage_slug "$stage_name")"
  timestamp="$(utc_now)"
  snapshot_dir="${SNAPSHOT_ROOT}/${timestamp}-${slug}"
  model_file="${snapshot_dir}/device-tree-model.txt"
  summary_file="${snapshot_dir}/summary.txt"
  failed_units_file="${snapshot_dir}/systemd-failed.txt"

  mkdir -p "$snapshot_dir"

  cat /proc/cmdline >"${snapshot_dir}/cmdline.txt"
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\000' </proc/device-tree/model >"$model_file"
  else
    printf 'unavailable\n' >"$model_file"
  fi
  uname -a >"${snapshot_dir}/kernel.txt"
  ip -br a >"${snapshot_dir}/ip-br-a.txt" 2>&1 || true
  lsmod >"${snapshot_dir}/lsmod.txt" 2>&1 || true
  find /sys/class/drm -maxdepth 3 -mindepth 1 -printf '%P\n' >"${snapshot_dir}/drm-tree.txt" 2>&1 || true
  input_file="${snapshot_dir}/input-devices.txt"
  {
    printf '### /proc/bus/input/devices\n'
    cat /proc/bus/input/devices 2>&1 || true
    printf '\n### /sys/class/input\n'
    find /sys/class/input -maxdepth 3 -mindepth 1 -printf '%P\n' 2>&1 || true
    printf '\n### event properties\n'
    for event_node in /dev/input/event*; do
      [[ -e "$event_node" ]] || continue
      printf -- '--- %s\n' "$event_node"
      event_name="$(basename "$event_node")"
      if [[ -r "/sys/class/input/${event_name}/device/name" ]]; then
        printf 'name=%s\n' "$(cat "/sys/class/input/${event_name}/device/name")"
      fi
      if [[ -r "/sys/class/input/${event_name}/device/capabilities/abs" ]]; then
        printf 'capabilities_abs=%s\n' "$(cat "/sys/class/input/${event_name}/device/capabilities/abs")"
      fi
      if [[ -r "/sys/class/input/${event_name}/device/properties" ]]; then
        printf 'properties=%s\n' "$(cat "/sys/class/input/${event_name}/device/properties")"
      fi
      udevadm info --query=property --name="$event_node" 2>/dev/null \
        | grep -E '^(DEVNAME|DEVPATH|ID_INPUT|ID_MODEL|ID_VENDOR)=' || true
    done
    printf '\n### touch gate\n'
    cat /run/beagley_touch_gate.status /run/beagley_touch_gate.ok /run/beagley_touch_gate.log 2>/dev/null || true
  } >"$input_file" 2>&1 || true
  systemctl --failed --no-pager --no-legend >"$failed_units_file" 2>&1 || true
  journalctl -b --no-pager -n 200 >"${snapshot_dir}/journal-tail.txt" 2>&1 || true

  {
    printf 'stage=%s\n' "$slug"
    printf 'timestamp_utc=%s\n' "$timestamp"
    printf 'device_tree_model=%s\n' "$(tr '\n' ' ' <"$model_file" | sed 's/[[:space:]]\+$//')"
    printf 'kernel=%s\n' "$(tr '\n' ' ' <"${snapshot_dir}/kernel.txt" | sed 's/[[:space:]]\+$//')"
    printf 'failed_units=%s\n' "$(wc -l <"$failed_units_file" | tr -d ' ')"
  } >"$summary_file"

  ln -sfn "$(basename "$snapshot_dir")" "${SNAPSHOT_ROOT}/latest"
  write_boot_file "latest-summary.txt" "$summary_file"
  log_diag "captured snapshot ${timestamp}-${slug}"
}

usage() {
  cat <<'EOF'
usage: beagley-diagnostic.sh <mark-stage|collect|both> <stage-name>
EOF
}

main() {
  local cmd="${1:-}"
  local stage_name="${2:-}"

  trap cleanup_boot_mount EXIT

  case "$cmd" in
    mark-stage)
      [[ -n "$stage_name" ]] || { usage; exit 1; }
      mark_stage "$stage_name"
      ;;
    collect)
      [[ -n "$stage_name" ]] || { usage; exit 1; }
      collect_snapshot "$stage_name"
      ;;
    both)
      [[ -n "$stage_name" ]] || { usage; exit 1; }
      mark_stage "$stage_name"
      collect_snapshot "$stage_name"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
