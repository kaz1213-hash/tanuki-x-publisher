# Spectre shadow result and source follow-up

Returned RESULT.zip SHA256: `179fabc4ffc85a0a2c449dd9f6c5d3810c26ecdc620f10908bf176ba3add52aa`.
Delivered source: `5b6530dbebe68411012b8baa9cbc72254fc6d736`.
Run: 2026-09-21T06:58:59.8187397Z to 06:59:05.1818479Z.

Machine evidence: HOLD / SHADOW_QUALIFICATION_NOT_PASS. Windows 11, PS5.1 and SID roundtrip confirmed. One test (Windows.Preflight.ps1) completed; Runtime.Smoke.ps1 did not complete. Qualification records OTHER at parent invocation line 47, not the child source line. Exact child cause is unresolved. Cleanup PASS. No machine diagnostic, installer, watcher restart or Cockpit run was reached; repair_applied=false.

The previous native child invocation merged stderr under ErrorActionPreference=Stop and failed to preserve an inner test receipt. Source now runs a worker with separate local stdout/stderr files and a fixed-field receipt (status, code, safe exception class, allowlisted source basename, line, exit code). Raw output and exception messages are not returned. Worker timeout holds qualification and preserves the shadow directory rather than deleting files under a surviving process. No actual Factory mutation is permitted without complete qualification.

Shadow and nested fixture paths are shortened while keeping Unicode/space coverage; a shadow path budget holds before testing if exceeded. Long-path failure is a hypothesis, NOT machine-confirmed. No registry changes or bypass of the qualification gate.

AI-side validation: PowerShell 7.4.19 Linux synthetic assertions 122 PASS, including worker success, typed path failure, stderr failure and nonzero exit. Parser and PS5.1 syntax/command compatibility profile checked separately. These do not establish Windows runtime PASS.

No replacement trial package is requested from Director. Existing delivered file remains unchanged. This source correction is not claimed to repair the unresolved inner Windows test failure. Factory Completion, automatic result return, reboot regression and Cockpit product acceptance remain incomplete. Manual ZIP return worked; it is not automatic return PASS. Comic/FX remain blocked. PR stays draft/open/unmerged.
