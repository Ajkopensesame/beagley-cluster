#!/usr/bin/env bash
set -euo pipefail

max_attempts="${YOCTO_GIT_FETCH_RETRIES:-6}"
attempt=1
delay_seconds=15
subcommand=""
skip_next=0

for arg in "$@"; do
  if (( skip_next )); then
    skip_next=0
    continue
  fi

  case "$arg" in
    -c|-C|--config-env)
      skip_next=1
      ;;
    --*)
      ;;
    -*)
      ;;
    *)
      subcommand="$arg"
      break
      ;;
  esac
done

is_retryable=0
case "$subcommand" in
  clone|fetch|ls-remote)
    is_retryable=1
    ;;
esac

while true; do
  if git -c http.version=HTTP/1.1 "$@"; then
    exit 0
  fi

  status=$?
  if (( !is_retryable || attempt >= max_attempts )); then
    exit "$status"
  fi

  echo "[git-retry] git ${subcommand:-unknown} failed with exit code ${status}; retrying ${attempt}/${max_attempts} after ${delay_seconds}s" >&2
  sleep "$delay_seconds"
  attempt=$((attempt + 1))
  delay_seconds=$((delay_seconds * 2))
done
