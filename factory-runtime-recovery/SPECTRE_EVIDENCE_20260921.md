# Spectre returned evidence, 2026-09-21

Received ZIP SHA256: `80f6611524c36b6c022ec63f06188bdad11f1a7b7baddbd265509db97a69c295`. Exactly one member: FACTORY_RESULT.json (3618 bytes).
Executed package source: PR #2 head e7ff0e89aebd12a555e9d30692c22dcb325f0565.
Run: 2026-09-21T05:32:14.3769108Z through 05:32:43.8562441Z.

## Machine-confirmed findings

- Windows PS5.1 preflight: PASS, as reported by wrapper. This is not a product runtime PASS.
- Ciphertext exists; SHA256 equals pinned 5066f4b6ebcd3f80031438b1d096f87120c9a4cbdd913c95b7295bde89bfe3f1.
- Legacy terminal FAIL: HMAC_CONSTRUCTOR_32_ARGUMENTS. Plaintext absent; source/job manifest absent; no process-start record; work-process count zero.
- processed state FAIL. No active attempt. No diagnostic collection errors. Task owner matches current user.
- Diagnostic class: HMAC_CONSTRUCTOR_FAILED_BEFORE_AES; decision ELIGIBLE_HMAC_PRESPAWN_REPAIR.
- Legacy result ZIP absent. Current recovery result ZIP returned successfully by manual upload (fallback C).
- Scheduled task Running, but watcher-process count zero: do not declare liveness PASS from task state.

The original HMAC constructor failure is now machine-confirmed by the allowlisted projection of the legacy terminal result and corroborating filesystem evidence. RSA unwrap is implied by the pinned legacy code ordering, not independently journaled. HMAC verification and AES decryption did not complete; no Cockpit build/runtime evidence exists.

## Separate recovery failure — unresolved

The installer returned HOLD / RECOVERY_EXCEPTION; installed=false, restart_performed=false, backup_complete=false, rollback=NOT_NEEDED. No active canary attempt or build summary was returned. The receipt lacks installer phase and exception classification. It cannot distinguish repeated diagnostic/config/hash/feed/descriptor/backup failures. Backup may have partially started; do not claim no files were created. Installed runtime replacement was not reached according to the receipt.

Do not ascribe this second failure to HMAC or declare a fix without evidence. No rerun is requested. No replacement package is issued from this evidence update.

## Source hardening following this receipt

ApplyVerifiedRecovery now checkpoints INSTALL_RESULT.json before each major installer phase and retains fixed exception class plus integer script line on failure. No raw message, stack, path, stdout, keys or clinical data is exported. InstallerFailure.Smoke executes the installer with disposable fixtures and injected config/feed/descriptor failures; verifies HOLD, no replacement/restart, retained phase, and privacy-safe receipt. Linux PowerShell 7 qualification only; this new revision has not executed on Spectre.

Factory Completion remains HOLD: repaired execution, product gates, reboot regression, liveness, automatic result return and queue advancement remain unverified/incomplete. Clinic Cockpit R2 remains 203a2a3775dc06671de4733ec01cb9d4f503ce87; Comic/FX remain blocked. PR remains draft and unmerged.
