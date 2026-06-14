#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STRICT=0

usage() {
  cat <<'EOF'
Usage:
  tools/perf/qml_render_risk_scan.sh [--strict]

Scans QML/C++ UI sources for rendering patterns that are risky on the embedded
PowerVR + Qt scenegraph path. Default mode reports counts and exits 0. Strict
mode exits non-zero when hard risks are present.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[qml-risk] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT"

count_pattern() {
  local pattern="$1"
  (rg -n --glob '*.qml' --glob '*.cpp' --glob '*.h' "$pattern" src/ui src/render 2>/dev/null || true) | wc -l | tr -d ' '
}

echo "[qml-risk] repo=$ROOT"
echo "[qml-risk] branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf unknown)"
echo "[qml-risk] commit=$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
echo
echo "[qml-risk] counts"

canvas_count="$(count_pattern '\bCanvas\s*\{')"
canvas_fbo_count="$(count_pattern 'renderTarget:[[:space:]]*Canvas\.FramebufferObject')"
layer_count="$(count_pattern 'layer\.enabled')"
unconditional_layer_count="$(count_pattern 'layer\.enabled:[[:space:]]*true')"
clip_true_count="$(count_pattern 'clip:[[:space:]]*true')"
number_animation_count="$(count_pattern '\bNumberAnimation\b')"
behavior_count="$(count_pattern '\bBehavior on\b')"
timer_count="$(count_pattern '\bTimer\s*\{')"
shader_effect_count="$(count_pattern '\bShaderEffect\b|\bMultiEffect\b|\bOpacityMask\b|\bDropShadow\b|\bFastBlur\b')"

printf 'canvas=%s\n' "$canvas_count"
printf 'canvas_framebuffer_object=%s\n' "$canvas_fbo_count"
printf 'layer_enabled=%s\n' "$layer_count"
printf 'unconditional_layer_enabled=%s\n' "$unconditional_layer_count"
printf 'clip_true=%s\n' "$clip_true_count"
printf 'number_animation=%s\n' "$number_animation_count"
printf 'behavior_on=%s\n' "$behavior_count"
printf 'timer=%s\n' "$timer_count"
printf 'shader_or_graphical_effect=%s\n' "$shader_effect_count"

echo
echo "[qml-risk] hard-risk lines"
rg -n --glob '*.qml' --glob '*.cpp' --glob '*.h' \
  'layer\.enabled:[[:space:]]*true|\bShaderEffect\b|\bMultiEffect\b|\bOpacityMask\b|\bDropShadow\b|\bFastBlur\b' \
  src/ui src/render || true

echo
echo "[qml-risk] top source files by risk-token count"
rg -n --glob '*.qml' --glob '*.cpp' --glob '*.h' \
  '\bCanvas\s*\{|renderTarget:[[:space:]]*Canvas\.FramebufferObject|layer\.enabled|clip:[[:space:]]*true|\bNumberAnimation\b|\bBehavior on\b|\bTimer\s*\{|\bShaderEffect\b|\bMultiEffect\b|\bOpacityMask\b|\bDropShadow\b|\bFastBlur\b' \
  src/ui src/render \
  | awk -F: '{ counts[$1]++ } END { for (file in counts) printf "%5d %s\n", counts[file], file }' \
  | sort -nr \
  | head -20 || true

if [[ "$STRICT" == "1" ]]; then
  failures=0
  if [[ "$unconditional_layer_count" != "0" ]]; then
    echo "[qml-risk] FAIL: unconditional layer.enabled exists" >&2
    failures=$((failures + 1))
  fi
  if [[ "$shader_effect_count" != "0" ]]; then
    echo "[qml-risk] FAIL: shader/graphical effect token exists" >&2
    failures=$((failures + 1))
  fi
  if [[ "$failures" -gt 0 ]]; then
    exit 1
  fi
fi

echo "[qml-risk] PASS"
