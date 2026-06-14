#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${BEAGLEY_HOST:-root@beagley-ai.local}"

usage() {
  cat <<'EOF'
Usage:
  tools/ui/beagley_display_status.sh [options]

Options:
  --host HOST   SSH target. Default: root@beagley-ai.local
  -h, --help    Show this help.

Reports what the actual BeagleY display is running: deployed binary build
provenance, process environment, QML-dev source manifest, and service state.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[beagley-display] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "[local]"
printf 'repo_path=%s\n' "$ROOT"
printf 'git_branch=%s\n' "$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || printf unknown)"
printf 'git_commit=%s\n' "$(cd "$ROOT" && git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
printf 'git_dirty_count=%s\n' "$(cd "$ROOT" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

echo
echo "[beagley]"
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$HOST" 'sh -s' <<'REMOTE'
set -eu

unit=beagley_cluster
pid="$(systemctl show -p MainPID --value "$unit" 2>/dev/null || true)"
active="$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || true)"
sub="$(systemctl show -p SubState --value "$unit" 2>/dev/null || true)"
restarts="$(systemctl show -p NRestarts --value "$unit" 2>/dev/null || true)"

printf 'service=%s/%s\n' "${active:-unknown}" "${sub:-unknown}"
printf 'main_pid=%s\n' "${pid:-unknown}"
printf 'n_restarts=%s\n' "${restarts:-unknown}"

if [ -z "${pid:-}" ] || [ "$pid" = "0" ] || [ ! -r "/proc/$pid/environ" ]; then
  echo 'process_env=unavailable'
  exit 0
fi

env_dump="$(tr '\0' '\n' <"/proc/$pid/environ")"
echo
echo "[process-env]"
printf '%s\n' "$env_dump" \
  | grep -E '^(BEAGLEY_DISPLAY_PROFILE|BEAGLEY_UI_VARIANT|BEAGLEY_RENDER_PROFILE|BEAGLEY_EFFECT_LEVEL|BEAGLEY_GAUGE_DETAIL|BEAGLEY_GAUGE_DEMO|BEAGLEY_CLUSTER_SIMULATION|BEAGLEY_MAP_RENDERER|BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL|BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY|BEAGLEY_QML_DEV_ROOT|BEAGLEY_QML_DEV_FILE|BEAGLEY_STRESS_SCENE|QSG_RENDER_LOOP|VEHICLE_HUB_WS_URL)=' \
  | sort || true

qml_root="$(printf '%s\n' "$env_dump" | sed -n 's/^BEAGLEY_QML_DEV_ROOT=//p' | tail -n 1)"
echo
echo "[display-source]"
if [ -n "$qml_root" ]; then
  printf 'qml_source=qml-dev\n'
  printf 'qml_root=%s\n' "$qml_root"
  manifest="$qml_root/.beagley-qml-manifest"
  if [ -r "$manifest" ]; then
    echo
    echo "[qml-manifest]"
    cat "$manifest"
  else
    printf 'qml_manifest=missing\n'
  fi
else
  printf 'qml_source=compiled-binary\n'
fi

echo
echo "[build-log]"
build_log="$(journalctl -b -u "$unit" --no-pager 2>/dev/null | grep '\[BUILD\]' | tail -n 1 || true)"
boot_log="$(journalctl -b -u "$unit" --no-pager 2>/dev/null | grep '\[BOOT\]' | tail -n 1 || true)"
if [ -n "$build_log" ]; then
  printf '%s\n' "$build_log"
else
  echo 'build_log=missing'
fi
if [ -n "$boot_log" ]; then
  printf '%s\n' "$boot_log"
else
  echo 'boot_log=missing'
fi
REMOTE
