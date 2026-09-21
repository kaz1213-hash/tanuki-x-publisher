# Tanuki Windows Runner v0.5

Purpose: run one self-contained Windows job on Spectre, return one privacy-bounded `RESULT.zip`, and keep validated product artifacts separate under `ARTIFACTS/<run-id>/`.

This reset lane intentionally does **not** implement a queue, remote feed, encrypted/HMAC/DPAPI transport, scheduled task, retry/reboot persistence, GitHub Actions, PAT/OAuth, or a background service. First prove a small Windows execution contract end-to-end.

## Generic runner contract

The canonical job manifest schema is `tanuki-windows-runner-job-v1`.

```json
{
  "schema": "tanuki-windows-runner-job-v1",
  "job_id": "example",
  "entrypoint": "run.cmd",
  "timeout_minutes": 60,
  "include_console_tail": false,
  "safe_result_files": ["SAFE_RESULT.json"],
  "required_result_files": ["SAFE_RESULT.json"]
}
```

Rules:
- the job is copied to a short isolated TEMP path before execution;
- reparse points inside the supplied job and returned result tree are rejected;
- entrypoint paths and result paths must be safe relative paths;
- child jobs receive `TANUKI_RUNNER_OUT`, `TANUKI_RUNNER_JOB_ID`, `TANUKI_RUNNER_RUN_ID`, and `TANUKI_RUNNER_ARTIFACTS`;
- only files explicitly listed in `safe_result_files` can enter `RESULT.zip`;
- a successful child process is still failed closed when a file listed in `required_result_files` is missing;
- console tails are excluded unless the manifest explicitly opts in;
- product artifacts are never bundled into the diagnostic ZIP by the generic runner.

`RESULT.json` uses schema `tanuki-windows-runner-result-v3` and records the runner version, run id, manifest schema, child exit code, collected safe-result names, missing required-result names, and artifact count without exposing local filesystem paths.

## One-click runner self-test

Run `START_RUNNER_SELFTEST.cmd`.

The self-test is product-independent. It verifies the generic environment/output/artifact contract and intentionally writes one **unlisted** probe file into the child output directory. After the runner exits, `VerifyRunnerSelfTest.ps1` checks that:
- the runner and manifest schemas are exact;
- the child exited PASS;
- the allowlisted result is present;
- the unlisted probe is absent from `RESULT.zip`;
- the artifact exists outside the diagnostic ZIP;
- the child self-test checks are all true.

The one-click lane then creates `FACTORY_SELFTEST_RESULT.zip`. That is the only evidence package needed for Factory qualification.

This is the preferred Factory canary now that Clinic Cockpit RC3 has been completed through another product-specific route.

## Clinic Cockpit canary

`START_COCKPIT_WINDOWS.cmd` and `JOB/` remain as a historical/product canary. They are no longer the definition of the generic Factory architecture.

The Cockpit job still returns only:
- `BUILD_RESULT_SUMMARY.json`
- `COCKPIT_JOB_RESULT.json`

The generic runner does not interpret Clinic Cockpit release semantics. Product-specific acceptance stays inside the child job.

## Current Factory boundary

Build next only after the minimal runner itself has a real Windows PASS:
- no queue;
- no watcher/service;
- no encrypted feed/HMAC/DPAPI;
- no automatic outbound upload;
- no Director log reading or PowerShell debugging.

The next Factory milestone is a real Spectre PASS of the standalone runner self-test, with `FACTORY_SELFTEST_RESULT.zip` proving the allowlist contract and artifact separation.
