#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BEAGLEY_COMMON="$ROOT/skills/beagley-common/scripts/ssh.sh"
ELITEBOOK_KEY="${ELITEBOOK_SSH_KEY:-$HOME/.ssh/pneumaion_elitebook}"
ELITEBOOK_REPO="${ELITEBOOK_REPO:-/home/pneumaion/projects/beagley-cluster}"
ELITEBOOK_YOCTO_BUILD_DIR="${ELITEBOOK_YOCTO_BUILD_DIR:-/home/pneumaion/ti-sdk-11.00/yocto-build/build}"
SOURCE_REMOTE="${BEAGLEY_SOURCE_REMOTE:-https://github.com/Ajkopensesame/beagley-cluster.git}"
RUN_BEAGLEY=1
RUN_ELITEBOOK=1
RUN_GITHUB=0
RUN_FULL_BEAGLEY=0
RUN_SOURCE_GUARD=0
FAILURES=0
WARNINGS=0

usage() {
  cat <<'EOF'
Usage:
  skills/lab-status/scripts/status.sh [options]

Checks local repo, BeagleY runtime/network, EliteBook builder/sandbox, and
optionally GitHub/source alignment.

Options:
  --beagley-only       Check only BeagleY plus local repo context
  --elitebook-only     Check only EliteBook plus local repo context
  --github            Check local HEAD against the configured GitHub/source remote
  --full-beagley       Run the verbose BeagleY network-status helper
  --source-guard       Run the EliteBook build-source guard
  -h, --help           Show this help

Environment:
  ELITEBOOK_TARGETS    Space/comma separated SSH targets.
                       Default: ELITEBOOK_HOST, then
                       pneumaion@192.168.0.149 pneumaion@172.20.10.9 elitebook-sandbox
EOF
}

section() {
  printf '\n=== %s ===\n' "$1"
}

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s\n' "$1"
}

csv_to_words() {
  printf '%s\n' "$1" | tr ',' ' '
}

ssh_base_opts() {
  printf '%s\0' \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ConnectionAttempts=1 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=1 \
    -o StrictHostKeyChecking=accept-new
}

elitebook_ssh_opts=()
while IFS= read -r -d '' opt; do
  elitebook_ssh_opts+=("$opt")
done < <(ssh_base_opts)
if [[ -f "$ELITEBOOK_KEY" ]]; then
  elitebook_ssh_opts+=(-i "$ELITEBOOK_KEY")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beagley-only)
      RUN_BEAGLEY=1
      RUN_ELITEBOOK=0
      shift
      ;;
    --elitebook-only)
      RUN_BEAGLEY=0
      RUN_ELITEBOOK=1
      shift
      ;;
    --github)
      RUN_GITHUB=1
      shift
      ;;
    --full-beagley)
      RUN_FULL_BEAGLEY=1
      shift
      ;;
    --source-guard)
      RUN_SOURCE_GUARD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[lab-status] unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

check_local_repo() {
  section "local-repo"
  if [[ ! -d "$ROOT/.git" ]]; then
    fail "not a git checkout: $ROOT"
    return
  fi

  local branch commit dirty_count
  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  commit="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || true)"
  dirty_count="$(git -C "$ROOT" status --porcelain 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"

  printf 'root=%s\n' "$ROOT"
  printf 'branch=%s\n' "${branch:-detached}"
  printf 'commit=%s\n' "${commit:-unknown}"
  printf 'dirty_changes=%s\n' "${dirty_count:-unknown}"

  if [[ "${dirty_count:-0}" != "0" ]]; then
    warn "local checkout has ${dirty_count} uncommitted change(s)"
  else
    ok "local checkout clean"
  fi
}

