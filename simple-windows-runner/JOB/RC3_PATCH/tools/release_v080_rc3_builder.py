from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

import release_v080_rc2_builder as base

RC2_FROZEN_COMMIT = "1f99cff64812a05c75b3c6b17cd80acbf97bdd00"
RC3_FROZEN_COMMIT = "bf640bc9a58c3810b2d8cadde46b142054a18f3f"
RC3_FROZEN_TREE = "4dcd25855460d7b15ce14261e9eae79aceab54f8"
RC3_CANDIDATE = "v0.8.0 RC3"
RC2_HARDENED_BUILDER_BLOB = "866bf993f83a6add72f2593b579ba7f408eb8536"
RC3_FROZEN_START_HERE_BLOB = "5be7c5c73d20122bdd3226d2f65d2275c066a1bd"
RC3_CHANGED_BLOBS = {
    "RELEASE_CANDIDATE.json": ("4caeec00f80e3315f1e3421a90b3b2b1d2add9c7", 4104),
    "app_v060.py": ("5b20bc405b8367e3562b7ebc47ac6de50870b646", 31841),
    "app_v067.py": ("0b80b19bee05e5f0e0dc8369e1c234659d1de84d", 3447),
    "tests/test_app_v067_persistence.py": ("4f179dbec50d0f942ee42273798328512991a92f", 6346),
    "tests/test_release_candidate_v080.py": ("743340bcd302cfd2d67a6fe6336333265f386e09", 2442),
    "tests/test_windows_launcher_runtime.py": ("ee78ac488b7d402f870e7f48efe457169c12fb0f", 2691),
    "uke_ui.py": ("8d2ebd832736b8d92a4aecc8510f3e4699ebf1c9", 74606),
}

ROOT = Path(__file__).resolve().parents[1]
LOCALAPPDATA = Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData" / "Local"))
RC3_WORK_ROOT = LOCALAPPDATA / "TanukiReleaseBuilder" / "ClinicCockpitV080RC3"
RC3_MANIFEST_PATH = RC3_WORK_ROOT / "V080_RC3_SOURCE_BLOBS.json"
RC3_OUTPUT_DIR = ROOT / "RELEASE_OUTPUT_V080_RC3"
RC3_RESULT_PATH = RC3_OUTPUT_DIR / "BUILD_RESULT.json"
RC3_SHA_PATH = RC3_OUTPUT_DIR / "SHA256.txt"
RC3_OUTPUT_ZIP = RC3_OUTPUT_DIR / "院長レントゲン_v0.8.0_RC3_WINDOWS.zip"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def verify_rc3_adapter_contract() -> None:
    required = {
        "primary_vbs": ROOT / "START_BUILD_V080_RC3.vbs",
        "fallback_cmd": ROOT / "BUILD_V080_RC3_WINDOWS.cmd",
        "bootstrap_ps1": ROOT / "tools" / "release_v080_rc3_bootstrap.ps1",
        "adapter": ROOT / "tools" / "release_v080_rc3_builder.py",
        "base_builder": ROOT / "tools" / "release_v080_rc2_builder.py",
        "rc2_manifest": ROOT / "tools" / "V080_RC2_SOURCE_BLOBS.json",
        "legacy_rc2_vbs": ROOT / "START_BUILD_V080_RC2.vbs",
        "legacy_rc2_cmd": ROOT / "BUILD_V080_RC2_WINDOWS.cmd",
        "frozen_start_here": ROOT / "START_HERE_WINDOWS.bat",
    }
    missing = [name for name, path in required.items() if not path.is_file()]
    if missing:
        raise RuntimeError("RC3 release adapter files are missing: " + ", ".join(missing))
    for name in ("primary_vbs", "fallback_cmd", "bootstrap_ps1", "legacy_rc2_vbs", "legacy_rc2_cmd", "frozen_start_here"):
        if any(byte > 0x7F for byte in required[name].read_bytes()):
            raise RuntimeError(f"{name} must remain ASCII-only.")
    if not base.matching_blob_sha(required["base_builder"], RC2_HARDENED_BUILDER_BLOB):
        raise RuntimeError("Hardened RC2 base builder is not the exact proven blob.")
    vbs = required["primary_vbs"].read_text(encoding="ascii")
    if "WScript.ScriptFullName" not in vbs or "release_v080_rc3_bootstrap.ps1" not in vbs or "release_v080_rc2_bootstrap.ps1" in vbs:
        raise RuntimeError("RC3 primary VBS contract failed.")
    cmd = required["fallback_cmd"].read_text(encoding="ascii")
    if "release_v080_rc3_bootstrap.ps1" not in cmd or "V080_RC3" not in cmd or "release_v080_rc2_bootstrap.ps1" in cmd:
        raise RuntimeError("RC3 fallback CMD contract failed.")
    legacy_vbs = required["legacy_rc2_vbs"].read_text(encoding="ascii")
    legacy_cmd = required["legacy_rc2_cmd"].read_text(encoding="ascii")
    if "release_v080_rc3_bootstrap.ps1" not in legacy_vbs or "release_v080_rc2_bootstrap.ps1" in legacy_vbs:
        raise RuntimeError("Superseded RC2 VBS is not fail-safe routed to RC3.")
    if "release_v080_rc3_bootstrap.ps1" not in legacy_cmd or "release_v080_rc2_bootstrap.ps1" in legacy_cmd:
        raise RuntimeError("Superseded RC2 CMD is not fail-safe routed to RC3.")
    if not base.matching_blob_sha(required["frozen_start_here"], RC3_FROZEN_START_HERE_BLOB):
        raise RuntimeError("START_HERE_WINDOWS.bat no longer matches the exact RC3 frozen source blob.")
    bootstrap = required["bootstrap_ps1"].read_text(encoding="ascii")
    tokens = (
        'candidate = "v0.8.0 RC3"',
        f'frozen_commit = "{RC3_FROZEN_COMMIT}"',
        'RELEASE_OUTPUT_V080_RC3',
        'release_v080_rc3_builder.py',
        '-m py_compile',
    )
    missing_tokens = [token for token in tokens if token not in bootstrap]
    if missing_tokens:
        raise RuntimeError("RC3 bootstrap self-identification contract is incomplete: " + ", ".join(missing_tokens))
    if "release_v080_rc2_builder.py" in bootstrap:
        raise RuntimeError("RC3 bootstrap directly references the superseded RC2 builder module.")
    if RC3_OUTPUT_ZIP.name == base.OUTPUT_ZIP_NAME:
        raise RuntimeError("RC3 output ZIP must remain distinct from the inherited RC2 output ZIP.")


