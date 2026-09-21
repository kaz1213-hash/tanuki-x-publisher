# RC3 direct-run follow-up

Canonical lane re-read on 2026-09-21: PR #3 remains the minimal one-job runner lane. The old encrypted-feed/HMAC/DPAPI/queue recovery is still superseded.

Current Cockpit identities:
- corrected source freeze: `33fffccf66ab66f4bf161af8f07797576a6379b7`
- corrected source tree: `2a8eda04440baec5417bdb72f4e84f3f7e7f8930`
- release-ready branch: `release-ready/v0.8.0-rc3-no-github-r2`
- release-ready head observed before this runner update: `e6b65d36b6b9a4e7c0ba25e6d16820e4cbbbd587`

Fresh Windows evidence advanced through frozen-source verification (140/140), privacy scan, exact dependency lock/wheelhouse, dependency install and integrated Streamlit AppTest. It stopped at `release-harness-preflight` only because `tests/test_release_candidate_v080.py` still asserted RC2-era external gate names while the manifest already carried RC3-specific names. This is a bounded release-test contract defect, not product runtime evidence.

The source-freeze test contract was corrected and repinned. PR #3 is now updated so the minimal runner can use either the earlier local RC3 R2 package (`70ec03...`) or the corrected package (`33fff...`). It copies the located package to isolated TEMP, applies a bounded staging-only patch for the corrected manifest/test/release adapter/bootstrap, restores the exact frozen launcher blob, verifies the corrected staged identity, then runs the existing RC3 Windows gate. The original local package is never modified.

Acceptance remains fail-closed: exact schema/candidate/frozen identity, strictly boolean Windows Candidate PASS, one PASS for every required release gate, valid final ZIP SHA and copied-artifact SHA verification are all required. Raw BUILD_RESULT details and console tails are excluded from returned diagnostics.

No Windows Candidate PASS, USER_TESTABLE_ARTIFACT_READY or Factory Completion is declared by this audit. The next real Spectre execution is intended to continue beyond the previous preflight failure into integrated regression, PyInstaller, product runtime, Japanese renamed EXE, clean re-extract runtime, privacy and final ZIP validation without asking the Director to diagnose anything.
