#!/usr/bin/env bash
set -u -o pipefail

GPU_GATE_BIN="${BEAGLEY_GPU_GATE_BIN:-/usr/bin/beagley-gpu-gate}"
GPU_GATE_FILE="${BEAGLEY_GPU_GATE_FILE:-/run/beagley_gpu_gate.ok}"
GPU_PROBE_STATUS_FILE="${BEAGLEY_GPU_PROBE_STATUS_FILE:-/run/beagley_gpu_gate.status}"
GPU_PROBE_LOG_FILE="${BEAGLEY_GPU_PROBE_LOG_FILE:-/run/beagley_gpu_gate.log}"
GPU_GATE_MODE="${BEAGLEY_GPU_GATE_MODE:-appliance}"
GPU_GATE_TIMEOUT="${BEAGLEY_GPU_GATE_TIMEOUT:-45}"
GPU_GATE_RETRY_INTERVAL="${BEAGLEY_GPU_GATE_RETRY_INTERVAL:-3}"

log() {
  echo "[gpu-probe] $*"
}

mkdir -p "$(dirname "$GPU_GATE_FILE")" "$(dirname "$GPU_PROBE_STATUS_FILE")" "$(dirname "$GPU_PROBE_LOG_FILE")"
rm -f "$GPU_GATE_FILE" "$GPU_PROBE_STATUS_FILE" "$GPU_PROBE_LOG_FILE"

if [[ ! "$GPU_GATE_TIMEOUT" =~ ^[0-9]+$ ]]; then
  GPU_GATE_TIMEOUT=45
fi
if [[ ! "$GPU_GATE_RETRY_INTERVAL" =~ ^[0-9]+$ || "$GPU_GATE_RETRY_INTERVAL" -lt 1 ]]; then
  GPU_GATE_RETRY_INTERVAL=3
fi

timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
probe_output=""
probe_status="fail"
probe_exit_code=0
attempts=0
deadline=$((SECONDS + GPU_GATE_TIMEOUT))

while :; do
  attempts=$((attempts + 1))
  if [[ ! -x "$GPU_GATE_BIN" ]]; then
    probe_exit_code=127
    probe_output="[gpu-probe] FAIL: gpu gate binary is missing or not executable: ${GPU_GATE_BIN}"
    break
  elif probe_output="$("$GPU_GATE_BIN" --strict --mode "$GPU_GATE_MODE" --write-ok "$GPU_GATE_FILE" 2>&1)"; then
    probe_status="pass"
    probe_exit_code=0
    break
  else
    probe_exit_code=$?
  fi

  if (( SECONDS >= deadline )); then
    break
  fi
  sleep "$GPU_GATE_RETRY_INTERVAL"
done

printf '%s\n' "$probe_output" >"$GPU_PROBE_LOG_FILE"

renderer="$(
  printf '%s\n' "$probe_output" \
    | sed -n 's/.*renderer=\(.*\) lock=.*/\1/p' \
    | tail -n 1
)"
message="$(
  printf '%s\n' "$probe_output" \
    | sed -n 's/^\[[^]]*\] \(PASS\|FAIL\):\? //p' \
    | tail -n 1
)"
if [[ -z "$message" ]]; then
  message="$(
    printf '%s\n' "$probe_output" \
      | awk '
          NF { line = $0 }
          END {
            sub(/^\[[^]]*\][[:space:]]*/, "", line)
            print line
          }
        '
  )"
fi

{
  echo "status=${probe_status}"
  echo "timestamp_utc=${timestamp_utc}"
  echo "mode=${GPU_GATE_MODE}"
  echo "ok_file=${GPU_GATE_FILE}"
  echo "log_file=${GPU_PROBE_LOG_FILE}"
  echo "exit_code=${probe_exit_code}"
  echo "attempts=${attempts}"
  if [[ -n "$renderer" ]]; then
    echo "renderer=${renderer}"
  fi
  if [[ -n "$message" ]]; then
    echo "message=${message}"
  fi
} >"$GPU_PROBE_STATUS_FILE"

if [[ "$probe_status" == "pass" ]]; then
  log "PASS renderer=${renderer:-unknown} report=${GPU_PROBE_STATUS_FILE}"
else
  rm -f "$GPU_GATE_FILE"
  log "FAIL report=${GPU_PROBE_STATUS_FILE} log=${GPU_PROBE_LOG_FILE}"
fi

exit "$probe_exit_code"