check_github() {
  section "github-source"
  local branch commit remote_commit output

  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  commit="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || -z "$commit" ]]; then
    fail "cannot determine local branch/commit"
    return
  fi

  output="$(
    GIT_TERMINAL_PROMPT=0 git -C "$ROOT" \
      -c http.lowSpeedLimit=1 \
      -c http.lowSpeedTime=8 \
      ls-remote --heads "$SOURCE_REMOTE" "$branch" 2>&1
  )"
  if [[ $? -ne 0 ]]; then
    printf '%s\n' "$output"
    fail "could not query source remote: $SOURCE_REMOTE"
    return
  fi

  remote_commit="$(
    printf '%s\n' "$output" \
      | awk -v ref="refs/heads/${branch}" '$2 == ref { print $1; found=1 } END { exit !found }'
  )" || {
    fail "remote has no branch ${branch}: $SOURCE_REMOTE"
    return
  }

  printf 'remote=%s\nbranch=%s\nlocal=%s\nremote_head=%s\n' \
    "$SOURCE_REMOTE" "$branch" "$commit" "$remote_commit"
  if [[ "$remote_commit" == "$commit" ]]; then
    ok "local HEAD matches source remote"
  else
    fail "local HEAD does not match source remote"
  fi
}

check_beagley() {
  section "beagley"
  if [[ ! -f "$BEAGLEY_COMMON" ]]; then
    fail "missing BeagleY SSH helper: $BEAGLEY_COMMON"
    return
  fi

  # shellcheck source=/dev/null
  source "$BEAGLEY_COMMON"
  if ! beagley_require_ssh_target; then
    fail "no reachable BeagleY SSH target"
    return
  fi
  ok "BeagleY SSH reachable: $BEAGLEY_SSH_HOST"

  beagley_ssh "bash -s" <<'REMOTE'
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "--- identity"
hostname || true
date -Iseconds 2>/dev/null || date || true
echo "--- app-service"
systemctl show beagley_cluster -p ActiveState -p SubState -p NRestarts -p MainPID --no-pager 2>/dev/null || true
echo "--- display-source"
pid="$(systemctl show beagley_cluster -p MainPID --value 2>/dev/null || true)"
if [ -n "${pid:-}" ] && [ "$pid" != "0" ] && [ -r "/proc/$pid/environ" ]; then
  tr '\0' '\n' <"/proc/$pid/environ" \
    | grep -E '^(BEAGLEY_UI_VARIANT|BEAGLEY_RENDER_PROFILE|BEAGLEY_EFFECT_LEVEL|BEAGLEY_GAUGE_DETAIL|BEAGLEY_GAUGE_DEMO|BEAGLEY_CLUSTER_SIMULATION|BEAGLEY_MAP_RENDERER|BEAGLEY_QML_DEV_ROOT|BEAGLEY_STRESS_SCENE|QSG_RENDER_LOOP)=' \
    | sort || true
  qml_root="$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^BEAGLEY_QML_DEV_ROOT=//p' | tail -n 1)"
  if [ -n "${qml_root:-}" ]; then
    echo "qml_source=qml-dev"
    if [ -r "$qml_root/.beagley-qml-manifest" ]; then
      sed 's/^/qml_manifest./' "$qml_root/.beagley-qml-manifest"
    else
      echo "qml_manifest=missing"
    fi
  else
    echo "qml_source=compiled-binary"
  fi
else
  echo "process_env=unavailable"
fi
journalctl -b -u beagley_cluster --no-pager 2>/dev/null | grep '\[BUILD\]' | tail -n 1 || true
echo "--- wifi"
wpa_cli -i wlan0 status 2>/dev/null | awk -F= '$1 ~ /^(ssid|id_str|wpa_state|ip_address)$/ { print }' || true
iw dev wlan0 link 2>/dev/null | awk '/SSID:|signal:/ { sub(/^[ \t]+/, ""); print }' || true
echo "--- routes"
ip route show default 2>/dev/null || true
echo "--- watchdog"
systemctl show beagley-hotspot-watchdog.timer -p ActiveState -p SubState --no-pager 2>/dev/null || true
REMOTE

  local active restarts wifi_state
  active="$(beagley_ssh "systemctl show beagley_cluster -p ActiveState --value" 2>/dev/null || true)"
  restarts="$(beagley_ssh "systemctl show beagley_cluster -p NRestarts --value" 2>/dev/null || true)"
  wifi_state="$(beagley_ssh "wpa_cli -i wlan0 status 2>/dev/null | awk -F= '\$1==\"wpa_state\"{print \$2; exit}'" 2>/dev/null || true)"

  if [[ "$active" == "active" && "${restarts:-0}" == "0" ]]; then
    ok "BeagleY app service active with NRestarts=0"
  else
    fail "BeagleY app service active=${active:-unknown} NRestarts=${restarts:-unknown}"
  fi

  if [[ "$wifi_state" == "COMPLETED" ]]; then
    ok "BeagleY wlan0 associated"
  else
    fail "BeagleY wlan0 state=${wifi_state:-unknown}"
  fi

  if [[ "$RUN_FULL_BEAGLEY" == 1 ]]; then
    section "beagley-full-network"
    "$ROOT/skills/beagley-network-status/scripts/status.sh" || fail "full BeagleY network status failed"
  fi
}

