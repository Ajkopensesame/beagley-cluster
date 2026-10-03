#!/usr/bin/env python3
"""Static QML checks run by CTest (qml_static_guards, qmllint_errors).

  check_qml.py guards  <repo-root>
      Fast, dependency-free source guards (see GUARDS below).
  check_qml.py qmllint <repo-root> --qmllint <path> --import-path <build-dir>
      Runs the CI Qt install's qmllint over the supported QML files and fails on
      error-level problems only (see QMLLINT_FLAGS / the baseline in the docs).

Why flags and not a .qmllint.ini: qmllint picks up a .qmllint.ini from the linted file's
directory upwards, so a repo-level ini would also silently mute the *informational*
qmllint job that Platform DevOps owns in .github/workflows/checks.yml. Keeping the
levels here (documented, CTest-only) leaves that job's output untouched.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------- file selection
# Supported = everything under src/ui that ships in the compiled module and is reachable
# from MainV3 / MainEmbedded / the widget qmldirs, i.e. all tracked *.qml minus:
EXCLUDED = {}  # rel-path -> reason. (Legacy Main/MainV2 and dead SpeedoPearl were deleted.)
EXCLUDED_PREFIXES = ()
EXCLUDED_SUFFIXES = (".bak",)


def supported_files(root: Path):
    out = []
    for p in sorted((root / "src/ui").rglob("*.qml")):
        rel = p.relative_to(root).as_posix()
        if ".bak" in rel or rel in EXCLUDED or rel.startswith(EXCLUDED_PREFIXES):
            continue
        out.append(rel)
    return out


# ---------------------------------------------------------------- guards
# Allowed import module names (value: set of allowed version spellings, "" = unversioned).
ALLOWED_IMPORTS = {
    "QtQuick": {"", "2.15"},
    "QtQuick.Window": {"", "2.15"},
    # Versioned QtQuick.Shapes (e.g. 1.15) hides Shape.preferredRendererType /
    # Shape.CurveRenderer (Qt >= 6.6): "is not available in QtQuick.Shapes 1.15" and the
    # whole component fails to load. Must stay unversioned.
    "QtQuick.Shapes": {""},
    "Qt.labs.settings": {"", "1.0"},
    "QtCore": {""},
    "BeagleY": {"1.0"},
    # Optional-feature modules, only for files that are compiled in when the feature is on.
    "QtWebEngine": {""},
    "QtLocation": {"6.5"},
    "QtPositioning": {"6.5"},
    "MapLibre": {"3.0"},
}
IMPORT_RE = re.compile(r'^\s*import\s+([A-Za-z_][\w.]*)(?:\s+([\d.]+))?(?:\s+as\s+\w+)?\s*$')

CARTO_RE = re.compile(r"basemaps\.cartocdn\.com/rastertiles|cartocdn\.com/.*(dark_all|light_all|voyager)")


def map_style_init_failures(root: Path):
    """The MapLibre plugin reads its style once, at Map creation: the style must be an INITIAL
    property of the Loader-created Impl, and the Impl must never default to the demo style."""
    out = []
    wrapper = (root / "src/ui/widgets/MapCenterMapLibreNative.qml").read_text(encoding="utf-8")
    if 'setSource("MapCenterMapLibreNativeImpl.qml", { "styleUrl": root.styleUrl })' not in wrapper:
        out.append("src/ui/widgets/MapCenterMapLibreNative.qml: the Impl Loader must pass styleUrl as an initial "
                   "property via setSource(...) (assigning it in onLoaded is too late: the Qt Location plugin has "
                   "already read its style and the map stays on the Impl default)")
    impl = (root / "src/ui/widgets/MapCenterMapLibreNativeImpl.qml").read_text(encoding="utf-8")
    if "demotiles" in impl:
        out.append("src/ui/widgets/MapCenterMapLibreNativeImpl.qml: must not default to the MapLibre demo style "
                   "(blank map); use ClusterConfig::defaultMapLibreNativeStyleUrl() / BEAGLEY_MAPLIBRE_NATIVE_DEFAULT_STYLE_URL")
    return out


def run_guards(root: Path) -> int:
    failures = []
    for rel in supported_files(root):
        for n, line in enumerate((root / rel).read_text(encoding="utf-8").splitlines(), 1):
            if not line.lstrip().startswith("import ") or '"' in line:
                continue  # relative directory / .js imports are checked by the load test
            m = IMPORT_RE.match(line.split("//")[0])
            if not m:
                failures.append(f"{rel}:{n}: unparseable import: {line.strip()}")
                continue
            mod, ver = m.group(1), m.group(2) or ""
            if mod not in ALLOWED_IMPORTS:
                failures.append(f"{rel}:{n}: import of unlisted module '{mod}' (add it to ALLOWED_IMPORTS "
                                "in tests/qml_smoke/check_qml.py only if it exists in Qt 6)")
            elif ver not in ALLOWED_IMPORTS[mod]:
                failures.append(f"{rel}:{n}: 'import {mod} {ver}' - allowed spellings: "
                                f"{sorted(ALLOWED_IMPORTS[mod]) or ['(unversioned)']}")
    # Carto's keyless raster endpoints now answer every tile with an "API KEY REQUIRED" watermark.
    for sub in ("src", "tools"):
        for p in (root / sub).rglob("*"):
            if p.is_file() and p.suffix in {".qml", ".cpp", ".h", ".js", ".sh", ".py", ".html", ".json"} \
                    and ".bak" not in p.name:
                text = p.read_text(encoding="utf-8", errors="ignore")
                for n, line in enumerate(text.splitlines(), 1):
                    if CARTO_RE.search(line):
                        failures.append(f"{p.relative_to(root)}:{n}: Carto keyless raster tiles are dead "
                                        "(API KEY REQUIRED watermark); use BEAGLEY_MAP_TILE_URL")
    for f in failures:
        print("GUARD FAIL:", f)
    print(f"qml_static_guards: {len(supported_files(root))} files checked, {len(failures)} problem(s)")
    return 1 if failures else 0


# ---------------------------------------------------------------- qmllint
# Baseline (Qt 6.6.3 qmllint over the supported files, see PR description):
#   unqualified ~515, missing-property ~466, unresolved-type ~553  -> disabled. The app injects ~35
#       context properties from main.cpp and registers its C++ types at runtime with
#       qmlRegisterType (no QML_ELEMENT), so qmllint cannot see them. Pure false-positive volume.
#   import (~45 "X was not found" for those C++ types), duplicate-property-binding (6, the benign
#       `foo: x` + `NumberAnimation on foo` idiom), incompatible-type (1) -> reported as info,
#       never fatal.
# What remains fatal: syntax errors, plus every other category at its default level
# (alias/inheritance cycles, read-only writes, bad signal-handler parameters, duplicated names,
# deprecated, required, ... all currently 0).
QMLLINT_FLAGS = [
    "--unqualified", "disable",
    "--missing-property", "disable",
    "--unresolved-type", "disable",
    "--unused-imports", "disable",
    "--import", "info",
    "--duplicate-property-binding", "info",
    "--incompatible-type", "info",
]


def run_qmllint(root: Path, qmllint: str, import_path: str) -> int:
    files = supported_files(root)
    cmd = [qmllint, "-I", import_path, *QMLLINT_FLAGS, *files]
    print("running:", " ".join(cmd[:8]), f"... ({len(files)} files)")
    proc = subprocess.run(cmd, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    # Show only what matters; info-level noise is summarised.
    shown = [l for l in proc.stdout.splitlines() if l.startswith(("Error", "Warning"))]
    infos = sum(1 for l in proc.stdout.splitlines() if l.startswith("Info"))
    for l in shown:
        print(l)
    print(f"qmllint_errors: exit={proc.returncode}, {len(shown)} warning/error line(s), {infos} info line(s)")
    if proc.returncode != 0 and not shown:
        print(proc.stdout)
    return proc.returncode


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["guards", "qmllint"])
    ap.add_argument("root")
    ap.add_argument("--qmllint")
    ap.add_argument("--import-path")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    if a.mode == "guards":
        return run_guards(root)
    return run_qmllint(root, a.qmllint, a.import_path)


if __name__ == "__main__":
    sys.exit(main())
