Set-StrictMode -Version 2.0
function Get-FactoryErrorCode([string]$Detail) {
    if($Detail -match 'HMACSHA256' -and $Detail -match '\b32\b' -and $Detail -match '(?i)overload|argument|オーバーロード|引数'){return 'HMAC_CONSTRUCTOR_32_ARGUMENTS'}
    if($Detail -match 'Ciphertext SHA256 mismatch'){return 'CIPHER_SHA_MISMATCH'}
    if($Detail -match 'HMAC verification failed'){return 'HMAC_MISMATCH'}
    if($Detail -match 'Decrypted job ZIP SHA256 mismatch'){return 'PLAIN_SHA_MISMATCH'}
    if($Detail -match '(?i)timeout'){return 'JOB_TIMEOUT'}
    if($Detail -match 'Key not valid|指定された状態で使用するには無効'){return 'DPAPI_CONTEXT_FAILURE'}
    return 'UNCLASSIFIED_EXCEPTION'
}
function Get-FactoryRepairDecision($Evidence) {
    if($Evidence.error_codes.Count -gt 0){return 'DIAGNOSTIC_INCOMPLETE'}
    $f=$Evidence.facts
    if($f.active_attempt_exists){return 'ACTIVE_ATTEMPT_REQUIRES_RECONCILIATION'}
    if(-not $f.terminal_exists){return 'EXACT_STOP_PHASE_NOT_YET_PROVEN'}
    if($f.terminal_status -ne 'FAIL' -or $f.terminal_error_code -ne 'HMAC_CONSTRUCTOR_32_ARGUMENTS'){return 'FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS'}
    if(-not $f.cipher_sha_matches -or $f.plaintext_exists){return 'CRYPTO_EVIDENCE_INCONSISTENT'}
    if($f.source_exists -or $f.job_manifest_exists -or $f.process_start_logged -or $f.work_process_count -gt 0){return 'EXISTING_EXECUTION_REQUIRES_RECONCILIATION'}
    if(-not $f.task_user_matches_current_user){return 'TASK_USER_DIFFERS'}
    if($f.processed_state -ne 'FAIL'){return 'PROCESSED_STATE_INCONSISTENT'}
    return 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'
}
function Get-FactoryRetryEligibility($Attempt) {
    if($Attempt.status -eq 'PASS'){return 'COMPLETE_NO_RETRY'}
    if($Attempt.child_pid -or $Attempt.phase -in @('process-spawn','job-running','product-result-validation')){return 'REQUIRES_CHILD_RECONCILIATION'}
    return 'REQUIRES_VERIFIED_REPAIR'
}
