import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEMD_FILES = ROOT / "yocto/meta-beagley-cluster/recipes-apps/beagley-cluster/files"
SCRIPT = SYSTEMD_FILES / "beagley-touch-gate.sh"


def run_touch_gate(tmp_path: Path, *, timeout: int = 1) -> subprocess.CompletedProcess[str]:
    sys_input = tmp_path / "sys" / "class" / "input"
    dev_input = tmp_path / "dev" / "input"
    run_dir = tmp_path / "run"
    sys_input.mkdir(parents=True, exist_ok=True)
    dev_input.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env.update(
        {
            "BEAGLEY_TOUCH_SYS_CLASS_INPUT": str(sys_input),
            "BEAGLEY_TOUCH_DEV_INPUT": str(dev_input),
            "BEAGLEY_TOUCH_GATE_FILE": str(run_dir / "touch.ok"),
            "BEAGLEY_TOUCH_PROBE_STATUS_FILE": str(run_dir / "touch.status"),
            "BEAGLEY_TOUCH_PROBE_LOG_FILE": str(run_dir / "touch.log"),
        }
    )
    return subprocess.run(
        [str(SCRIPT), "--timeout", str(timeout)],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def make_event(tmp_path: Path, name: str, *, touchscreen: bool) -> None:
    event_dir = tmp_path / "sys" / "class" / "input" / "event1" / "device"
    event_dir.mkdir(parents=True)
    (event_dir / "name").write_text(name)
    if touchscreen:
        (event_dir / "uevent").write_text("ID_INPUT_TOUCHSCREEN=1\n")
    (tmp_path / "dev" / "input").mkdir(parents=True, exist_ok=True)
    (tmp_path / "dev" / "input" / "event1").write_text("")


def test_touch_gate_passes_on_touchscreen_property(tmp_path: Path) -> None:
    make_event(tmp_path, "Goodix Capacitive TouchScreen", touchscreen=True)

    result = run_touch_gate(tmp_path)

    assert result.returncode == 0, result.stdout
    assert "status=pass" in (tmp_path / "run" / "touch.ok").read_text()
    assert "Goodix Capacitive TouchScreen" in (tmp_path / "run" / "touch.status").read_text()


def test_touch_gate_fails_without_touchscreen(tmp_path: Path) -> None:
    make_event(tmp_path, "tps65219-pwrbutton", touchscreen=False)

    result = run_touch_gate(tmp_path, timeout=0)

    assert result.returncode == 1, result.stdout
    assert "status=fail" in (tmp_path / "run" / "touch.status").read_text()


def test_packaged_touch_gate_is_advisory_by_default() -> None:
    service = (SYSTEMD_FILES / "beagley_cluster.service").read_text()
    defaults = (SYSTEMD_FILES / "beagley-cluster.default").read_text()
    touch_probe = (SYSTEMD_FILES / "beagley-cluster-touch-probe.service").read_text()

    assert "Environment=XDG_CONFIG_HOME=/root/.config" in service
    assert "BEAGLEY_REQUIRE_TOUCH_GATE=0" in defaults
    assert "Environment=BEAGLEY_REQUIRE_TOUCH_GATE=0" in service

    unit_lines = [
        line
        for line in service.splitlines()
        if line.startswith(("After=", "Wants="))
    ]
    assert all("beagley-cluster-touch-probe.service" not in line for line in unit_lines)
    assert "Before=beagley_cluster.service" not in touch_probe
