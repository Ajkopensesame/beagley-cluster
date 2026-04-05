#!/usr/bin/env bash

MAC_BUILDER_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_BUILDER_SETTINGS_STORE_JSON="${HOME}/Library/Group Containers/group.com.docker/settings-store.json"
MAC_BUILDER_SETTINGS_JSON="${HOME}/Library/Group Containers/group.com.docker/settings.json"
MAC_BUILDER_VM_CONSOLE_LOG="${HOME}/Library/Containers/com.docker.docker/Data/log/vm/console.log"
MAC_BUILDER_BACKEND_LOG="${HOME}/Library/Containers/com.docker.docker/Data/log/host/com.docker.backend.log"
MAC_BUILDER_DEFAULT_VOLUME_NAME="BeagleyBuilder"
MAC_BUILDER_DEFAULT_DOCKER_VOLUME="beagley-ti-sdk-11-workspace"
MAC_BUILDER_DEFAULT_IMAGE_TAG="beagley-yocto-builder:11.00"
MAC_BUILDER_DEFAULT_CONTAINER_NAME="beagley-yocto-builder-mac"
MAC_BUILDER_DEFAULT_MEMORY_MIB=5632
MAC_BUILDER_DEFAULT_SWAP_MIB=4096
MAC_BUILDER_DEFAULT_CPUS=8
MAC_BUILDER_DEFAULT_DISK_SIZE_MIB=1048576
MAC_BUILDER_DEFAULT_MIN_FREE_GIB=500
MAC_BUILDER_DEFAULT_MIN_CAPACITY_GIB=900
MAC_BUILDER_DEFAULT_SMOKE_TEST_GIB=2

mac_builder_log() {
  printf '[yocto-mac] %s\n' "$*"
}

mac_builder_fail() {
  printf '[yocto-mac] FAIL: %s\n' "$*" >&2
  exit 1
}

mac_builder_require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || mac_builder_fail "macOS only"
}

mac_builder_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || mac_builder_fail "missing required command: $1"
}

