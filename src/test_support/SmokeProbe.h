#pragma once

// Headless QML smoke probe (test support).
//
// Inert unless BEAGLEY_SMOKE_TEST=1 is set in the environment, so the shipped binary
// behaves identically. When enabled, the *real* beagley_cluster bootstrap (main.cpp:
// all qmlRegisterType calls, all context properties, the real backends, the real
// entry-point selection via BEAGLEY_UI_VARIANT / BEAGLEY_VEHICLE_BACKEND) runs unchanged
// and this probe observes the result instead of re-implementing the bootstrap in a
// separate harness that could drift from it. See tests/qml_smoke/README.md.
//
//   BEAGLEY_SMOKE_EXPECT   "live"     vehicle data is flowing (mock backend): telltale
//                                     hidden, gauge readouts are numbers, not "--"
//                          "linklost" source never connects: LINK LOST telltale visible,
//                                     gauge readouts are "--"
//   BEAGLEY_SMOKE_FRAMES   frames that must be swapped before judging (default 5)
//   BEAGLEY_SMOKE_MIN_MS   minimum run time before judging (default 1500)
//   BEAGLEY_SMOKE_TIMEOUT_MS  hard limit (default 30000)
//
// Exit status of the process: 0 = all assertions held, 1 = at least one failed.

class QQmlApplicationEngine;

namespace SmokeProbe {

bool enabled();

// Call first thing in main(), before QGuiApplication: starts capturing every
// qWarning/qCritical/qFatal (QML load errors, binding errors, TypeErrors, ...).
void installMessageHandler();

// Call after the entry-point QML has been loaded and before app.exec().
void start(QQmlApplicationEngine &engine);

} // namespace SmokeProbe
