#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Scaling: keep 1:1 for predictable layout while developing
export QT_SCALE_FACTOR=1
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCREEN_SCALE_FACTORS=1

# macOS platform
export QT_QPA_PLATFORM=cocoa

# Hard force window geometry on every launch: WxH+X+Y
# (Prevents macOS from restoring an off-screen position.)
exec "$ROOT/build/beagley_cluster" \
  -platform "cocoa:geometry=1920x720+0+0"
