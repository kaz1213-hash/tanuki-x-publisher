# Factory recovery — staged, not installed

This change repairs source-level failure handling. It is NOT Factory Completion PASS and is NOT a Director handoff.

## Fresh canonical state

- `tanuki-x-publisher/main`: `5f17e47910b5d55d4448b8ddeb9bfb49b3a53ac1`
- `tanuki-x-publisher/factory-feed`: `3c68b254b9d7c15ce1d0759044e0f780dad8838c`
- Cockpit R2: `203a2a3775dc06671de4733ec01cb9d4f503ce87`
- Frozen RC3: `70ec03be3de89548bf61ceea2661bffb03dab18a`
- Latest returned machine evidence: v1.0.8, 2026-09-21 12:29:37 JST, real payload REQUEST only.

## Findings

1. Source-level defect reproduced using Microsoft PowerShell 7.4.19 on Linux:
   `New-Object Security.Cryptography.HMACSHA256($macKey)` with a 32-byte key fails with `Cannot find an overload for "HMACSHA256" and the argument count: "32".`
   The original common module executes this after ciphertext SHA and RSA unwrap, before HMAC/AES. The replacement constructs HMACSHA256 without arguments and assigns `.Key` explicitly. Spectre's actual exception and exact stop phase are still unobserved. This is a leading hypothesis, NOT a machine-confirmed root cause.
2. Original remote catch writes FAIL JSON but never bundles it. Original local catch only logs. Logging itself precedes remote result writing and can suppress it if logging fails.
3. Original watcher records failed jobs in `processed.json`; subsequent polls skip them. A 15-minute wait cannot repair a recorded failure.
4. Original common module treats exit code zero as PASS without verifying product results. This does not satisfy the Cockpit gate.
5. Automatic result return is explicitly absent. GitHub silence is not evidence of a Windows hang. `machine_live_heartbeat_available=true` in controller status was not justified by a returned one-time pickup record.
6. v1.0.8 supervisor serves an offline, hard-coded single-job feed. Its code does not fetch future queue jobs or return results. It cannot, by itself, automatically progress Cockpit -> Comic -> FX.

## Repair scope

- Keep existing DPAPI(CurrentUser)/RSA mechanism; never export or diagnose private key material. The normal watcher still accesses its private key locally, as before.
- Preserve HMAC-before-AES verification; require plaintext SHA.
- Persist per-attempt phase, isolated WORK and terminal scalar result before logging/compression.
- Keep historical attempts; no destructive WORK cleanup.
- Validate allowed job ID/entrypoint and ZIP containment.
- Explicitly quote paths and retain process handle/exit code.
- Emit HOLD after interrupted attempts and missing product evidence. Block subsequent jobs/retries pending reconciliation, including a possibly surviving timed-out child.
- Require current RC3 BUILD_RESULT, six exact source/runtime/privacy gate names and final artifact hash before Factory product PASS. Product Release PASS remains separate.
- Return bundle is allowlisted FACTORY_RESULT JSON only; stdout/stderr/source/medical files are not exported.
- Collector reads bounded known logs and metadata locally; emits only fixed codes/booleans/scalars. It does not read KEYS, archive source content or medical input.
- Installer is deliberately narrow: native parser and synthetic self-test, exact installed source hashes, same task owner, confirmed pre-spawn HMAC failure, no existing source directory, backup/rollback, then a single task restart. Unknown state stays HOLD. It is not yet Windows-qualified or distributed.

## Validation performed

Microsoft PowerShell 7.4.19 (Linux, not Windows 5.1):
- Actual PowerShell parser: all 6 PS1 files PASS.
- 24 synthetic runtime assertions PASS: RSA/AES/HMAC roundtrip, tampered HMAC rejection before plaintext, ciphertext/plaintext mismatch rejection, phase persistence, terminal JSON/ZIP, traversal rejection, no-result HOLD, each missing required product gate, stale result, altered ZIP, archive failure HOLD.
- Original HMAC constructor failure reproduced separately.
- Tree-sitter syntax check also passed before native runtime was made available.

None of these tests claims Spectre/DPAPI/Task Scheduler/Windows product runtime PASS.

## Exact evidence boundary: requested 24 phases

| Phase | Current Spectre evidence |
|---|---|
| 1 Download complete | Unknown; HTTP request is confirmed only |
| 2 Ciphertext SHA | Relay bundle SHA passed; watcher-side verification unknown |
| 3 RSA unwrap | Unknown |
| 4 AES decrypt | Unknown; implementation correctly authenticates HMAC first |
| 5 HMAC | Source-level constructor defect reproduced; Spectre exception unknown |
| 6 Plain ZIP SHA | Unknown |
| 7 ZIP expansion | Unknown |
| 8 Target factory | Bundled descriptor matches; inner execution unobserved |
| 9 Entrypoint | Unknown |
| 10 WORK creation | Unknown after pickup |
| 11 Process spawn | Unknown |
| 12 Local package discovery | Unknown |
| 13 R2 tooling application | Unknown |
| 14 Frozen source verification | Unknown on Spectre; GitHub frozen SHA verified |
| 15 Windows gate start | Unknown |
| 16 PyInstaller | Unknown |
| 17 Product runtime | Unknown |
| 18 Japanese EXE | Unknown |
| 19 Clean re-extract | Unknown |
| 20 Privacy | Unknown |
| 21 BUILD_RESULT | Unknown locally; none returned |
| 22 RESULT.zip | Unknown locally; none returned |
| 23 OUTBOX | Unknown after pickup |
| 24 Terminal notification | Unknown after pickup |

## Remaining blockers and next owned actions

1. Obtain privacy-safe Spectre evidence through an actual authenticated machine-to-controller path. No such callable path is exposed in this Work. Existing Netlify projects were checked: all report Forms not enabled; no unrelated site was changed. Existing runtime is local-only.
2. Run native Windows 5.1 smoke and the guarded installer using an AI-operated Windows path. No path currently available. Do not ask Director to test an unqualified repair.
3. Observe real Cockpit attempt and its exact final ZIP/runtime/privacy result. Do not infer build success from process exit or stale output.
4. Implement and prove visible liveness/terminal notification, durable authenticated result delivery, new-job transport, and queue progression. Current canary-only watcher intentionally blocks other products.
5. Prove restart/logon regression on Windows; no reboot occurred in this Work.

Director action: NONE. More than one infrastructure/physical gate remains. Do not describe a double-click as the last remaining step, or claim this work continues executing on Spectre after the chat ends.
