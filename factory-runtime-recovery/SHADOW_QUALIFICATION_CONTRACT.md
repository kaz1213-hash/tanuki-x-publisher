# Spectre qualification-before-mutation contract

Base PR #2 reread: 1a159029462cbd793311a17bd65bcc4aad5bf20a. This revision implements the Director's explicit change: qualify on Spectre in disposable shadow fixtures, then conditionally repair in the same launch. External Windows qualification is no longer a distribution prerequisite. No pre-execution Windows/product PASS is claimed.

## One launch

1. Unpack SHA-verified embedded package into a unique per-user directory. Verify manifest hashes and parse every packaged PS1. Start a per-session status window.
2. QUALIFYING: Windows.Qualification.ps1 requires Windows 11 client and x64 Windows PowerShell 5.1. It creates a unique TEMP shadow root; child fixtures inherit TEMP/TMP pointing there. It runs native parser, preflight, synthetic crypto/runtime tests, policy, delivery, installer failure/transaction, and qualification gate tests. Synthetic CurrentUser DPAPI and RSA material never use the installed private key. The real Tanuki task/config/bin/processed/KEYS are not modified.
3. The only scheduled task modified by qualification is its own unique TanukiQualification-GUID fixture. Register/start/Running/info/stop/cleanup and current-user SID translation must pass. Cleanup failure is HOLD. A receipt binds PASS to this run's nonce, exact manifest SHA and completion timestamp.
4. Both the controller AND ApplyVerifiedRecovery require that receipt. Missing, failed, stale, wrong-source/wrong-nonce, malformed platform booleans, incomplete tests or incomplete cleanup prohibit machine diagnosis/repair through the controller. A direct installer call also requires the receipt.
5. DIAGNOSING: current real Factory is read-only assessed. Factory ID, exact source hashes, task owner, HMAC failure/ciphertext identity, absent plaintext/source/spawn/active child/active attempt, processed FAIL, transaction and previous backup summaries are inspected. The installer rechecks the eligibility and refuses any existing transaction marker. Legacy unjournaled backups are preserved; exact live source/state checks still apply.
6. REPAIRING: record transaction, stop task, acquire executor lock, repeat diagnosis/source hashes, take unique hash-checked backup, replace files, reconcile the eligible failed job, commit, release lock, request start once, confirm task Running. Unknown post-start outcome records safe observation and HOLD; no unlocked rollback or second start.
7. RUNNING COCKPIT: existing pinned canary runner observes descriptor/payload/crypto/staging/spawn/product result phases. No exit-code-only PASS. Exact RC3 product gates and artifact digest are required.
8. Save privacy-safe FACTORY_RESULT.json before archive. Return ZIP contains that file only. Desktop/TanukiFactory_Result/RESULT.zip is selected automatically and available through the screen's button. Copy failure selects the session copy; compression failure retains/selects JSON. Detailed logs, local paths, source, private key and clinic data are not in the return ZIP. A local-only DELIVERY_LOCATION.json is excluded from the ZIP.

## AI-side distribution checks

Microsoft PowerShell 7.4.19/Linux: Runtime 24, Policy 21, Delivery 4, InstallerFailure 3, InstallerTransaction 41, QualificationGate 20, DeliveryPath 5 = 118 assertions. QualificationGate includes nine refusal cases, each also producing its one-file terminal ZIP, the valid one-repair path and direct-installer refusal. InstallerTransaction tests real installer/file/hash/lock/rollback with platform/network doubles in disposable Japanese/spaced paths. These are not Windows machine evidence.

Native parser and Windows PS5.1 syntax/commands compatibility profile are required, along with embedded ZIP/hash/manifest/BOM/CRLF/line-length audits and byte-identical repeat builds. Neither Python nor GitHub downloads nor Actions/PAT/OAuth are required on Spectre for this recovery package. The existing Cockpit build's own dependency requirements are unchanged.

## Truth boundary

Prior Spectre HMAC defect remains machine-confirmed. The old installer RECOVERY_EXCEPTION exact phase cannot be reconstructed; this revision does not invent one. Fresh Windows shadow qualification runs only when the delivered launcher executes on Spectre. If it fails, installed Factory remains unchanged and terminal evidence is returned; this is not a request for repeated Director troubleshooting.

Delivery state: READY_FOR_GUARDED_SPECTRE_SELF_QUALIFICATION. Not WINDOWS_QUALIFIED, not USER_TESTABLE_ARTIFACT_READY, not Factory Completion. Manual result bridge C remains in use; automatic return, reboot/logon evidence and queue progression remain incomplete. Comic/FX remain blocked. PR stays draft/unmerged.
