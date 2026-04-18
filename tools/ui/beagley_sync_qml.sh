#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"
REMOTE_ROOT="${BEAGLEY_QML_DEV_ROOT:-/opt/beagley-cluster/qml-dev}"
RESTART=1
HEALTH=1

usage() {
  cat <<'EOF'
Usage:
  ./tools/ui/beagley_sync_qml.sh [options]

Options:
  --host HOST          SSH target. Default: root@beagley-ai.local
  --remote-root PATH   Remote QML dev root. Default: /opt/beagley-cluster/qml-dev
  --no-restart         Sync files without restarting beagley_cluster.
  --no-health          Skip post-restart health check.
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
    --no-restart)
      RESTART=0
      shift
      ;;
    --no-health)
      HEALTH=0
      shift
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

echo "[beagley-ui] Step 1: Verify SSH..."
ssh -o ConnectTimeout=5 "$HOST" "true"

echo "[beagley-ui] Step 2: Sync QML to $HOST:$REMOTE_ROOT..."
(
  cd "$ROOT"
  find src/ui -type f \( -name '*.qml' -o -name 'qmldir' \) | sort | tar -czf - -T -
) | ssh "$HOST" "set -e;
  tmp='${REMOTE_ROOT}.tmp';
  rm -rf \"\$tmp\";
  mkdir -p \"\$tmp\";
  tar -xzf - -C \"\$tmp\";
  rm -rf '$REMOTE_ROOT';
  mv \"\$tmp\" '$REMOTE_ROOT';
  chown -R root:root '$REMOTE_ROOT' 2>/dev/null || true;
  find '$REMOTE_ROOT/src/ui' -type f \\( -name '*.qml' -o -name 'qmldir' \\) | wc -l"

if [[ "$RESTART" != "1" ]]; then
  echo "[beagley-ui] Sync complete; restart skipped"
  exit 0
fi

echo "[beagley-ui] Step 3: Restart beagley_cluster..."
ssh "$HOST" "systemctl reset-failed beagley_cluster && systemctl restart beagley_cluster"

if [[ "$HEALTH" != "1" ]]; then
  echo "[beagley-ui] Restart complete; health check skipped"
  exit 0
fi

echo "[beagley-ui] Step 4: Health check..."
if ! "$ROOT/skills/beagley-health-check/scripts/check.sh"; then
  echo "[beagley-ui] Health check failed; collecting debug output..."
  "$ROOT/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[beagley-ui] Complete"
