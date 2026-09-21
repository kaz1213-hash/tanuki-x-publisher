Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\bin\RecoveryPolicy.ps1')
$count=0
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:count++}
function Baseline {
    return [pscustomobject]@{error_codes=@();facts=[pscustomobject]@{active_attempt_exists=$false;terminal_exists=$true;terminal_status='FAIL';terminal_error_code='HMAC_CONSTRUCTOR_32_ARGUMENTS';cipher_sha_matches=$true;plaintext_exists=$false;source_exists=$false;job_manifest_exists=$false;process_start_logged=$false;work_process_count=0;task_user_matches_current_user=$true;processed_state='FAIL'}}
}
$e=Baseline
Check ((Get-FactoryRepairDecision $e) -eq 'ELIGIBLE_HMAC_PRESPAWN_REPAIR') 'Known pre-spawn failure rejected'
Check ((Get-FactoryErrorCode 'Cannot find an overload for HMACSHA256 and argument count: 32') -eq 'HMAC_CONSTRUCTOR_32_ARGUMENTS') 'English constructor classification failed'
Check ((Get-FactoryErrorCode 'HMACSHA256 と引数の数 32 のオーバーロードが見つかりません') -eq 'HMAC_CONSTRUCTOR_32_ARGUMENTS') 'Japanese constructor classification failed'
Check ((Get-FactoryErrorCode 'HMACSHA256 provider error') -ne 'HMAC_CONSTRUCTOR_32_ARGUMENTS') 'Broad HMAC mention authorized repair'
Check ((Get-FactoryErrorCode 'Encrypted job HMAC verification failed.') -eq 'HMAC_MISMATCH') 'Tampering misclassified'
foreach($name in @('active_attempt_exists','plaintext_exists','source_exists','job_manifest_exists','process_start_logged')){
    $e=Baseline;$e.facts.$name=$true
    Check ((Get-FactoryRepairDecision $e) -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR') ('Unsafe state accepted: '+$name)
}
foreach($name in @('terminal_exists','cipher_sha_matches','task_user_matches_current_user')){
    $e=Baseline;$e.facts.$name=$false
    Check ((Get-FactoryRepairDecision $e) -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR') ('Missing proof accepted: '+$name)
}
$e=Baseline;$e.facts.work_process_count=1
Check ((Get-FactoryRepairDecision $e) -eq 'EXISTING_EXECUTION_REQUIRES_RECONCILIATION') 'Survivor ignored'
$e=Baseline;$e.error_codes=@('PROCESS_STATE_UNAVAILABLE')
Check ((Get-FactoryRepairDecision $e) -eq 'DIAGNOSTIC_INCOMPLETE') 'Incomplete collector authorized repair'
$e=Baseline;$e.facts.processed_state='PASS'
Check ((Get-FactoryRepairDecision $e) -eq 'PROCESSED_STATE_INCONSISTENT') 'Prior PASS retried'
$e=Baseline;$e.facts.terminal_error_code='HMAC_MISMATCH'
Check ((Get-FactoryRepairDecision $e) -eq 'FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS') 'HMAC tamper repair authorized'
Check ((Get-FactoryRetryEligibility @{status='HOLD';child_pid=123;phase='job-running'}) -eq 'REQUIRES_CHILD_RECONCILIATION') 'Child hold retryable'
Check ((Get-FactoryRetryEligibility @{status='HOLD';child_pid=$null;phase='process-spawn'}) -eq 'REQUIRES_CHILD_RECONCILIATION') 'Ambiguous spawn retryable'
Check ((Get-FactoryRetryEligibility @{status='FAIL';child_pid=$null;phase='hmac-verify'}) -eq 'REQUIRES_VERIFIED_REPAIR') 'Failure permanently processed'
Check ((Get-FactoryRetryEligibility @{status='PASS';child_pid=123;phase='product-result-validation'}) -eq 'COMPLETE_NO_RETRY') 'PASS retryable'
Write-Output ('POLICY_PASS='+$count)
