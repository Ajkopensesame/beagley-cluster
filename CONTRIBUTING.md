# Contributing

## Pull requests

- Branch off the line you are changing (`codex/maplibre-native-yocto-build` for this line; `main` is a separate, unrelated history — port changes by hand, don't merge across).
- Keep one concern per PR (docs, CI, a single feature, or a focused bugfix).
- Never push directly to a shared line; open a PR and let CI run. The **Configure + build (WITH_WEBENGINE=OFF)** job is required and must be green.
- Link related issues in the PR body.
- Do not merge your own PR without review if you are working as a team.
- Prefer documenting known debt over drive-by mega-refactors.
- When you add or remove a file in `src/ui/widgets/qmldir`, update `BEAGLEY_QML_FILES` in `CMakeLists.txt` too (the configure-time guard fails otherwise).

## Issues

Please include:

- Steps to reproduce
- Expected vs actual behavior
- Environment: `BEAGLEY_VEHICLE_BACKEND` (`mock` / `live`), Qt version, OS
- Relevant logs (hub WebSocket URL may be redacted)

## Wire protocol / hub changes

Cluster ↔ hub `vehicle_state` messages are defined by the hub repo:

- Hub: https://github.com/Ajkopensesame/vehicle-hub
- Protocol: https://github.com/Ajkopensesame/vehicle-hub/blob/main/PROTOCOL.md

Propose protocol changes there first (or in a linked issue), then update the cluster client to match. Keep `VehicleStateSource` property names stable: QML binds to them.

## Known debt (tracked — please do not “clean up” opportunistically)

- Dual assets (`assets/` vs `src/assets/`) and legacy `src/qml.qrc` not wired into the current `qt_add_*` build path
- `src/ui/web/test/` remains gitignored local scratch (not part of the build)

These are intentional follow-ups; small, well-scoped PRs that fix one of them with a plan are welcome. Large unrelated refactors are not.
