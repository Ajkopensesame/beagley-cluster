# Deploying a CI-built aarch64 binary to the BeagleY (plan only)

> **Status: PLAN. Nothing in this document has been executed.** No SSH to, and no
> change on, the board was made while writing it. Every step that changes the board
> needs ThatGuy's explicit approval (see `docs/BOARD_RUNBOOK.md`, section 1). The
> read-only checks in section 4 are the only commands meant to be run before approval
> of the swap itself.

Related: `.github/workflows/build-aarch64.yml` (the build), `docs/BOARD_RUNBOOK.md`
(access, rules), `docs/ENVIRONMENT.md` (env vars), `ARCHITECTURE.md` ("Link-lost behaviour").

---

## 1. How the binary is built and why

**Approach chosen: a native build on a GitHub-hosted ARM64 runner (`ubuntu-24.04-arm`,
free for public repos; 22.04 cannot be used because the aqtinstall Qt 6.9.1 arm64 host tools such as `moc` need glibc 2.38; 24.04 has glibc 2.39 and GCC 13, the same as the Scarthgap toolchain), run manually (`workflow_dispatch`)**, against Qt **6.9.1** from
aqtinstall (`linux_gcc_arm64`, modules `qtwebsockets qtlocation qtpositioning qtshadertools`) and
**QMapLibre 3.0.0 built from source** with the same flags and patch as
`yocto/meta-beagley-cluster/recipes-graphics/maplibre-native-qt/maplibre-native-qt_3.0.0.bb`.
The app is configured exactly like the Yocto recipe: `-DCMAKE_BUILD_TYPE=Release
-DBEAGLEY_APPLIANCE_PRODUCTION=ON -DWITH_WEBENGINE=OFF -DWITH_MAPLIBRE_NATIVE=ON`.

| Option | Verdict |
| --- | --- |
| (a) Yocto build of the whole image / recipe in CI | Rejected for CI: TI SDK 11.00 is hundreds of GB and hours; GitHub runners have ~14 GB free. **But** an *app-only* Yocto rebuild on the Elitebook (`tools/yocto/build_beagley_cluster_app.sh`, `bitbake beagley-cluster`, warm sstate) is the highest-fidelity fallback if the board checks in section 4 fail. |
| **(b) Native ARM64 runner + aqtinstall Qt + QMapLibre from source** | **Chosen.** No cross toolchain/sysroot to maintain, free, reproducible, minutes after the first run (QMapLibre is cached). |
| (c) Elitebook | Not assumed to be aarch64 (it is the x86 Yocto builder). Its Yocto app build is the fallback in row (a). |

### What this build is NOT
It is **not** compiled against the board image's sysroot. The Qt it links is the Qt
Company's 6.9.1 desktop build, the board runs the Yocto-built Qt. These are
source-compatible and normally binary-compatible within one minor series (6.9.x), but
that is an expectation, not a proof. The workflow records ABI evidence (section 3) and
section 4 lists the read-only checks that turn the expectation into a verified fact
*before* anything is swapped.

### Required versions on the board (what the binary needs)

| Component | Needed | Why / evidence |
| --- | --- | --- |
| Qt 6 (Core, Gui, Network, Qml, Quick, Svg, WebSockets, Location, Positioning) | **6.9.x with patch >= 6.9.1** | TI Processor SDK 11.00 pins `meta-qt6` branch `6.9` @ `fce7cf8c3aa5` (oe-layersetup `processor-sdk-analytics-11.00.00-config.txt`), where `QT_VERSION = "6.9.1"`. The repo's Yocto layer targets that SDK (`yocto/README.md`, `LAYERSERIES_COMPAT = "scarthgap"`). **The version actually installed on the board has not been read** (UNKNOWN until section 4). |
| libQMapLibre | **exactly 3.0.0** (`libQMapLibre.so.3`) | `find_package(QMapLibre 3.0.0 EXACT)`; Yocto recipe `maplibre-native-qt_3.0.0.bb` |
| glibc / libstdc++ | glibc <= 2.39, GLIBCXX <= 3.4.32 | Scarthgap toolchain (glibc 2.39, GCC 13.x). The workflow fails if the binary needs more. |
| Qt plugins/QML on the board | eglfs + eglfs_kms platform plugin, `geoservices/libqtgeoservices_maplibre.so`, `qml/MapLibre`, SQLite SQL driver | Same as the existing image; unchanged by this deploy |

Note: the CI build also compiles with Qt 6.9.1 although the repo's required CI gate
(`ci.yml`) uses Qt 6.6.3 on x86. The app source is therefore built against two Qt
minors; any 6.9-only warnings surface in the aarch64 workflow log.

