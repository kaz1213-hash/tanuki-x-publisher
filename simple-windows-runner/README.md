# Tanuki Windows Runner v0.2

Purpose: run one self-contained Windows job on Spectre and return one `RESULT.zip`.

This intentionally does **not** implement a factory, queue, remote feed, crypto transport,
DPAPI, scheduled tasks, retries, reboot persistence, GitHub Actions, PAT/OAuth or background service.
The reset goal is to prove one Windows execution lane end-to-end before adding infrastructure.

## One-click Cockpit package layout

```text
START_COCKPIT_WINDOWS.cmd
RUN_JOB.cmd
RunJob.ps1
JOB/
  job.json
  RunClinicCockpit.ps1
```

`START_COCKPIT_WINDOWS.cmd` is the only intended human entrypoint for the Cockpit canary.
`RUN_JOB.cmd` invokes the generic runner and selects the terminal `RESULT.zip` in Explorer.
There is no final keypress/pause requirement.

## Generic job contract

`job.json` example:

```json
{
  "job_id": "example",
  "entrypoint": "run.cmd",
  "timeout_minutes": 60,
  "include_console_tail": false
}
```

The child job writes deliverables under `%TANUKI_RUNNER_OUT%`.
The runner creates:
- `RESULT.json`
- `RESULT.zip`

Runner PASS requires the child process to exit 0 **and** result collection/compression to complete.
A timeout attempts to terminate the child process tree. Console tails are excluded by default so
product wrappers can return their own privacy-safe structured diagnostics instead of raw local paths.

Product-specific acceptance remains the job's responsibility. The Clinic Cockpit wrapper accepts
PASS only after its existing RC3 release gate reports exact frozen-source, integrated-source,
Windows runtime, renamed Japanese EXE, clean re-extract runtime, privacy, and final ZIP evidence.

No administrator rights are required by the generic runner. The generic runner itself makes no
network request.
