# RC3 direct-run follow-up

Canonical lane re-read on 2026-09-21: PR #3 remains the minimal one-job runner lane. The old encrypted-feed/HMAC/DPAPI/queue recovery, GitHub self-hosted runner registration, and GitHub Actions are superseded for this gate.

Current Cockpit identities:
- corrected source freeze: `bf640bc9a58c3810b2d8cadde46b142054a18f3f`
- corrected source tree: `4dcd25855460d7b15ce14261e9eae79aceab54f8`
- release-ready branch: `release-ready/v0.8.0-rc3-no-github-r2`
- minimal runner job: `clinic-cockpit-rc3-minimal-run-005`

Fresh real-Windows evidence advanced through Python 3.12.10, the hardened 25-test release-runtime harness, frozen-source verification 140/140, privacy scan, exact dependency lock/wheelhouse/install/freeze, Streamlit directory-upload contract, integrated v0.8 AppTest, release-harness-preflight 6/6, ORCA foundation 117/117, UKE core 64/64, privacy/AI integration 37/37, and 44/45 UI/Windows release contracts.

The sole stop was `tests/test_windows_launcher_runtime.py::test_ready_sentinel_requires_matching_run_id`. The launcher already creates the runtime directory. The test rebound `LOCALAPPDATA` to pytest's deeply nested `tmp_path`; in the release workspace the `.ready` destination crossed legacy Windows MAX_PATH while the two-character-shorter `.tmp` path remained writable. The bounded correction keeps the same assertions but places the test under the already-isolated TEMP root with a short leaf. Product runtime source is unchanged.

PR #3 now accepts locally present RC3 packages at the original `70ec03...`, prior corrected `33fff...`, or current `bf640...` freeze. It copies the selected package to isolated TEMP and overlays the exact current manifest/test/adapter/bootstrap plus the MAX_PATH fixture correction. The original package is never modified.

Acceptance remains fail-closed: exact schema/candidate/current frozen identity, strictly boolean Windows Candidate PASS, one PASS for every required release gate, valid final ZIP SHA-256 and copied-artifact SHA verification are all required. Raw BUILD_RESULT details and console tails are excluded from returned diagnostics.

No Windows Candidate PASS, USER_TESTABLE_ARTIFACT_READY, Factory Completion or Release PASS is declared by this audit. The remaining evidence is one fresh Windows execution through the remaining UI/Windows contract, integrated source gate, PyInstaller, product runtime, Japanese renamed EXE, clean re-extract runtime, privacy and final ZIP validation.
