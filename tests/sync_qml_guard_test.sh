#!/usr/bin/env bash
# Tests the live-runtime guard of tools/ui/beagley_sync_qml.sh with a fake `ssh`.
# The fake ssh never touches a real host: it executes only the read-only probe
# (BEAGLEY_LIVE_PROBE) locally and merely records every other command (the destructive rm -rf
# sync), so "was anything deleted?" == "did a non-probe ssh command run?".
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/tools/ui/beagley_sync_qml.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
LOG="$T/ssh.log"
cat >"$T/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
cmd="${*: -1}"
if [[ "$cmd" == *BEAGLEY_LIVE_PROBE* ]]; then
  echo "PROBE" >>"$SSH_LOG"
  sh -c "$cmd"
  exit $?
fi
[[ ! -t 0 ]] && cat >/dev/null
echo "CMD: $cmd" >>"$SSH_LOG"
exit 0
FAKE
chmod +x "$T/bin/ssh"
export PATH="$T/bin:$PATH" SSH_LOG="$LOG"

fail=0
run() { # name expected_rc expect_destructive(0/1) root
  local name="$1" want_rc="$2" want_cmd="$3" root="$4" rc
  : >"$LOG"
  BEAGLEY_HOST=fake@host "$SCRIPT" --remote-root "$root" --no-restart --no-health </dev/null >"$T/out" 2>&1
  rc=$?
  local ran=0
  grep -q "rm -rf" "$LOG" && ran=1
  if [[ "$rc" -ne "$want_rc" || "$ran" -ne "$want_cmd" ]]; then
    echo "FAIL: $name (rc=$rc want $want_rc, destructive-ssh=$ran want $want_cmd)"
    sed 's/^/    | /' "$T/out"
    fail=1
  else
    echo "ok:   $name"
  fi
}

# --- path rules (rejected locally, ssh never reached) ---
run "refuse /data/beagley-cluster/runtime-x/source" 2 0 /data/beagley-cluster/runtime-drive-1/source
run "refuse /data/beagley-cluster/anything/else"   2 0 /data/beagley-cluster/qml/dev
run "refuse runtime-* segment elsewhere"           2 0 /srv/foo/runtime-abc/source
[[ ! -s "$LOG" ]] || { echo "FAIL: ssh was contacted for a path-rule refusal"; fail=1; }

# --- remote marker probe (executed locally by the fake ssh) ---
mkdir -p "$T/live/qml/dev" "$T/live2/src/x" "$T/clean/qml/dev" "$T/bin2/qml/dev/inner"
touch "$T/live/launch.sh"                      # marker in a parent of the root
run "refuse root whose parent has launch.sh" 2 0 "$T/live/qml/dev"
mkdir -p "$T/live2/bin"; touch "$T/live2/bin/beagley_cluster"
run "refuse root under dir holding bin/beagley_cluster" 2 0 "$T/live2/src/x"
touch "$T/bin2/qml/dev/.live"
run "refuse root containing a .live marker" 2 0 "$T/bin2/qml/dev"
run "refuse root below a .live marker" 2 0 "$T/bin2/qml/dev/inner"

# --- clean target proceeds (sync + manifest ssh calls happen) ---
run "allow a clean dev root" 0 1 "$T/clean/qml/dev"
grep -q "rm -rf" "$LOG" || { echo "FAIL: clean root did not reach the sync"; fail=1; }

# a failing probe (ssh error) must NOT continue to the destructive step
cat >"$T/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
cmd="${*: -1}"
[[ "$cmd" == *BEAGLEY_LIVE_PROBE* ]] && exit 255
[[ ! -t 0 ]] && cat >/dev/null
echo "CMD: $cmd" >>"$SSH_LOG"
exit 0
FAKE
run "probe failure aborts before deleting" 1 0 "$T/clean/qml/dev"

exit "$fail"
