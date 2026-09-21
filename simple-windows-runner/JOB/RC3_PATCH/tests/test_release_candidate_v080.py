from __future__ import annotations

import json
from pathlib import Path

import app_v067
import windows_launcher_v062


ROOT = Path(__file__).resolve().parents[1]


def test_release_candidate_manifest_matches_runtime_identity():
    manifest = json.loads((ROOT / "RELEASE_CANDIDATE.json").read_text(encoding="utf-8"))
    assert manifest["candidate_version"] == "0.8.0-ophthalmology-pack-working"
    assert manifest["candidate_label"] == "v0.8.0 RC3 SOURCE FREEZE"
    assert manifest["entrypoint"] == "app_v067.py"
    assert manifest["windows_launcher"] == "windows_launcher_v062.py"
    assert manifest["windows_runtime_key"] == "v080w"
    assert manifest["source_completion_gate"] == "python run_local_gate.py"
    assert manifest["release_pass"] is False
    assert app_v067.APP_VERSION == manifest["candidate_version"]
    assert windows_launcher_v062.APP_VERSION == manifest["candidate_version"]
    assert windows_launcher_v062._RUNTIME_KEY == manifest["windows_runtime_key"]


def test_release_candidate_manifest_keeps_external_gates_fail_closed():
    manifest = json.loads((ROOT / "RELEASE_CANDIDATE.json").read_text(encoding="utf-8"))
    pending = set(manifest["external_release_gates_pending"])
    assert "full integrated regression execution after RC3 tab UX change" in pending
    assert "Windows PyInstaller build after RC3 tab UX change" in pending
    assert "Windows runtime product gate after RC3 tab UX change" in pending
    assert "real-clinic visual touch confirmation for dedicated UKE and ChatGPT tabs" in pending
    assert "Do not call Release PASS" in manifest["release_rule"]


def test_local_gate_is_integrated_not_legacy_orca_only():
    source = (ROOT / "run_local_gate.py").read_text(encoding="utf-8")
    for token in (
        "integrated-source-completion-gate",
        "verified-orca-ui-preservation-contract",
        "same-month-director-readout-contract",
        "privacy-double-gate-contract",
        "ophthalmology-four-pillar-contract",
        "chatgpt-management-brief-contract",
        "windows-build-contract",
    ):
        assert token in source


def test_ci_and_windows_build_share_the_same_source_gate():
    ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    windows = (ROOT / ".github" / "workflows" / "windows-portable.yml").read_text(encoding="utf-8")
    assert "python run_local_gate.py" in ci
    assert "python run_local_gate.py" in windows
