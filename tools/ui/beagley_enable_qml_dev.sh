#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"
REMOTE_ROOT="${BEAGLEY_QML_DEV_ROOT:-/opt/beagley-cluster/qml-dev}"

usage() {
  cat <<'EOF'
Usage:
  ./tools/ui/beagley_enable_qml_dev.sh [options]

Options:
  --host HOST          SSH target. Default: root@beagley-ai.local
  --remote-root PATH   Remote QML dev root. Default: /opt/beagley-cluster/qml-dev
  -h, --help           Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="$2"
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

if [[ "$REMOTE_ROOT" == *"'"* ]]; then
  echo "[beagley-ui] remote root may not contain single quotes: $REMOTE_ROOT" >&2
  exit 2
fi

echo "[beagley-ui] Step 1: Sync current QML..."
BEAGLEY_HOST="$HOST" BEAGLEY_QML_DEV_ROOT="$REMOTE_ROOT" \
  "$ROOT/tools/ui/beagley_sync_qml.sh" --no-restart --no-health

echo "[beagley-ui] Step 2: Install systemd QML dev override..."
ssh "$HOST" "set -e;
  mkdir -p /etc/systemd/system/beagley_cluster.service.d;
  cat > /etc/systemd/system/beagley_cluster.service.d/ui-dev.conf <<'EOF'
[Service]
Environment=BEAGLEY_QML_DEV_ROOT=$REMOTE_ROOT
EOF
  systemctl daemon-reload;
  systemctl reset-failed beagley_cluster;
  systemctl restart beagley_cluster"

echo "[beagley-ui] Step 3: Health check..."
if ! "$ROOT/skills/beagley-health-check/scripts/check.sh"; then
  echo "[beagley-ui] Health check failed; collecting debug output..."
  "$ROOT/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[beagley-ui] QML dev mode enabled"