mac_builder_docker_bin() {
  if command -v docker >/dev/null 2>&1; then
    command -v docker
    return
  fi
  if [[ -x /usr/local/bin/docker ]]; then
    printf '/usr/local/bin/docker\n'
    return
  fi
  if [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
    printf '/Applications/Docker.app/Contents/Resources/bin/docker\n'
    return
  fi
  mac_builder_fail "docker CLI not found"
}

mac_builder_settings_file() {
  if [[ -f "$MAC_BUILDER_SETTINGS_STORE_JSON" ]]; then
    printf '%s\n' "$MAC_BUILDER_SETTINGS_STORE_JSON"
    return
  fi
  if [[ -f "$MAC_BUILDER_SETTINGS_JSON" ]]; then
    printf '%s\n' "$MAC_BUILDER_SETTINGS_JSON"
    return
  fi
  mac_builder_fail "Docker Desktop settings JSON not found"
}

mac_builder_volume_mount() {
  printf '/Volumes/%s\n' "$1"
}

mac_builder_gib_to_bytes() {
  local gib="$1"
  printf '%s\n' $((gib * 1024 * 1024 * 1024))
}

mac_builder_free_bytes() {
  local path="$1"
  df -kP "$path" | awk 'NR == 2 { print $4 * 1024 }'
}

mac_builder_total_bytes() {
  local path="$1"
  diskutil info -plist "$path" | python3 - <<'PY'
import plistlib
import sys

data = plistlib.load(sys.stdin.buffer)
print(int(data.get("TotalSize", 0)))
PY
}

mac_builder_assert_volume_mounted() {
  local mount_path="$1"
  [[ -d "$mount_path" ]] || mac_builder_fail "external volume is not mounted at $mount_path"
}

mac_builder_assert_apfs() {
  local mount_path="$1"
  local fs_type

  fs_type="$(diskutil info "$mount_path" 2>/dev/null | awk -F: '
    /File System Personality/ || /Type \(Bundle\)/ {
      gsub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ')"
  [[ "$fs_type" == "APFS" || "$fs_type" == "apfs" ]] || mac_builder_fail "expected APFS volume at $mount_path, found ${fs_type:-unknown}"
}

mac_builder_verify_volume() {
  local mount_path="$1"
  diskutil verifyVolume "$mount_path"
}

mac_builder_check_free_space() {
  local path="$1"
  local min_bytes="$2"
  local free_bytes

  free_bytes="$(mac_builder_free_bytes "$path")"
  if (( free_bytes < min_bytes )); then
    mac_builder_fail "free space at $path is below the required threshold: ${free_bytes} bytes available, ${min_bytes} bytes required"
  fi
}

mac_builder_check_total_capacity() {
  local path="$1"
  local min_bytes="$2"
  local total_bytes

  total_bytes="$(mac_builder_total_bytes "$path")"
  if (( total_bytes < min_bytes )); then
    mac_builder_fail "volume at $path is below the required capacity: ${total_bytes} bytes total, ${min_bytes} bytes required"
  fi
}

mac_builder_dump_settings() {
  python3 - "$MAC_BUILDER_SETTINGS_STORE_JSON" "$MAC_BUILDER_SETTINGS_JSON" <<'PY'
import json
import os
import sys

store_path, legacy_path = sys.argv[1:3]
aliases = {
    "Cpus": ("Cpus", "cpus"),
    "MemoryMiB": ("MemoryMiB", "memoryMiB"),
    "SwapMiB": ("SwapMiB", "swapMiB"),
    "DiskSizeMiB": ("DiskSizeMiB", "diskSizeMiB"),
    "DataFolder": ("DataFolder", "dataFolder"),
    "UseResourceSaver": ("UseResourceSaver", "useResourceSaver"),
    "AutoPauseTimeoutSeconds": ("AutoPauseTimeoutSeconds", "autoPauseTimeoutSeconds"),
}

files = []
for path, style in ((store_path, "store"), (legacy_path, "legacy")):
    if os.path.exists(path):
        with open(path) as fh:
            files.append((style, json.load(fh)))

if not files:
    sys.exit("Docker Desktop settings JSON not found")

for canonical, (store_key, legacy_key) in aliases.items():
    value = None
    for style, data in files:
      key = store_key if style == "store" else legacy_key
      if key in data:
        value = data[key]
        break
    print(f"{canonical}={value}")
PY
}

mac_builder_assert_docker_settings() {
  local expected_data_folder="$1"
  local expected_cpus="$2"
  local expected_memory_mib="$3"
  local expected_swap_mib="$4"
  local expected_disk_size_mib="$5"
  local expected_use_resource_saver="$6"
  local expected_auto_pause_timeout="$7"

  python3 - \
    "$MAC_BUILDER_SETTINGS_STORE_JSON" \
    "$MAC_BUILDER_SETTINGS_JSON" \
    "$expected_data_folder" \
    "$expected_cpus" \
    "$expected_memory_mib" \
    "$expected_swap_mib" \
    "$expected_disk_size_mib" \
    "$expected_use_resource_saver" \
    "$expected_auto_pause_timeout" <<'PY'
import json
import os
import sys

store_path, legacy_path, data_folder, cpus, memory_mib, swap_mib, disk_size_mib, use_resource_saver, auto_pause_timeout = sys.argv[1:10]
aliases = {
    "DataFolder": ("DataFolder", "dataFolder", data_folder),
    "Cpus": ("Cpus", "cpus", int(cpus)),
    "MemoryMiB": ("MemoryMiB", "memoryMiB", int(memory_mib)),
    "SwapMiB": ("SwapMiB", "swapMiB", int(swap_mib)),
    "DiskSizeMiB": ("DiskSizeMiB", "diskSizeMiB", int(disk_size_mib)),
    "UseResourceSaver": ("UseResourceSaver", "useResourceSaver", use_resource_saver.lower() == "true"),
    "AutoPauseTimeoutSeconds": ("AutoPauseTimeoutSeconds", "autoPauseTimeoutSeconds", int(auto_pause_timeout)),
}

files = []
for path, style in ((store_path, "store"), (legacy_path, "legacy")):
    if os.path.exists(path):
        with open(path) as fh:
            files.append((path, style, json.load(fh)))

if not files:
    print("Docker Desktop settings JSON not found", file=sys.stderr)
    sys.exit(1)

mismatches = []
for path, style, data in files:
    for canonical, (store_key, legacy_key, expected) in aliases.items():
        key = store_key if style == "store" else legacy_key
        actual = data.get(key)
        if actual != expected:
            mismatches.append(f"{path}: {key}={actual!r}, expected {expected!r}")

if mismatches:
    print("\n".join(mismatches), file=sys.stderr)
    sys.exit(1)
PY
}

mac_builder_apply_docker_settings() {
  local desired_data_folder="$1"
  local desired_cpus="$2"
  local desired_memory_mib="$3"
  local desired_swap_mib="$4"
  local desired_disk_size_mib="$5"
  local desired_use_resource_saver="$6"
  local desired_auto_pause_timeout="$7"

  python3 - \
    "$MAC_BUILDER_SETTINGS_STORE_JSON" \
    "$MAC_BUILDER_SETTINGS_JSON" \
    "$desired_data_folder" \
    "$desired_cpus" \
    "$desired_memory_mib" \
    "$desired_swap_mib" \
    "$desired_disk_size_mib" \
    "$desired_use_resource_saver" \
    "$desired_auto_pause_timeout" <<'PY'
import json
import os
import sys

store_path, legacy_path, data_folder, cpus, memory_mib, swap_mib, disk_size_mib, use_resource_saver, auto_pause_timeout = sys.argv[1:10]
desired = {
    "store": {
        "DataFolder": data_folder,
        "Cpus": int(cpus),
        "MemoryMiB": int(memory_mib),
        "SwapMiB": int(swap_mib),
        "DiskSizeMiB": int(disk_size_mib),
        "UseResourceSaver": use_resource_saver.lower() == "true",
        "AutoPauseTimeoutSeconds": int(auto_pause_timeout),
    },
    "legacy": {
        "dataFolder": data_folder,
        "cpus": int(cpus),
        "memoryMiB": int(memory_mib),
        "swapMiB": int(swap_mib),
        "diskSizeMiB": int(disk_size_mib),
        "useResourceSaver": use_resource_saver.lower() == "true",
        "autoPauseTimeoutSeconds": int(auto_pause_timeout),
    },
}

changed = False
updated = []
for path, style in ((store_path, "store"), (legacy_path, "legacy")):
    if not os.path.exists(path):
        continue
    with open(path) as fh:
        data = json.load(fh)

    local_changed = False
    for key, value in desired[style].items():
        if data.get(key) != value:
            data[key] = value
            local_changed = True

    if local_changed:
        with open(path, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        changed = True
        updated.append(path)

print("changed=1" if changed else "changed=0")
for path in updated:
    print(f"updated={path}")
PY
}

mac_builder_wait_for_docker() {
  local docker_bin="$1"
  local attempts="${2:-120}"
  local delay_seconds="${3:-2}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt += 1)); do
    if "$docker_bin" version >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay_seconds"
  done

  mac_builder_fail "Docker engine did not become ready in time"
}

mac_builder_current_vm_storage_errors() {
  python3 - "$MAC_BUILDER_VM_CONSOLE_LOG" "$MAC_BUILDER_BACKEND_LOG" <<'PY'
from pathlib import Path
import re
import sys

vm_log = Path(sys.argv[1])
backend_log = Path(sys.argv[2])
patterns = [
    re.compile(r"EXT4-fs .*failed to convert unwritten extents", re.I),
    re.compile(r"overlay2.*input/output error", re.I),
    re.compile(r"SIGBUS", re.I),
    re.compile(r"No space left on device", re.I),
    re.compile(r"fatal error: fault", re.I),
]

def current_session_lines(path: Path):
    if not path.exists():
        return []
    lines = path.read_text(errors="replace").splitlines()
    marker = 0
    for idx, line in enumerate(lines):
        if "Linux docker-desktop" in line:
            marker = idx
    return lines[marker:]

matches = []
for line in current_session_lines(vm_log):
    if any(pattern.search(line) for pattern in patterns):
        matches.append(line)

for line in current_session_lines(backend_log):
    if any(pattern.search(line) for pattern in patterns):
        matches.append(line)

if matches:
    for line in matches[-20:]:
        print(line)
    sys.exit(0)

sys.exit(1)
PY
}

mac_builder_run_smoke_test() {
  local cache_root="$1"
  local smoke_test_gib="$2"
  local test_file
  local count
  local stamp_file="$cache_root/.mac-builder-smoke-test.ok"

  mkdir -p "$cache_root"
  test_file="$(mktemp "${cache_root}/.mac-builder-smoke.XXXXXX")"
  count=$((smoke_test_gib * 128))

  mac_builder_log "running ${smoke_test_gib} GiB write/read smoke test on ${cache_root}"
  dd if=/dev/zero of="$test_file" bs=8m count="$count" conv=fsync status=none
  shasum -a 256 "$test_file" >/dev/null
  rm -f "$test_file"

  {
    printf 'timestamp=%s\n' "$(date -u +%FT%TZ)"
    printf 'smoke_test_gib=%s\n' "$smoke_test_gib"
  } >"$stamp_file"
  mac_builder_log "smoke test passed"
}
