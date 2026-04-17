#!/bin/bash
set -u

HOST="root@beagley-ai.local"

echo "[GPU-DIAG] Step 1: Check /dev/dri..."
ssh $HOST "ls -l /dev/dri 2>/dev/null || echo '[FAIL] /dev/dri not found'"

echo ""
echo "[GPU-DIAG] Step 2: Check DRM devices..."
ssh $HOST "ls /dev/dri/card* 2>/dev/null || echo '[FAIL] No card devices'"
ssh $HOST "ls /dev/dri/render* 2>/dev/null || echo '[WARN] No render devices'"

echo ""
echo "[GPU-DIAG] Step 3: Check permissions..."
ssh $HOST "ls -l /dev/dri/* 2>/dev/null"

echo ""
echo "[GPU-DIAG] Step 4: Check kernel modules..."
ssh $HOST "lsmod | grep -E 'drm|gpu' || echo '[WARN] No DRM/GPU modules loaded'"

echo ""
echo "[GPU-DIAG] Step 5: Check dmesg for GPU..."
ssh $HOST "dmesg | grep -i drm | tail -n 20"

echo ""
echo "[GPU-DIAG] Step 6: Check environment..."
ssh $HOST "echo QT_QPA_PLATFORM=\$QT_QPA_PLATFORM"

echo ""
echo "[GPU-DIAG] Step 7: Check running user..."
ssh $HOST "ps -o user= -p \$(pgrep beagley_cluster 2>/dev/null) 2>/dev/null || echo '[INFO] Service not running'"

echo ""
echo "[GPU-DIAG] Complete"