Everything the app needs at runtime besides shared libraries is **inside the binary**:
QML, fonts (Oxanium, Orbitron), skin atlases and the web resources are Qt resources
(`qt_add_qml_module`, `qt_add_resources`, `qrc:/...`). The installed
`BeagleY/qmldir` and `.qmltypes` are tooling metadata only. There are no asset
directories to copy. The only files shipped are `beagley_cluster` (and optionally
`nowplayingctl`).

---

## 2. Running the build and fetching the artifact

```
gh workflow run build-aarch64.yml -R Ajkopensesame/beagley-cluster \
   -f ref=codex/maplibre-native-yocto-build        # (needs the workflow on the default branch)
gh run watch -R Ajkopensesame/beagley-cluster
gh run download <run-id> -R Ajkopensesame/beagley-cluster -D /workspace/artifacts
```

The artifact `beagley-aarch64-<sha12>` contains:

| File | Content |
| --- | --- |
| `beagley_cluster` | the binary (build RUNPATH removed with `patchelf`, so the board's normal loader path applies) |
| `nowplayingctl` | helper, same build |
| `BUILD_INFO.txt` | full commit hash, subject, runner, compiler, Qt and QMapLibre versions, flags, timestamp, run URL |
| `SHA256SUMS` | checksums of every file |
| `evidence/file.txt`, `readelf-header.txt`, `readelf-dynamic.txt`, `needed-libs.txt` | architecture and the exact shared libraries it needs |
| `evidence/readelf-version-info.txt`, `glibc-versions-needed.txt`, `glibcxx-versions-needed.txt`, `qt-symbol-versions-needed.txt`, `qt-private-api-symbols.txt` | symbol-version requirements |
| `evidence/abi-checks.txt` | PASS/FAIL list (aarch64, links QMapLibre + Qt6Location, no WebEngine, glibc/glibcxx ceilings) |
| `reference/libQMapLibre*.so*` | the QMapLibre this binary was linked against. **Reference only; do not deploy unless section 4 shows the board's copy is missing/wrong.** |
| `reference/beagley-cluster-launch.sh.from-repo`, `beagley-cluster.default.from-repo` | the repo's launcher and env defaults, for comparison with the board's |

Verify on the Mac before copying anything: `shasum -a 256 -c SHA256SUMS`.

---

## 3. What the board runs today (and what is unknown)

* Board binary: Sep 13 appliance build, commit `1371e7f299fd` (not present in this
  repo's history; the source it was built from is unknown), at
  `/data/beagley-cluster/runtime-drive-adaptive-1371e7f299fd/`, launched by
  `/data/beagley-cluster/runtime-hotspot-wifi-20260919/launch.sh`. Neither path is in
  the repo: the layout of those directories, what `launch.sh` exports
  (`LD_LIBRARY_PATH`? `QT_PLUGIN_PATH`? hub wait?) and how the systemd unit points at
  it are **UNKNOWN until section 4**. This plan is therefore built so that it copies
  and minimally edits the *existing* `launch.sh` rather than inventing a new one.
* The repo's `skills/beagley-deploy/scripts/deploy.sh` is **not** the way this board is
  deployed and must not be used here: it builds locally, stops the service, then
  copies the binary **to the root filesystem** (`/usr/bin/beagley_cluster`) and
  `/usr/bin/beagley-cluster-launch.sh`, deleting `/usr/bin/beagley_cluster.bak*`
  first. The root filesystem is ~95% full and the runtime lives under `/data`.
* Repo launcher `beagley-cluster-launch.sh`: sets Qt/eglfs and `BEAGLEY_*` defaults,
  runs the GPU gate, waits up to 20 s for `VEHICLE_HUB_WS_URL` (`nc`), then
  `exec /usr/bin/beagley_cluster`. The unit has `Restart=always`, `RestartSec=2`.

---

## 4. Read-only pre-flight on the board (needs approval to connect, changes nothing)

From the Mac (the only machine that reaches the board; get the IP with
`dns-sd -G v4 beagley-ai.local`):

```bash
B=root@<beagley-ip>; K="-o BatchMode=yes -o ConnectTimeout=8 -i ~/.ssh/beagley_bbb"
ssh $K $B 'bash -s' <<'EOF'
set -u
echo "== space (STOP if /data free < 3x binary size, or rootfs inodes exhausted)"; df -h / /data /var/volatile; df -i / /data
echo "== service"; systemctl is-active beagley_cluster; systemctl cat beagley_cluster --no-pager | grep -E '^(ExecStart|ExecStartPre|Environment|EnvironmentFile|WorkingDirectory|Restart|StartLimit|\[|#)'
ls /etc/systemd/system/beagley_cluster.service.d/ 2>/dev/null
echo "== runtime dirs"; ls -la /data/beagley-cluster/; du -sh /data/beagley-cluster/runtime-* 2>/dev/null
ls -la /data/beagley-cluster/runtime-drive-adaptive-1371e7f299fd/ /data/beagley-cluster/runtime-hotspot-wifi-20260919/
echo "== launch.sh (review for secrets before pasting anywhere)"; cat /data/beagley-cluster/runtime-hotspot-wifi-20260919/launch.sh
echo "== running process"; pid=$(systemctl show -p MainPID --value beagley_cluster); echo pid=$pid; readlink /proc/$pid/exe
echo "== effective env, NAMES ONLY (the values include secrets: never print/paste them)"; tr '\0' '\n' < /proc/$pid/environ | cut -d= -f1 | sort
echo "== effective env, the non-secret values this plan depends on"
tr '\0' '\n' < /proc/$pid/environ | grep -E '^(BEAGLEY_VEHICLE_BACKEND|VEHICLE_HUB_WS_URL|BEAGLEY_WIFI_ONBOARDING|BEAGLEY_WIFI_WIZARD_TRIGGER|BEAGLEY_UI_VARIANT|BEAGLEY_RENDER_PROFILE|BEAGLEY_MAP_RENDERER|QT_QPA_PLATFORM|LD_LIBRARY_PATH|QT_PLUGIN_PATH|QML2?_IMPORT_PATH)='
echo "== Qt / MapLibre / libc on the board"
ls -l /usr/lib/libQt6Core.so.6* /usr/lib/libQt6Location.so.6* /usr/lib/libQMapLibre* 2>&1
strings /usr/lib/libQt6Core.so.6 | grep -m3 -E '^6\.[0-9]+\.[0-9]+(\.|$)'
readelf -d /usr/lib/libQMapLibre.so.3 | grep -E 'SONAME|NEEDED'
ls /usr/lib/plugins/geoservices /usr/lib/qml/MapLibre 2>&1 | head
/lib/libc.so.6 2>&1 | head -1
echo "== old binary needs (for diffing against the new one)"; readelf -d /data/beagley-cluster/runtime-drive-adaptive-1371e7f299fd/beagley_cluster 2>&1 | grep -E 'NEEDED|RUNPATH|RPATH'
EOF
```

**Go / no-go criteria (all must hold):**

1. `/data` has at least **3x the binary size** free (binary + `nowplayingctl` + a copy of `launch.sh`; the old runtime dir is *not* copied). Rootfs is not written to at all in the preferred (symlink) variant. If the only switch mechanism is a systemd drop-in on rootfs, that is a ~200-byte file; confirm `df` shows free blocks *and* inodes first.
2. Board Qt is **6.9.x with patch >= 6.9.1** and `libQMapLibre.so.3` is present with a 3.0.0 build. If Qt is e.g. 6.8.x or 6.10, or the QMapLibre soname differs: **STOP** and use the Elitebook app-only Yocto build instead.
3. Board glibc is >= 2.39.
4. After staging the binary (section 5, step 2) and **before** switching:
   ```bash
   # use the exact LD_LIBRARY_PATH / QT_PLUGIN_PATH values the old launch.sh exports (if any)
   LD_TRACE_LOADED_OBJECTS=1 /data/beagley-cluster/runtime-<sha12>-linklost/beagley_cluster | grep -E 'not found|=>'
   ```
   must show **no `not found`**, and `libQt6*.so.6` / `libQMapLibre.so.3` must resolve to the same paths the old binary resolves to (run the same command on the old binary and diff). This does not start the app; it only runs the dynamic loader in trace mode.

---

## 5. Deploy (each step needs approval; do not run until ThatGuy says go)

Naming: `SHA=<first 12 chars of the built commit>`, new runtime dir
`/data/beagley-cluster/runtime-${SHA}-linklost`. The old dirs are never modified.

**Step 0 - verify on the Mac:** `gh run download`, then `shasum -a 256 -c SHA256SUMS`;
compare with the sha256 posted in the PR.

**Step 1 - rollback script on the board** (small file under `/data`, no service change; the
two variant blocks are filled in from the section-4 findings, exactly one stays):

```bash
ssh $K $B 'cat > /data/beagley-cluster/rollback-to-1371e7f.sh && chmod 0755 /data/beagley-cluster/rollback-to-1371e7f.sh' <<'SCRIPT'
#!/bin/sh
# Restores the pre-deploy runtime. Safe to run repeatedly.
set -eu
# A) systemd drop-in variant:
#    cp /data/beagley-cluster/rollback/ExecStart.dropin.orig /etc/systemd/system/beagley_cluster.service.d/<file>.conf
# B) symlink variant:
#    ln -sfn /data/beagley-cluster/runtime-hotspot-wifi-20260919 /data/beagley-cluster/current
systemctl daemon-reload
systemctl reset-failed beagley_cluster || true
systemctl restart beagley_cluster
SCRIPT
```

**Step 2 - stage the new runtime dir** (service untouched, still running the old binary):

```bash
SHA=<sha12>; NEW=/data/beagley-cluster/runtime-${SHA}-linklost; OLD=/data/beagley-cluster/runtime-hotspot-wifi-20260919
ssh $K $B "df -h /data && mkdir -p $NEW"                      # abort if free space < 3x size
scp $K beagley_cluster nowplayingctl $B:$NEW/
ssh $K $B "chmod 0755 $NEW/beagley_cluster $NEW/nowplayingctl && cd $NEW && sha256sum beagley_cluster nowplayingctl"   # must equal SHA256SUMS
# launcher: COPY the board's own launch.sh and change ONLY the runtime-dir/binary paths.
ssh $K $B "cp -p $OLD/launch.sh $NEW/launch.sh && grep -n 'runtime-\|beagley_cluster' $NEW/launch.sh"
#   edit so the only differences vs $OLD/launch.sh are those paths, then:
ssh $K $B "diff $OLD/launch.sh $NEW/launch.sh; sh -n $NEW/launch.sh"
```

Run the section-4 item-4 loader check against `$NEW/beagley_cluster`. Stop here if anything is off.
Nothing has changed for the driver at this point.

**Step 3 - arm the guard, then switch (one change):**

```bash
# auto-rollback in 3 minutes unless cancelled (transient timer lives in /run: no rootfs write)
ssh $K $B "systemd-run --unit=beagley-rollback-guard --on-active=180 /data/beagley-cluster/rollback-to-1371e7f.sh"
# A) drop-in variant: first save the original (cp <dropin> /data/beagley-cluster/rollback/ExecStart.dropin.orig),
#    then change ONLY the ExecStart path from $OLD/launch.sh to $NEW/launch.sh
# B) symlink variant: ln -sfn $NEW /data/beagley-cluster/current   (atomic)
ssh $K $B "systemctl daemon-reload && systemctl restart beagley_cluster"
```

If the unit can only be re-pointed by editing its main unit file on rootfs, stop and ask:
that is a rootfs write on a ~95% full disk.

**Step 4 - verify (section 6).** If the display is good and ThatGuy confirms:
`ssh $K $B 'systemctl stop beagley-rollback-guard.timer'` cancels the guard. If it is not
cancelled within 3 minutes, the guard rolls back by itself.

Restart conventions: `systemctl restart beagley_cluster`; if the app hangs on shutdown,
`systemctl kill -s KILL beagley_cluster` (runbook open question 7). Never `pkill -f`.

---

## 6. Verification after the swap

Read-only observation (`journalctl -u beagley_cluster -b --no-pager | tail -150`):

* `[main] BEAGLEY_VEHICLE_BACKEND = live` (the appliance build refuses `mock` anyway)
* `[UI] variant = embedded entry = MainEmbedded`
* no `is not a type`, `module "BeagleY" is not installed`, `Cannot assign`, QML errors, `SQLite driver not found`, `could not load the Qt platform plugin "eglfs"`
* hub connected (`[VehicleStateClient] connected ws://10.24.0.7:8765`)
* `systemctl is-active beagley_cluster` stays `active` for >= 2 minutes, `systemctl show -p NRestarts beagley_cluster` = 0
* Wi-Fi onboarding as before (`BEAGLEY_WIFI_ONBOARDING`, `BEAGLEY_WIFI_WIZARD_TRIGGER` same as the old env); do not touch Wi-Fi config.

On the glass:

1. Hub up: live speed/rpm/fuel/coolant, gear, no LINK LOST pill, status `LIVE`.
2. **Link-lost behaviour** (PR #23, `ARCHITECTURE.md`): unplug the hub LAN cable on the BeagleY `eth0` (no sudo and no BBB change needed), or have ThatGuy stop the hub on the BBB. Within about 1 s expect `--` for speed/rpm/fuel/coolant, greyed gauges, gear `-`, turn signals off, the amber **LINK LOST** pill, and any warning that was lit still lit (raise one, e.g. door, beforehand). Reconnect: live values return and the pill disappears.
3. Map shows tiles (online) or the expected offline fallback; fonts render (Oxanium/Orbitron, no tofu boxes).
4. Touch / Wi-Fi wizard behave as on the old binary.

---

## 7. Rollback

Fast (service alive or crash-looping), from the Mac:

```bash
ssh $K $B '/data/beagley-cluster/rollback-to-1371e7f.sh'      # Step 1 script
# equivalent, variant B:  ln -sfn /data/beagley-cluster/runtime-hotspot-wifi-20260919 /data/beagley-cluster/current && systemctl restart beagley_cluster
# equivalent, variant A:  restore the saved drop-in; systemctl daemon-reload; systemctl reset-failed beagley_cluster; systemctl restart beagley_cluster
ssh $K $B 'systemctl is-active beagley_cluster; journalctl -u beagley_cluster -n 50 --no-pager'
```

The old runtime dirs (`runtime-drive-adaptive-1371e7f299fd`, `runtime-hotspot-wifi-20260919`) are never modified, so
rollback needs no copy and no extra disk. The guard timer (Step 3) runs the same script
after 3 minutes unless cancelled. The new runtime dir is deleted only after a successful
soak and a separate approval.

If SSH is unavailable after the swap (Wi-Fi drops are a known issue): the guard still fires on the board;
otherwise power-cycle (the swap persists across reboot unless the guard fired). The serial-console /
physical recovery procedure is UNKNOWN (runbook open question 9).

---

## 8. Risks

| Risk | Mitigation |
| --- | --- |
| **Disk full** (rootfs ~95%) | Nothing is written to rootfs in the symlink variant; new files live in `/data`; space gate in section 4; no old-binary copies; do not run `deploy.sh` |
| **Qt ABI mismatch** (build is desktop-Qt 6.9.1, board is Yocto Qt) | Section 4 version check + loader trace; `abi-checks.txt`; Qt private-API imports listed; precompiled QML caches self-invalidate on a Qt version mismatch and fall back to the QML source in the binary (slower start, not a crash). Fallback: Elitebook app-only Yocto build |
| **QMapLibre mismatch** (must be exactly 3.0.0 with the same flags) | soname + version check; the reference lib in the artifact is a last resort only, and only with explicit approval (it would be loaded via `LD_LIBRARY_PATH` from `/data`) |
| **Fonts missing** | Fonts are Qt resources inside the binary; confirm visually (6.3) |
| **Env vars lost/changed** (`BEAGLEY_WIFI_ONBOARDING`, `BEAGLEY_WIFI_WIZARD_TRIGGER`, `VEHICLE_HUB_WS_URL=ws://10.24.0.7:8765`, `BEAGLEY_VEHICLE_BACKEND` must stay `live`, `BEAGLEY_UI_VARIANT`, map vars) | The new `launch.sh` is a copy of the board's own with only paths changed; compare env **names** and the non-secret values from section 4 before/after; `mock` is refused in this build; env files (`/etc/default/beagley-cluster*`, may hold secrets) are untouched and never printed |
| **Crash / boot loop** (`Restart=always`, `RestartSec=2`; systemd's default start limit can park the unit in `failed`) | 3-minute dead-man's-switch restoring the old runtime; check `NRestarts` |
| **GPU gate / eglfs** (`BEAGLEY_REQUIRE_GPU_GATE=1`) | Unchanged; the launcher runs the same gate before `exec` |
| **Source line differs from the Sep 13 binary** (commit `1371e7f299fd` is not in repo history) | The new binary is the default-branch tip: expect behavioural differences beyond link-lost (Phase 1 vehicle state, new UI, fonts). Review the PR list since Sep 13 before approving |
| **Wi-Fi** | Owned by Chief of Staff; nothing here touches wpa/networkd/watchdog |
| **Hub side** | The BBB hub is not changed by this deploy; the new cluster treats `_health.stale` as link lost, so a stale hub now shows dashes + LINK LOST instead of zeros |

## 9. Not verified / open

* Board Qt/QMapLibre/glibc versions, runtime-dir layout, `launch.sh` contents, systemd unit shape (all in section 4).
* Whether Qt 6.9.1 from aqtinstall behaves identically to the Yocto Qt on eglfs/GLES (the app code uses no `QOpenGL*` API, but the scene-graph backend differs in build configuration).
* The binary has not been executed anywhere; CI only builds and inspects it.
* The guard/rollback scripts above were never run.
