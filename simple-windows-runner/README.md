# Tanuki Windows Runner v0.4

Purpose: run one self-contained Windows job on Spectre and return one `RESULT.zip` plus a separately verified final product artifact when the candidate passes.

This intentionally does **not** implement a queue, remote feed, encrypted/HMAC/DPAPI transport, scheduled tasks, retries, reboot persistence, GitHub Actions, PAT/OAuth or a background service. The reset goal is one Windows execution lane end-to-end before infrastructure.

## One-click Cockpit layout

```text
START_COCKPIT_WINDOWS.cmd
RUN_JOB.cmd
RunJob.ps1
JOB/
  job.json
  RunClinicCockpit.ps1
  CockpitAcceptance.ps1
  RC3_PATCH/
    RELEASE_CANDIDATE.json
    tests/test_release_candidate_v080.py
    tests/test_windows_launcher_runtime.py
    tools/release_v080_rc3_builder.py
    tools/release_v080_rc3_bootstrap.ps1
```

`START_COCKPIT_WINDOWS.cmd` is the only intended human entrypoint.

The Cockpit job can consume a local RC3 R2 package frozen at the original `70ec03be3de89548bf61ceea2661bffb03dab18a`, the prior corrected `33fffccf66ab66f4bf161af8f07797576a6379b7`, or the current `bf640bc9a58c3810b2d8cadde46b142054a18f3f`. It never edits that local package. Instead it copies the package to TEMP, overlays the bounded current RC3 test-contract/release-adapter patch, restores the exact frozen `START_HERE_WINDOWS.bat`, verifies the staged identity, and executes the existing hardened RC3 Windows release gate.

The latest bounded correction is test-only: the Windows launcher unit fixture now uses the already-isolated release TEMP root with a short leaf instead of pytest's deeply nested `tmp_path` as `LOCALAPPDATA`. This avoids a false failure from legacy Windows MAX_PATH while preserving the same ready-sentinel/state/privacy assertions. Product runtime source is unchanged.

## Generic job contract

The child job writes only safe evidence under `%TANUKI_RUNNER_OUT%`. Validated product ZIPs are kept separately in `ARTIFACTS/<run-id>/` via `%TANUKI_RUNNER_ARTIFACTS%`; they are not included in the returned diagnostic ZIP. The runner creates `RESULT.json` and `RESULT.zip`.

Runner PASS requires the child process to exit 0 and result collection/compression to complete. A timeout attempts to terminate the child process tree. Console tails are excluded by default.

Cockpit PASS additionally requires exact candidate/schema/current-frozen identity, strictly boolean Windows Candidate PASS, exactly one PASS for every required release gate, a valid final ZIP SHA-256, and successful copied-artifact SHA verification.

No administrator rights are required by the generic runner. The generic runner itself makes no network request. Product source/UI is not redesigned by this package.

Latest AI-side audit: see `RC3_HANDOFF_AUDIT.md`. No Windows Candidate PASS is implied until the actual Spectre run returns the required evidence.
