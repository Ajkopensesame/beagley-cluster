#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLL_INTERVAL="${POLL_INTERVAL:-1}"

usage() {
  cat <<'EOF'
Usage:
  ./tools/ui/beagley_watch_qml.sh

Watches src/ui QML files, syncs them to the BeagleY QML dev root, restarts
beagley_cluster, and runs the health check after each change.

Environment:
  BEAGLEY_HOST           SSH target. Default: root@beagley-ai.local
  BEAGLEY_QML_DEV_ROOT   Remote QML dev root. Default: /opt/beagley-cluster/qml-dev
  POLL_INTERVAL          Watch poll interval in seconds. Default: 1
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

source_fingerprint() {
  (
    cd "$ROOT"
    find src/ui -type f \( -name '*.qml' -o -name 'qmldir' \) | sort | while IFS= read -r path; do
      shasum "$path"
    done
  ) | shasum | awk '{print $1}'
}

echo "[beagley-ui] Initial sync..."
"$ROOT/tools/ui/beagley_sync_qml.sh"
last_fp="$(source_fingerprint)"

echo "[beagley-ui] Watching src/ui. Press Ctrl-C to stop."
while true; do
  sleep "$POLL_INTERVAL"
  next_fp="$(source_fingerprint)"
  if [[ "$next_fp" == "$last_fp" ]]; then
    continue
  fi

  last_fp="$next_fp"
  echo "[beagley-ui] QML changed; syncing to BeagleY..."
  if ! "$ROOT/tools/ui/beagley_sync_qml.sh"; then
    echo "[beagley-ui] Sync or health check failed; fix the QML and save again."
  fi
done
