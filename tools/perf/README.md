# Embedded Perf Harness

These helpers exercise the embedded production scene with recorded
`vehicle_state` frames and validate the `[Perf]` output emitted by the app.
They are the deterministic acceptance path for the final appliance FPS target,
after the board has already passed the GPU proof stage.

## Replay file format

JSON Lines. Each line can be either:

```json
{"type":"vehicle_state", ...}
```

or:

```json
{"delayMs":16,"frame":{"type":"vehicle_state", ...}}
```

The optional `delayMs` controls the pause before the next frame.

## Run a replay

```bash
tools/perf/run_embedded_replay.sh /path/to/replay.jsonl /tmp/beagley_embedded_perf.log
```

## Check a perf log

```bash
tools/perf/check_perf_log.sh /tmp/beagley_embedded_perf.log \
  --min-fps 58 \
  --max-p95 17 \
  --max-p99 25
```

For the BeagleY appliance contract, keep the replay file fixed across runs and
raise `--min-fps` to the final 60 FPS target once hardware rendering is proven.

## Premium 720 Matrix

The real-display acceptance path for the premium 1920x720 cluster profile is:

```bash
tools/perf/run_premium_720_matrix.sh \
  --host root@beagley-ai.local \
  --duration 45 \
  --warmup 15
```

The matrix installs the named `premium-720` profile, tests `basic` and
`threaded` render loops across controlled effect levels, captures `[Perf]`
logs, runs the frame-time checker, and captures real display screenshots.

Static embedded-rendering risk scan:

```bash
tools/perf/qml_render_risk_scan.sh
```

See `docs/premium_720_display_plan.md` for the long-term display contract and
thresholds.
