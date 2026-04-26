#!/usr/bin/env bash
set -euo pipefail

SRC="${BBB_BENCH_SIM_SRC:-/home/debian/projects/beagley-cluster/tools/bbb_hub/bbb_bench_vehicle_sim.sh}"
DEST="${BBB_BENCH_SIM_DEST:-/usr/local/sbin/bbb-bench-sim}"
SUDOERS="${BBB_BENCH_SIM_SUDOERS:-/etc/sudoers.d/bbb-bench-sim}"
USER_NAME="${BBB_BENCH_SIM_USER:-debian}"

usage() {
  cat <<'EOF'
Usage:
  tools/bbb_hub/install_bbb_bench_sim_toggle.sh

Run this on the BBB. It installs a root-owned bbb-bench-sim command and a
limited sudoers rule so the debian user can switch the production vehicle hub
between bench simulation and real vehicle inputs without a password.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

run_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ ! -f "$SRC" ]]; then
  echo "[bbb-bench-sim-install] missing source script: $SRC" >&2
  exit 1
fi

TMP_SCRIPT="$(mktemp)"
TMP_SUDOERS="$(mktemp)"
trap 'rm -f "$TMP_SCRIPT" "$TMP_SUDOERS"' EXIT

cp "$SRC" "$TMP_SCRIPT"

cat >"$TMP_SUDOERS" <<EOF
# Installed by /home/debian/projects/beagley-cluster/tools/bbb_hub/install_bbb_bench_sim_toggle.sh
$USER_NAME ALL=(root) NOPASSWD: $DEST enable
$USER_NAME ALL=(root) NOPASSWD: $DEST disable
$USER_NAME ALL=(root) NOPASSWD: $DEST status
EOF

run_root install -o root -g root -m 0755 "$TMP_SCRIPT" "$DEST"
run_root install -o root -g root -m 0440 "$TMP_SUDOERS" "$SUDOERS"
run_root visudo -cf "$SUDOERS" >/dev/null

echo "[bbb-bench-sim-install] installed $DEST"
echo "[bbb-bench-sim-install] installed $SUDOERS"
echo "[bbb-bench-sim-install] commands:"
echo "  sudo bbb-bench-sim status"
echo "  sudo bbb-bench-sim enable"
echo "  sudo bbb-bench-sim disable"
