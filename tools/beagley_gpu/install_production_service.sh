#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/home/debian/projects/beagley-cluster"
PROJECT_USER="debian"
PROJECT_GROUP="debian"
UNIT_NAME="beagley_cluster.service"
SYSTEMD_UNIT_DIR="/etc/systemd/system"
DEFAULT_ENV_FILE="/etc/default/beagley-cluster"
ENABLE_NOW=0

usage() {
  cat <<'EOF'
Usage: install_production_service.sh [options]

Installs the Beagley cluster production service so the UI always launches
through the strict embedded GPU gate.

Options:
  --project-root <path>    Repo root on the Beagley (default: /home/debian/projects/beagley-cluster)
  --user <name>            Service user (default: debian)
  --group <name>           Service group (default: debian)
  --unit-name <name>       Systemd unit name (default: beagley_cluster.service)
  --enable-now             Enable and start the service immediately
  -h, --help               Show help
EOF
}

fail() {
  echo "[cluster-service] FAIL: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --user)
      PROJECT_USER="${2:-}"
      shift 2
      ;;
    --group)
      PROJECT_GROUP="${2:-}"
      shift 2
      ;;
    --unit-name)
      UNIT_NAME="${2:-}"
      shift 2
      ;;
    --enable-now)
      ENABLE_NOW=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ $EUID -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT_ROOT" ]] || fail "project root not found: $PROJECT_ROOT"
[[ -f "$SCRIPT_DIR/beagley-cluster.service.in" ]] || fail "missing service template"
[[ -f "$SCRIPT_DIR/beagley-cluster.env.example" ]] || fail "missing env example"

UNIT_PATH="${SYSTEMD_UNIT_DIR}/${UNIT_NAME}"
mkdir -p "$SYSTEMD_UNIT_DIR" "$(dirname "$DEFAULT_ENV_FILE")"

sed \
  -e "s|__PROJECT_ROOT__|${PROJECT_ROOT}|g" \
  -e "s|__PROJECT_USER__|${PROJECT_USER}|g" \
  -e "s|__PROJECT_GROUP__|${PROJECT_GROUP}|g" \
  "$SCRIPT_DIR/beagley-cluster.service.in" >"$UNIT_PATH"

if [[ ! -f "$DEFAULT_ENV_FILE" ]]; then
  install -m 0644 "$SCRIPT_DIR/beagley-cluster.env.example" "$DEFAULT_ENV_FILE"
fi

systemctl daemon-reload
systemctl enable "$UNIT_NAME"

if [[ $ENABLE_NOW -eq 1 ]]; then
  systemctl restart "$UNIT_NAME"
fi

echo "[cluster-service] installed unit=$UNIT_PATH env=$DEFAULT_ENV_FILE"
