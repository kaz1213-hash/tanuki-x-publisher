# Tanuki Windows Factory JOB Package v1

Factory v0.6 standardizes product handoffs without changing the runtime-qualified v0.5 runner.

## Layout

```text
<package-root>/
  PACKAGE.json
  JOB/
    job.json
    <entrypoint>
    <payload...>
```

The generic runner still reads only `JOB/job.json`. `PACKAGE.json` is the preflight/provenance envelope.

## PACKAGE.json

Required fields:

```json
{
  "schema": "tanuki-windows-job-package-v1",
  "package_id": "tanuki-product-canary-v1",
  "product": "Tanuki Product",
  "package_version": "1.0",
  "risk_class": "read-only",
  "director_operations_required": 0,
  "job_directory": "JOB",
  "source": {
    "repository": "owner/repository",
    "ref": "immutable-or-reviewed-ref"
  }
}
```

Rules:

- `schema` is exactly `tanuki-windows-job-package-v1`.
- `package_id` uses the same safe token grammar as the runner job id and must equal `JOB/job.json.job_id`.
- `job_directory` is exactly `JOB`.
- `director_operations_required` is exactly `0`; the Director never debugs inside a JOB.
- `risk_class` is one of `read-only`, `local-build`, or `local-write`.
- `source.repository` and `source.ref` record provenance. The package may embed its payload; the generic runner does not fetch source.
- reparse points/symlinks are rejected.
- package-produced diagnostic files must be explicitly allowlisted by `JOB/job.json.safe_result_files`.
- at least one safe result and one required result are mandatory for Factory evidence.
- `include_console_tail` must be explicitly `false` in v1 packages.
- product artifacts go only to `%TANUKI_RUNNER_ARTIFACTS%`; they do not enter `RESULT.zip`.

## JOB/job.json

The existing runtime-qualified runner schema remains unchanged:

```json
{
  "schema": "tanuki-windows-runner-job-v1",
  "job_id": "tanuki-product-canary-v1",
  "entrypoint": "run.ps1",
  "timeout_minutes": 30,
  "include_console_tail": false,
  "safe_result_files": ["PRODUCT_RESULT.json"],
  "required_result_files": ["PRODUCT_RESULT.json"]
}
```

Supported entrypoints: `.ps1`, `.cmd`, `.bat`, `.vbs`, `.exe`.

## Required workflow

1. Product team creates the package from this contract.
2. AI/package builder runs `Test-JobPackage.ps1`.
3. Only a PASS package is handed to Spectre.
4. Handoff launcher runs the same preflight again, then invokes the unchanged v0.5 runner.
5. Spectre returns `RESULT.zip`; product artifacts remain separate.

No encrypted feed, HMAC, DPAPI, queue, scheduled watcher, service, PAT, or GitHub Actions are part of this contract.
