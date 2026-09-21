> Historical audit. Current distribution policy and self-qualification boundary are in SHADOW_QUALIFICATION_CONTRACT.md. The Director has authorized Spectre shadow qualification before mutation in one launch. Prior BLOCKED distribution statements below describe the earlier revision.

# Spectre one-shot compatibility and acceptance audit

Base PR #2 head reread: 52287b52f68a86cc27db801008a7c5a284f122c7 (draft/open).
Cockpit R2 reread: 203a2a3775dc06671de4733ec01cb9d4f503ce87.

## Executed AI-side

- Microsoft PowerShell 7.4.19/Linux native AST parser: all PS1 files.
- Runtime.Smoke: 24 assertions, including cryptography and strict product-result acceptance.
- RecoveryPolicy.Smoke: 21 assertions: exact EN/JA constructor error classification, missing proof, unsafe/unknown/interrupted states, survivors, previous PASS, tamper failures, retry eligibility.
- ResultDelivery.Smoke: 4 assertions: JSON, exactly one allowlisted ZIP entry, compression failure retains HOLD JSON, stale ZIP removed.
- PSScriptAnalyzer compatibility rules using Windows/.NET Framework 4.8/PowerShell 5.1 profile: no syntax or command incompatibilities.
- Type profile flags DPAPI and WinForms types as not loaded by default. Code explicitly loads System.Security and System.Windows.Forms before access; actual assembly/type/handle availability is checked by Windows.Preflight BEFORE installed code changes. These diagnostics are recorded, not counted as machine PASS.

## Automatically required on Windows before mutation

- Windows PowerShell 5.1 x64 identity.
- Hash of every packaged script; native parser for every PS1.
- Windows.Preflight: cmdlet presence; synthetic CurrentUser DPAPI roundtrip; WinForms native handle; Unicode/spaced PS1 path process launch; retained process handle and exit code; UTF16 WSH startup compatibility.
- Runtime.Smoke and RecoveryPolicy.Smoke executed under that Windows PS5.1 interpreter.
- Actual legacy HMAC 32-argument failure, exact ciphertext identity, no plaintext/source/child/spawn evidence, known FAIL processed marker, same task user.
- Installed legacy watcher/Common exact byte hashes, current feed identity, executor kernel lock, second diagnosis inside the lock.

## Limits

No Windows cloud/computer execution capability was exposed. Generic Windows qualification is NOT yet recorded as PASS. Synthetic DPAPI preflight is not access to Spectre's real Factory key. Machine-confirmed root cause must come from the collector; merely mentioning HMAC is insufficient.

No software can guarantee disk writes if all volumes are unwritable. Terminal JSON has an independent per-user recovery directory, the runtime has an emergency directory, and bootstrap has a Desktop fallback. Compression/logging failure is never used as evidence of success.

No automatic reboot is issued. The persistent controller observes the next natural restart/logon, records boot change and post-boot watcher evidence, and never reruns the installer on Resume. A surviving/interrupted job remains HOLD.

## Return route

Existing Netlify projects were reread; no enabled Forms receiver is available. No unrelated production site changed and no credentials introduced. This package uses explicitly permitted option C: one privacy-safe RESULT.zip, copied to Desktop/TanukiFactory_Result. Manual upload is NOT automatic-return PASS. Factory Completion remains false until return/queue/reboot gates are separately proven.

## Packaging

Single self-contained START_FACTORY_RECOVERY.cmd, ASCII/CRLF. Embedded ZIP is SHA256 checked before extraction. Files are expanded into a unique persistent LocalAppData directory. Paths are passed via environment variables/quoted arguments, not interpolated into source. PS1 files are UTF8 BOM/CRLF. No GitHub/Python download is required for recovery. Cockpit's own pre-existing build dependency requirements are unchanged.

## Follow-up qualification boundary

See INSTALLER_AUDIT_20260921.md. HMAC failure is now machine-confirmed in the returned Spectre receipt. Current installer hardening adds 3 failure and 41 transaction assertions on Linux PS7. A new Windows.Qualification.ps1 tests the actual native scheduled-task APIs on an AI-owned Windows guest; it has not been run. No current generic Windows PASS or Director distribution is authorized by these Linux tests.
