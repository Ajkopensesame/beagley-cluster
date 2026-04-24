#!/bin/bash
set -euo pipefail

BASE="/Users/joshkomant/projects/beagley-cluster"
HOST="root@beagley-ai.local"

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
scp "$BIN" "$HOST:/tmp/beagley_cluster.new"

echo "[DEPLOY] Step 3: Backup current version..."
ssh $HOST "cp /usr/bin/beagley_cluster /usr/bin/beagley_cluster.bak 2>/dev/null || true"

echo "[DEPLOY] Step 4: Install new version..."
ssh $HOST "cp /tmp/beagley_cluster.new /usr/bin/beagley_cluster && chmod 0755 /usr/bin/beagley_cluster && rm /tmp/beagley_cluster.new"

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
