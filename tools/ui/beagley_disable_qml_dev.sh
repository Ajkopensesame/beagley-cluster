#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"

usage() {
  cat <<'EOF'
Usage:
  ./tools/ui/beagley_disable_qml_dev.sh [options]

Options:
  --host HOST    SSH target. Default: root@beagley-ai.local
  -h, --help     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[beagley-ui] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "[beagley-ui] Step 1: Remove systemd QML dev override..."
ssh "$HOST" "set -e;
  rm -f /etc/systemd/system/beagley_cluster.service.d/ui-dev.conf;
  rmdir /etc/systemd/system/beagley_cluster.service.d 2>/dev/null || true;
  systemctl daemon-reload;
  systemctl reset-failed beagley_cluster;
  systemctl restart beagley_cluster"

echo "[beagley-ui] Step 2: Health check..."
if ! "$ROOT/skills/beagley-health-check/scripts/check.sh"; then
  echo "[beagley-ui] Health check failed; collecting debug output..."
  "$ROOT/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[beagley-ui] QML dev mode disabled"
