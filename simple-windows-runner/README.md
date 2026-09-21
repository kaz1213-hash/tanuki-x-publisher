# Tanuki Windows Runner v0.5

Purpose: run one self-contained Windows job on Spectre, return one privacy-bounded `RESULT.zip`, and keep validated product artifacts separate under `ARTIFACTS/<run-id>/`.

This reset lane intentionally does **not** implement a queue, remote feed, encrypted/HMAC/DPAPI transport, scheduled task, retry/reboot persistence, GitHub Actions, PAT/OAuth, or a background service.

## Runtime status

Generic runner v0.5 is **Spectre runtime-qualified**.

Real Windows self-test evidence:
- result schema: `tanuki-windows-runner-result-v3`
- runner version: `0.5`
- manifest schema: `tanuki-windows-runner-job-v1`
- child status: PASS
- exit code: 0
- safe result collected exactly: `SELFTEST_RESULT.json`
- required result missing: none
- artifact count: 1
- unlisted probe absent from `RESULT.zip`
- child self-test checks: all PASS

The returned diagnostic ZIP contained only `RESULT.json` and `output/SELFTEST_RESULT.json`, proving the allowlist boundary while the separately written artifact was counted outside the diagnostic package.

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

## Running a real job

Place a `JOB/` directory beside `RunJob.ps1` using the manifest contract above, then use `RUN_JOB.cmd`.

The generic runner owns process isolation, timeout, safe result collection, evidence packaging, and artifact separation. Product-specific build/runtime acceptance stays inside the child job.

## Current Factory boundary

The minimal runner is now runtime-qualified. The next development stage may add reusable job-package conventions and additional product canaries, but still does **not** justify reintroducing:
- encrypted remote feed;
- HMAC/DPAPI transport;
- queue;
- scheduled watcher/service;
- retry/reboot persistence;
- automatic outbound upload.

Those remain separate future decisions, not prerequisites for using the runner.
