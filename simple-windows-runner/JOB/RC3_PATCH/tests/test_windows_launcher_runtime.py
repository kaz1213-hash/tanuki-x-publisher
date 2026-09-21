import json
import os
import socket
from pathlib import Path

import windows_launcher as wl


def _set_short_localappdata(monkeypatch, leaf: str) -> Path:
    """Keep the Windows launcher contract test below legacy MAX_PATH.

    The release harness already isolates TEMP/TMP under its private workspace.
    Using pytest's deeply nested ``tmp_path`` as LOCALAPPDATA can push the
    ``runtime/<uuid>.ready`` target a couple of characters beyond legacy
    MAX_PATH on Windows even though the product's normal LocalAppData path is
    much shorter. That turns a launcher-contract test into a path-length test.
    """
    root = Path(os.environ.get("TEMP") or os.environ.get("TMP") or ".") / leaf
    root.mkdir(parents=True, exist_ok=True)
    monkeypatch.setenv("LOCALAPPDATA", str(root))
    return root


def test_choose_port_falls_back_when_preferred_is_busy(monkeypatch):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as held:
        held.bind(("127.0.0.1", 0))
        held.listen(1)
        busy = held.getsockname()[1]
        monkeypatch.setenv("CLINIC_COCKPIT_PORT", str(busy))

        chosen = wl._choose_port()

        assert chosen != busy
        assert 1 <= chosen <= 65535


def test_ready_sentinel_requires_matching_run_id(monkeypatch):
    _set_short_localappdata(monkeypatch, "cc-ready-test")
    run_id = "12345678-1234-5678-1234-567812345678"

    wl._write_ready(run_id)

    assert wl._ready_matches(run_id)
    assert not wl._ready_matches("87654321-4321-8765-4321-876543218765")


def test_state_contains_only_safe_runtime_metadata(monkeypatch):
    _set_short_localappdata(monkeypatch, "cc-state-test")
    wl._write_state(
        phase="RUNNING",
        run_id="12345678-1234-5678-1234-567812345678",
        port=8765,
        launcher_pid=100,
        child_pid=101,
    )

    payload = json.loads(wl._runtime_state_path().read_text(encoding="utf-8"))

    assert set(payload) == {
        "schema_version",
        "version",
        "phase",
        "run_id",
        "port",
        "launcher_pid",
        "child_pid",
        "updated_unix",
    }


def test_launcher_log_ignores_unknown_fields(monkeypatch):
    _set_short_localappdata(monkeypatch, "cc-log-test")
    wl._write_launcher_log(
        phase="FAILED",
        run_id="run",
        port=8765,
        exception_class="RuntimeError",
        patient_name="SHOULD_NOT_APPEAR",
        uploaded_filename="SHOULD_NOT_APPEAR.csv",
    )

    text = wl._launcher_log_path().read_text(encoding="utf-8")
    assert "SHOULD_NOT_APPEAR" not in text

    record = json.loads(text.strip())
    assert record["phase"] == "FAILED"
    assert record["exception_class"] == "RuntimeError"