elitebook_targets() {
  if [[ -n "${ELITEBOOK_TARGETS:-}" ]]; then
    csv_to_words "$ELITEBOOK_TARGETS"
    return
  fi
  if [[ -n "${ELITEBOOK_HOST:-}" ]]; then
    printf '%s\n' "$ELITEBOOK_HOST"
  fi
  printf '%s\n' \
    pneumaion@192.168.0.149 \
    pneumaion@172.20.10.9 \
    elitebook-sandbox
}

pick_elitebook_target() {
  local target
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if ssh "${elitebook_ssh_opts[@]}" "$target" true >/dev/null 2>&1; then
      printf '%s\n' "$target"
      return 0
    fi
  done < <(elitebook_targets | awk 'NF && !seen[$0]++')
  return 1
}

check_elitebook() {
  section "elitebook"
  local target
  target="$(pick_elitebook_target || true)"
  if [[ -z "$target" ]]; then
    fail "no reachable EliteBook SSH target"
    printf 'tried_targets=%s\n' "$(elitebook_targets | paste -sd' ' -)"
    return
  fi
  ok "EliteBook SSH reachable: $target"

  ssh "${elitebook_ssh_opts[@]}" "$target" bash -s -- \
    "$ELITEBOOK_REPO" "$ELITEBOOK_YOCTO_BUILD_DIR" <<'REMOTE'
set -u
repo="$1"
build_dir="$2"
echo "--- identity"
hostname || true
date -Iseconds 2>/dev/null || date || true
uname -a || true
uptime -p 2>/dev/null || uptime || true
echo "--- addresses"
ip -br addr 2>/dev/null || true
echo "--- disk"
df -h / /home 2>/dev/null || df -h / || true
echo "--- codex"
if command -v codex >/dev/null 2>&1; then
  command -v codex
elif [ -x /snap/bin/codex ]; then
  echo /snap/bin/codex
else
  echo missing
fi
echo "--- repo"
if [ -d "$repo/.git" ]; then
  echo "repo=$repo"
  git -C "$repo" branch --show-current 2>/dev/null || true
  git -C "$repo" rev-parse --short=12 HEAD 2>/dev/null || true
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  echo "dirty_changes=${dirty:-unknown}"
  if [ -x "$repo/tools/yocto/verify_beagley_build_source.sh" ]; then
    echo "verifier=ok"
  else
    echo "verifier=missing"
  fi
else
  echo "repo_missing=$repo"
fi
echo "--- yocto"
if [ -f "$build_dir/conf/setenv" ]; then
  echo "yocto_build_dir=$build_dir"
  echo "setenv=ok"
else
  echo "yocto_setenv_missing=$build_dir/conf/setenv"
fi
REMOTE

  if [[ "$RUN_SOURCE_GUARD" == 1 ]]; then
    section "elitebook-source-guard"
    "$ROOT/skills/beagley-build-source-guard/scripts/check.sh" --elitebook-only --elitebook-host "$target" \
      || fail "EliteBook source guard failed"
  fi
}

check_local_repo
if [[ "$RUN_GITHUB" == 1 ]]; then
  check_github
else
  section "github-source"
  echo "skipped=use --github for source remote alignment"
fi
if [[ "$RUN_BEAGLEY" == 1 ]]; then
  check_beagley
fi
if [[ "$RUN_ELITEBOOK" == 1 ]]; then
  check_elitebook
fi

section "summary"
printf 'warnings=%s\nfailures=%s\n' "$WARNINGS" "$FAILURES"
if [[ "$FAILURES" -gt 0 ]]; then
  echo "[lab-status] FAIL"
  exit 1
fi
echo "[lab-status] PASS"
