# Tanuki Windows Runner v0.1

Purpose: run one self-contained Windows job on Spectre and return one RESULT.zip.

This intentionally does **not** implement a factory, queue, remote feed, crypto transport,
DPAPI, scheduled tasks, retries, reboot persistence, GitHub Actions, PAT/OAuth or background service.

## Contract

Package layout:

```
RUN_JOB.cmd
RunJob.ps1
JOB/
  job.json
  <job files>
```

`job.json`:

```json
{
  "job_id": "example",
  "entrypoint": "run.cmd",
  "timeout_minutes": 60
}
```

The job may write deliverables under `_runner_output` inside its working directory.
Runner always creates:
- `RESULT.json`
- `RESULT.zip`

Status is PASS only when the child process exits 0. Product-specific acceptance remains the
job's responsibility and should be expressed by its own files in `_runner_output`.

No administrator rights are required. No network is used by the runner itself.
