#!/bin/bash
set -euo pipefail

BASE="/Users/joshkomant/projects/beagley-cluster"
HOST="root@beagley-ai.local"
REMOTE_TMP="/var/volatile/beagley_cluster.new"
REMOTE_ROLLBACK="/var/volatile/beagley_cluster.rollback"

echo "[DEPLOY] Step 1: Build Linux aarch64 target..."
cd "$BASE"

if [[ -n "${BEAGLEY_DEPLOY_BIN:-}" ]]; then
  BIN="$BEAGLEY_DEPLOY_BIN"
else
  "$BASE/tools/beagley_gpu/build_aarch64.sh"
  BUILD_DIR="${BEAGLEY_AARCH64_BUILD_DIR:-$BASE/build-beagley-aarch64}"
  BIN=$(find "$BUILD_DIR" -type f -name beagley_cluster | head -n 1)
fi

if [[ -z "${BIN:-}" || ! -f "$BIN" ]]; then
  echo "[DEPLOY] Built binary not found" >&2
  exit 2
fi

BIN_DESC=$(file "$BIN")

echo "[DEPLOY] Built binary: $BIN_DESC"

if [[ "$BIN_DESC" != *"ELF 64-bit"* || "$BIN_DESC" != *"aarch64"* ]]; then
  echo "[DEPLOY] Refusing to deploy non-Linux-aarch64 binary to BeagleY" >&2
  echo "[DEPLOY] Configure a Linux aarch64 cross-build or build on a BeagleY image before deploying." >&2
  exit 2
fi

echo "[DEPLOY] Step 2: Transfer binary..."
ssh $HOST "mkdir -p /var/volatile && rm -f '$REMOTE_TMP' '$REMOTE_ROLLBACK' /tmp/beagley_cluster.new"
scp "$BIN" "$HOST:$REMOTE_TMP"

echo "[DEPLOY] Step 3: Free old generated deploy backups..."
ssh $HOST "for path in /usr/bin/beagley_cluster.bak /usr/bin/beagley_cluster.bak.* /usr/bin/beagley_cluster.backup-* /usr/bin/beagley_cluster.compare.*; do [ -e \"\$path\" ] && rm -f \"\$path\"; done; true"

echo "[DEPLOY] Step 4: Install new version..."
ssh $HOST "bash -s" <<REMOTE
set -euo pipefail
restore_on_error() {
  echo "[DEPLOY] Install failed; attempting rollback" >&2
  if [ -s "$REMOTE_ROLLBACK" ]; then
    cp "$REMOTE_ROLLBACK" /usr/bin/beagley_cluster || true
    chmod 0755 /usr/bin/beagley_cluster || true
  fi
  systemctl start beagley_cluster || true
}
trap restore_on_error ERR
systemctl stop beagley_cluster || true
if [ -x /usr/bin/beagley_cluster ]; then
  cp /usr/bin/beagley_cluster "$REMOTE_ROLLBACK" || true
fi
cp "$REMOTE_TMP" /usr/bin/beagley_cluster
chmod 0755 /usr/bin/beagley_cluster
rm -f "$REMOTE_TMP"
sync
trap - ERR
REMOTE

echo "[DEPLOY] Step 5: Restart service..."
ssh $HOST "systemctl reset-failed beagley_cluster"
ssh $HOST "systemctl restart beagley_cluster"

echo "[DEPLOY] Step 6: Verify service..."
ssh $HOST "systemctl status beagley_cluster --no-pager"

echo "[DEPLOY] Step 7: Health check..."
if ! "$BASE/skills/beagley-health-check/scripts/check.sh"; then
  echo "[DEPLOY] Health check failed; collecting diagnostics..."
  "$BASE/skills/beagley-debug-service/scripts/debug.sh" || true
  exit 1
fi

echo "[DEPLOY] Complete"
