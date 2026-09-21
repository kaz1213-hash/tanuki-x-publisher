param([string]$Root='C:\TanukiFactory',[string]$OutputDirectory='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'bin\RecoveryPolicy.ps1')
$job='clinic-cockpit-rc3-r2-20260921-001'
$result=[ordered]@{schema='tanuki-factory-safe-diagnostic-v2';utc=[DateTime]::UtcNow.ToString('o');job_id=$job;status='HOLD';phase='UNKNOWN_AFTER_PAYLOAD_REQUEST';keys_collected=$false;medical_data_collected=$false;outbound_return_connected=$false;facts=[ordered]@{cipher_exists=$false;cipher_sha=$null;cipher_sha_matches=$false;plaintext_exists=$false;plaintext_sha=$null;plaintext_sha_matches=$false;source_exists=$false;job_manifest_exists=$false;processed_state='ABSENT';terminal_exists=$false;terminal_status='ABSENT';terminal_error_code='NONE';task_state='UNKNOWN';task_last_result=$null;task_user_matches_current_user=$false;watcher_process_count=0;work_process_count=0;process_start_logged=$false;process_end_logged=$false;remote_failure_logged=$false;result_zip_exists=$false;active_attempt_exists=$false;active_phase='NONE';active_status='NONE'};error_codes=@();repair_decision='UNCLASSIFIED'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $Root ('OUTBOX\RECOVERY\'+[Guid]::NewGuid().ToString('N'))}
function Read-SmallJson([string]$Path){
    $f=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($f.Length -gt 1MB -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe metadata file'}
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json)
}
try {
    $f=$result.facts
    $remote=Join-Path $Root ('WORK\remote_'+$job)
    $cipher=Join-Path $remote 'payload.bin';$plain=Join-Path $remote ($job+'.job.zip')
    $f.cipher_exists=Test-Path -LiteralPath $cipher -PathType Leaf
    if($f.cipher_exists){$f.cipher_sha=(Get-FileHash -LiteralPath $cipher -Algorithm SHA256).Hash.ToLowerInvariant();$f.cipher_sha_matches=$f.cipher_sha -eq '5066f4b6ebcd3f80031438b1d096f87120c9a4cbdd913c95b7295bde89bfe3f1'}
    $f.plaintext_exists=Test-Path -LiteralPath $plain -PathType Leaf
    if($f.plaintext_exists){$f.plaintext_sha=(Get-FileHash -LiteralPath $plain -Algorithm SHA256).Hash.ToLowerInvariant();$f.plaintext_sha_matches=$f.plaintext_sha -eq '433b720dcf485cd90202ed1269e900fe5272ba555be8d51ce6f0cbec4b3cf764'}
    $source=Join-Path $Root ('WORK\'+$job+'\source')
    $f.source_exists=Test-Path -LiteralPath $source -PathType Container
    $f.job_manifest_exists=Test-Path -LiteralPath (Join-Path $source 'job.json') -PathType Leaf
    $processed=Join-Path $Root 'STATE\processed.json'
    if(Test-Path -LiteralPath $processed){$p=(Read-SmallJson $processed).PSObject.Properties[$job];if($p){$f.processed_state=if($p.Value -in @('PASS','FAIL','HOLD')){[string]$p.Value}else{'OTHER'}}}
    $legacy=Join-Path $Root ('OUTBOX\'+$job+'\FACTORY_RESULT.json')
    $f.terminal_exists=Test-Path -LiteralPath $legacy -PathType Leaf
    if($f.terminal_exists){
        $r=Read-SmallJson $legacy
        if($r.job_id -ne $job -or $r.schema -ne 'tanuki-windows-factory-result-v1'){throw 'Legacy result identity mismatch'}
        $f.terminal_status=if($r.status -in @('PASS','FAIL','HOLD')){[string]$r.status}else{'OTHER'}
        if($r.PSObject.Properties['detail']){$f.terminal_error_code=Get-FactoryErrorCode ([string]$r.detail)}
    }
    $active=Join-Path $Root 'STATE\active-attempt.json'
    $f.active_attempt_exists=Test-Path -LiteralPath $active -PathType Leaf
    if($f.active_attempt_exists){
        $a=Read-SmallJson $active
        if($a.job_id -eq $job){
            if($a.status -in @('PASS','FAIL','HOLD','RUNNING')){$f.active_status=[string]$a.status}
            if($a.phase -in @('accepted','descriptor-download','payload-download','payload-download-complete','ciphertext-sha','rsa-key-access','rsa-unwrap','hmac-verify','aes-decrypt','plaintext-zip-sha','zip-expand','job-target-and-entrypoint','process-spawn','job-running','product-result-validation')){$f.active_phase=[string]$a.phase}
        }
    }
    $f.result_zip_exists=Test-Path -LiteralPath (Join-Path $Root ('OUTBOX\'+$job+'_RESULT.zip')) -PathType Leaf
} catch {$result.error_codes+='METADATA_INCOMPLETE'}
try {
    # At most two known Factory logs, 2000 trailing lines each; no raw lines leave the machine.
    $logs=@(Get-ChildItem -LiteralPath (Join-Path $Root 'LOGS') -Filter 'factory-*.log' -File -ErrorAction Stop|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 2)
    foreach($log in $logs){
        if($log.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked log rejected'}
        foreach($line in @(Get-Content -LiteralPath $log.FullName -Tail 2000 -Encoding UTF8)){
            if($line -like ('*START job='+$job+' *')){$result.facts.process_start_logged=$true}
            if($line -like ('*END job='+$job+' *')){$result.facts.process_end_logged=$true}
            if($line -like ('*REMOTE JOB FAIL job='+$job+' *')){$result.facts.remote_failure_logged=$true}
        }
    }
} catch {$result.error_codes+='LOG_EVIDENCE_UNAVAILABLE'}
try {
    $task=Get-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $result.facts.task_state=if([string]$task.State -in @('Unknown','Disabled','Queued','Ready','Running')){[string]$task.State}else{'UNKNOWN'}
    $result.facts.task_last_result=[long](Get-ScheduledTaskInfo -TaskName 'TanukiWindowsFactory' -ErrorAction Stop).LastTaskResult
    $taskOwner=[string]$task.Principal.UserId
    if($taskOwner -match '^S-1-'){$taskSid=$taskOwner}else{$account=New-Object Security.Principal.NTAccount($taskOwner);$taskSid=$account.Translate([Security.Principal.SecurityIdentifier]).Value}
    $result.facts.task_user_matches_current_user=$taskSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
} catch {$result.error_codes+='TASK_STATE_UNAVAILABLE'}
try {
    $processes=@(Get-CimInstance Win32_Process -ErrorAction Stop)
    $watcher=Join-Path $Root 'bin\TanukiFactoryWatcher.ps1'
    $workPrefix=(Join-Path $Root 'WORK')+'\'
    foreach($p in $processes){
        if(-not $p.CommandLine){continue}
        if(([string]$p.CommandLine).IndexOf($watcher,[StringComparison]::OrdinalIgnoreCase) -ge 0){$result.facts.watcher_process_count++}
        if(([string]$p.CommandLine).IndexOf($workPrefix,[StringComparison]::OrdinalIgnoreCase) -ge 0){$result.facts.work_process_count++}
    }
} catch {$result.error_codes+='PROCESS_STATE_UNAVAILABLE'}
$f=$result.facts
if($f.cipher_sha_matches){$result.phase='CIPHERTEXT_PRESENT'}
if($f.plaintext_sha_matches){$result.phase='PLAINTEXT_VERIFIED'}
if($f.source_exists){$result.phase='SOURCE_PRESENT'}
if($f.process_start_logged){$result.phase='PROCESS_START_LOGGED'}
if($f.terminal_exists){$result.phase='LEGACY_TERMINAL_PRESENT'}
if($f.active_attempt_exists){$result.phase=$f.active_phase}
$result.repair_decision=Get-FactoryRepairDecision $result
if($result.repair_decision -eq 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'){$result.phase='HMAC_CONSTRUCTOR_FAILED_BEFORE_AES'}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputDirectory 'FACTORY_DIAGNOSTIC.json') -Encoding UTF8
return [pscustomobject]$result
