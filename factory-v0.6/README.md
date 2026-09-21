# Tanuki Windows Factory v0.6

Status: **JOB contract + preflight + generic result verifier implemented; first non-Cockpit canary pending Spectre runtime evidence.**

## Frozen foundation

Factory v0.6 does not modify the runtime-qualified v0.5 runner in `simple-windows-runner/`.

v0.5 remains responsible for:

`JOB -> isolated short TEMP -> one child -> allowlisted RESULT.zip -> separate ARTIFACTS/<run-id>`

## v0.6 adds only three thin layers

1. **Reusable JOB package contract** — `JOB_PACKAGE_V1.md`
2. **Preflight before execution** — `Test-JobPackage.ps1`
3. **Generic post-run verification** — `Verify-FactoryPackageResult.ps1`

`Run-FactoryPackage.ps1` composes:

`preflight -> unchanged v0.5 RunJob.ps1 -> generic result verification`

## Product ownership

Each Tanuki owns its own package:

```text
PACKAGE.json
JOB/
  job.json
  product-specific entrypoint/payload
```

Factory owns only the transport-free execution contract and evidence boundary.

## First canary

The first non-Cockpit proof target is **Tanuki Security**, using a product-owned read-only canary. It queries Windows security surfaces but performs no scan, setting change, registry write, service change, firewall change, or outbound network request.

## Still parked

Do not add these merely because v0.6 exists:

- encrypted feed
- HMAC / DPAPI
- queue
- scheduled watcher/service
- retry/reboot persistence
- PAT/OAuth
- GitHub Actions dependency
- automatic outbound upload

A future feature must first prove it reduces Director work beyond the established one-package/one-run model.
