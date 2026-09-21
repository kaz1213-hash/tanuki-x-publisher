# Installer follow-up audit — release blocked

Canonical PR #2 head reread: a09d8f55430c3a2e34386f3c190327c96c729d99, open/draft. Cockpit R2 remains 203a2a3775dc06671de4733ec01cb9d4f503ce87. Prior Spectre HMAC evidence is accepted, not re-investigated.

## What the old receipt can and cannot establish

The receipt shows the wrapper's Windows preflight and first diagnostic completed. The installer returned its own initialized receipt, so its top-level helper imports completed. backup_complete=false excludes its Stop-ScheduledTask, kernel lock, replacement, processed removal and Start-ScheduledTask: they occur after that field becomes true in the executed e7ff0e89 revision. The reported RECOVERY_EXCEPTION is not one of its explicitly classified policy/hash/identity mismatch codes.

Remaining unclassified paths: repeat collector's final receipt write/output failure; config read/parse or missing property; missing/unreadable installed script during hash calculation; feed/descriptor HTTP or missing properties; listing package bin; creating unique backup directory; file or processed backup copying. Task/SID/legacy-result failures inside the collector normally become DIAGNOSTIC_INCOMPLETE, not RECOVERY_EXCEPTION. These are exclusions from code ordering, not reconstructed machine traces. The uploaded receipt cannot identify one remaining path. Neither source hardening nor injected failures retrospectively establishes the Spectre installer root cause.

## Concrete source defects closed

1. Backup was taken while the watcher could still write state. It is now taken after task stop, actual exclusive executor lock, repeat diagnosis and repeat exact source hash verification. Backup copies have digest checks and count/phase checkpoints, including processed.json.
2. Start-ScheduledTask can throw after a start request has taken effect. The old catch could roll back after releasing the executor lock, then retry start. New code treats post-release failures as START_OUTCOME_REQUIRES_RECONCILIATION; no unlocked rollback and no duplicate start.
3. Uncaught receipt writing inside finally could erase installer evidence. Receipt writing is now self-contained before helper loading, tries primary/per-user/package-local destinations, and returns the same safe report to the wrapper. Primary receipt failure prevents mutation. Storage exhaustion of all destinations remains physically unresolvable by software.
4. Partial transaction reruns had no explicit barrier. STATE/recovery-transaction.json now records PREPARING, REPLACING, COMMITTED or ROLLED_BACK. Any existing marker blocks reapplication pending reconciliation. Old unjournaled backup directories are preserved; new backups use unique names. This deliberately does not auto-retry unknown partial state.
5. The wrapper now requires installed=true AND INSTALLED_AWAITING_RUNTIME before canary observation. Applied files with ambiguous task start do not imply a successful recovery.
6. Status UI now has a result-file button; termination selects the actual existing session ZIP (JSON fallback) in Explorer. It no longer relies on a user finding a similarly named Desktop folder. Exact local paths are not included in the returned ZIP.

## Checks and remaining blocker

Linux / Microsoft PowerShell 7.4.19: Runtime 24, Policy 21, Delivery 4, InstallerFailure 3, InstallerTransaction 41 assertions PASS. Installer transaction fixtures use real installer/JSON/copy/hash/lock/rollback on Japanese/spaced paths. Task, network and legacy digest identity are controlled doubles; these are NOT Windows Task Scheduler qualification.

Windows.Qualification.ps1 is prepared for an AI-owned disposable Windows 11 / PS5.1 x64 guest. It rejects Linux/non-5.1, binds evidence to package-manifest SHA, runs the complete fixture suite, tests actual identity SID translation and a uniquely named scheduled task's register/start/Running/info/stop/cleanup. It never touches the installed Tanuki task or keys. It has NOT executed on Windows.

BLOCKER: this Work exposes a Linux executor, no Windows/cloud-computer tool, and no local KVM device. No connected Windows guest with AI execution/result access is available. Prior Spectre preflight PASS applies to the previously run package, not this revision. Fresh generic Windows qualification and the original installer exception's exact cause therefore remain unresolved.

Ending condition B applies. Build output is internal qualification material only, marked BLOCKED_PENDING_WINDOWS_QUALIFICATION. Do not issue another Director trial package, merge PR #2, or declare canary/Factory PASS. The next required evidence is a real Windows qualification receipt for the exact current manifest, followed by the already-authorized guarded Spectre flow. Manual result ZIP bridge C remains permitted; automatic result return, reboot regression and queue progression remain incomplete. Comic/FX stay blocked.