def prepare_rc3_manifest() -> Path:
    source_path = ROOT / "tools" / "V080_RC2_SOURCE_BLOBS.json"
    payload = json.loads(source_path.read_text(encoding="utf-8"))
    if payload.get("frozen_commit") != RC2_FROZEN_COMMIT:
        raise RuntimeError("Inherited RC2 source manifest is not the expected proven baseline.")
    blobs = payload.get("blobs")
    if not isinstance(blobs, list):
        raise RuntimeError("Inherited source manifest has no blob list.")
    by_path = {str(item.get("path") or ""): item for item in blobs}
    missing = sorted(set(RC3_CHANGED_BLOBS) - set(by_path))
    if missing:
        raise RuntimeError("RC3 delta paths are missing from inherited source manifest: " + ", ".join(missing))
    payload["schema"] = "clinic-cockpit-v080-rc3-frozen-source-blobs-v1"
    payload["candidate"] = RC3_CANDIDATE
    payload["frozen_commit"] = RC3_FROZEN_COMMIT
    payload["frozen_tree"] = RC3_FROZEN_TREE
    for path, (sha, size) in RC3_CHANGED_BLOBS.items():
        by_path[path]["sha"] = sha
        by_path[path]["size"] = size
    if int(payload.get("blob_count") or -1) != len(blobs):
        raise RuntimeError("Inherited source manifest blob count is inconsistent.")
    RC3_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    temp = RC3_MANIFEST_PATH.with_suffix(".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(RC3_MANIFEST_PATH)
    return RC3_MANIFEST_PATH


def configure_base(manifest_path: Path) -> None:
    base.FROZEN_COMMIT = RC3_FROZEN_COMMIT
    base.MANIFEST_PATH = manifest_path
    base.OUTPUT_ZIP_NAME = RC3_OUTPUT_ZIP.name
    base.OUTPUT_DIR = RC3_OUTPUT_DIR
    base.OUTPUT_ZIP = RC3_OUTPUT_ZIP
    base.RESULT_PATH = RC3_RESULT_PATH
    base.SHA_PATH = RC3_SHA_PATH
    base.WORK_ROOT = RC3_WORK_ROOT


def normalize_rc3_result_metadata() -> None:
    if not RC3_RESULT_PATH.is_file():
        raise RuntimeError("Inherited builder did not emit BUILD_RESULT.json.")
    payload = json.loads(RC3_RESULT_PATH.read_text(encoding="utf-8-sig"))
    payload["candidate"] = RC3_CANDIDATE
    payload["frozen_commit"] = RC3_FROZEN_COMMIT
    payload["release_adapter"] = {
        "candidate": RC3_CANDIDATE,
        "frozen_tree": RC3_FROZEN_TREE,
        "adapter": "tools/release_v080_rc3_builder.py",
        "base_builder": "tools/release_v080_rc2_builder.py",
        "base_builder_blob": RC2_HARDENED_BUILDER_BLOB,
        "base_lineage": "RC2 hardened release builder",
        "rc3_entrypoint": "START_BUILD_V080_RC3.vbs",
        "legacy_entrypoints_fail_safe_to_rc3": True,
    }
    temp = RC3_RESULT_PATH.with_suffix(".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(RC3_RESULT_PATH)


def write_adapter_failure(detail: str) -> None:
    RC3_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in (RC3_OUTPUT_ZIP, RC3_SHA_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    payload = {
        "schema": "clinic-cockpit-no-github-windows-release-gate-v1",
        "product": "院長レントゲン / Clinic Cockpit Lite",
        "candidate": RC3_CANDIDATE,
        "frozen_commit": RC3_FROZEN_COMMIT,
        "gate": "NO_GITHUB_WINDOWS_RELEASE_GATE",
        "status": "FAIL",
        "windows_candidate_pass": False,
        "release_pass": False,
        "director_debug_required": False,
        "github_actions_used": False,
        "failed_step": "rc3-adapter-self-contract",
        "detail": str(detail)[-2000:],
        "finished_utc": utc_now(),
    }
    RC3_RESULT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    try:
        verify_rc3_adapter_contract()
        manifest_path = prepare_rc3_manifest()
        configure_base(manifest_path)
        rc = int(base.main())
        normalize_rc3_result_metadata()
        return rc
    except Exception as exc:
        write_adapter_failure(type(exc).__name__ + ": " + str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
