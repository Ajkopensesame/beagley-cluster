#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/mac-builder-common.sh"

CONTAINER_NAME=""
WATCH_LOG=""
POLL_INTERVAL="${POLL_INTERVAL:-15}"

usage() {
  cat <<EOF
Usage: $0 --container NAME [--watch-log PATH] [--poll-interval SECONDS]
EOF
}

log_watch() {
  local message="$1"
  mac_builder_log "$message"
  if [[ -n "$WATCH_LOG" ]]; then
    printf '[yocto-mac] %s\n' "$message" >>"$WATCH_LOG"
  fi
}

abort_container() {
  if "$DOCKER_BIN" ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    "$DOCKER_BIN" stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    "$DOCKER_BIN" kill "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

last_task_from_logs() {
  local log_output="$1"
  printf '%s\n' "$log_output" | grep -Eo 'Running (noexec )?task [0-9]+ of [0-9]+' | tail -1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --watch-log)
      WATCH_LOG="$2"
      shift 2
      ;;
    --poll-interval)
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      mac_builder_fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$CONTAINER_NAME" ]] || mac_builder_fail "--container is required"
DOCKER_BIN="$(mac_builder_docker_bin)"
if [[ -n "$WATCH_LOG" ]]; then
  mkdir -p "$(dirname "$WATCH_LOG")"
  : >"$WATCH_LOG"
fi

log_watch "watching ${CONTAINER_NAME} for Docker storage errors"

vm_offset=1
backend_offset=1
last_task="unknown"

if [[ -f "$MAC_BUILDER_VM_CONSOLE_LOG" ]]; then
  vm_offset=$(( $(wc -l <"$MAC_BUILDER_VM_CONSOLE_LOG") + 1 ))
fi
if [[ -f "$MAC_BUILDER_BACKEND_LOG" ]]; then
  backend_offset=$(( $(wc -l <"$MAC_BUILDER_BACKEND_LOG") + 1 ))
fi

while true; do
  if ! "$DOCKER_BIN" version >/dev/null 2>&1; then
    log_watch "docker engine became unavailable while watching ${CONTAINER_NAME}"
    exit 1
  fi

  container_status="$("$DOCKER_BIN" inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [[ -n "$container_status" ]]; then
    container_state="${container_status%% *}"
    container_exit="${container_status##* }"
    if [[ "$container_state" == "exited" ]]; then
      log_watch "${CONTAINER_NAME} exited with code ${container_exit}; last task: ${last_task}"
      if [[ "$container_exit" == "0" ]]; then
        exit 0
      fi
      exit 1
    fi
  fi

  log_output="$("$DOCKER_BIN" logs --tail 200 "$CONTAINER_NAME" 2>&1 || true)"
  task_candidate="$(last_task_from_logs "$log_output" || true)"
  if [[ -n "$task_candidate" ]]; then
    last_task="$task_candidate"
  fi

  if printf '%s\n' "$log_output" | grep -Eiq 'overlay2.*input/output error|SIGBUS|No space left on device|fatal error: fault'; then
    log_watch "storage error detected in Docker log output for ${CONTAINER_NAME}"
    log_watch "last task: ${last_task}"
    printf '%s\n' "$log_output" | grep -Ei 'overlay2.*input/output error|SIGBUS|No space left on device|fatal error: fault' | tail -20 | while IFS= read -r line; do
      log_watch "$line"
    done
    abort_container
    exit 1
  fi

  if [[ -f "$MAC_BUILDER_VM_CONSOLE_LOG" ]]; then
    vm_total_lines="$(wc -l <"$MAC_BUILDER_VM_CONSOLE_LOG")"
    if (( vm_total_lines < vm_offset )); then
      vm_offset=1
    fi
    if (( vm_total_lines >= vm_offset )); then
      vm_new_lines="$(sed -n "${vm_offset},\$p" "$MAC_BUILDER_VM_CONSOLE_LOG" 2>/dev/null || true)"
      vm_offset=$((vm_total_lines + 1))
      if printf '%s\n' "$vm_new_lines" | grep -Eiq 'EXT4-fs .*failed to convert unwritten extents|overlay2.*input/output error|SIGBUS|No space left on device|fatal error: fault'; then
        log_watch "storage error detected in Docker VM console for ${CONTAINER_NAME}"
        log_watch "last task: ${last_task}"
        printf '%s\n' "$vm_new_lines" | grep -Ei 'EXT4-fs .*failed to convert unwritten extents|overlay2.*input/output error|SIGBUS|No space left on device|fatal error: fault' | tail -20 | while IFS= read -r line; do
          log_watch "$line"
        done
        abort_container
        exit 1
      fi
    fi
  fi

  if [[ -f "$MAC_BUILDER_BACKEND_LOG" ]]; then
    backend_total_lines="$(wc -l <"$MAC_BUILDER_BACKEND_LOG")"
    if (( backend_total_lines < backend_offset )); then
      backend_offset=1
    fi
    if (( backend_total_lines >= backend_offset )); then
      backend_new_lines="$(sed -n "${backend_offset},\$p" "$MAC_BUILDER_BACKEND_LOG" 2>/dev/null || true)"
      backend_offset=$((backend_total_lines + 1))
      if printf '%s\n' "$backend_new_lines" | grep -Eiq 'overlay2.*input/output error|SIGBUS|No space left on device|fatal error: fault'; then
        log_watch "storage error detected in Docker backend log for ${CONTAINER_NAME}"
        log_watch "last task: ${last_task}"
        printf '%s\n' "$backend_new_lines" | grep -Ei 'overlay2.*input/output error|SIGBUS|No space left on device|fatal error: fault' | tail -20 | while IFS= read -r line; do
          log_watch "$line"
        done
        abort_container
        exit 1
      fi
    fi
  fi

  sleep "$POLL_INTERVAL"
done
