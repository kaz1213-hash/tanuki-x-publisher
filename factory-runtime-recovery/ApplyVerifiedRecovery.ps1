param([string]$OutputDirectory,[string]$QualificationReceipt,[string]$QualificationNonce)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='C:\TanukiFactory'
$job='clinic-cockpit-rc3-r2-20260921-001'
$report=[ordered]@{schema='factory-recovery-install-v2';status='HOLD';code='STARTING';installed=$false;keys_read=$false;restart_performed=$false;runtime_verified=$false;started_utc=[DateTime]::UtcNow.ToString('o');backup_complete=$false;rollback='NOT_NEEDED';phase='INITIALIZING';exception_class='NONE';exception_line=0;phase_state='START';events=@();backup_files_copied=0;processed_backup_complete=$false;receipt_storage='PRIMARY';restart_attempted=$false;transaction_state='NONE';start_observation=[ordered]@{complete=$false;task_state='UNVERIFIED';active_attempt_exists=$false;work_process_count=0}}
$stopped=$false;$replaced=$false;$backup=$null;$lock=$null;$backedUp=@();$newFiles=@()
$receiptId=[Guid]::NewGuid().ToString('N')
function Save-InstallReceipt {
    # Self-contained: helper loading and ordinary logging cannot block this receipt.
    $destinations=@($OutputDirectory,(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('TanukiFactoryRecovery\emergency\'+$receiptId)),(Join-Path $PSScriptRoot ('recovery-receipt-'+$receiptId)))
    for($i=0;$i -lt $destinations.Count;$i++){
        try {
            if(-not $destinations[$i]){continue}
            $report.receipt_storage=if($i -eq 0){'PRIMARY'}else{'FALLBACK'}
            [void][IO.Directory]::CreateDirectory($destinations[$i])
            $json=$report|ConvertTo-Json -Depth 16
            foreach($name in @('FACTORY_RECOVERY_INSTALL_RESULT.json','INSTALL_RESULT.json')){
                $path=Join-Path $destinations[$i] $name
                $temp=$path+'.tmp'
                [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($true)))
                Move-Item -LiteralPath $temp -Destination $path -Force -ErrorAction Stop
            }
            return $true
        } catch {}
    }
    return $false
}
function Set-InstallPhase([string]$Phase,[string]$State='START'){
    $report.phase=$Phase;$report.phase_state=$State
    $report.events+=@{phase=$Phase;state=$State;utc=[DateTime]::UtcNow.ToString('o')}
    if(-not (Save-InstallReceipt)){throw 'INSTALL_RECEIPT_STORAGE_FAILED'}
    if($report.receipt_storage -ne 'PRIMARY'){throw 'INSTALL_PRIMARY_RECEIPT_UNAVAILABLE'}
}
$transaction=Join-Path $root 'STATE\recovery-transaction.json'
$startAttempted=$false
try {
    Set-InstallPhase 'HELPER_LOAD'
    . (Join-Path $PSScriptRoot 'bin\RecoveryPolicy.ps1')
    . (Join-Path $PSScriptRoot 'bin\FactoryRuntime.ps1')
    Set-InstallPhase 'HELPER_LOAD' 'COMPLETE'
    Set-InstallPhase 'SHADOW_QUALIFICATION_GATE'
    . (Join-Path $PSScriptRoot 'bin\QualificationPolicy.ps1')
    $qualification=Assert-FactoryQualification $QualificationReceipt $QualificationNonce (Join-Path $PSScriptRoot 'PACKAGE_MANIFEST.json')
    Set-InstallPhase 'SHADOW_QUALIFICATION_GATE' 'COMPLETE'
    Set-InstallPhase 'DIAGNOSTIC'
    # No mutation until the existing machine's diagnostic is eligible.
    $evidence=& (Join-Path $PSScriptRoot 'CollectFactoryEvidence.ps1') -OutputDirectory $OutputDirectory
    if($evidence.repair_decision -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'){throw $evidence.repair_decision}
    Set-InstallPhase 'DIAGNOSTIC' 'COMPLETE'
    Set-InstallPhase 'CONFIG_READ'
    $config=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($config.factory_id -ne 'ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f'){throw 'FACTORY_ID_MISMATCH'}
    Set-InstallPhase 'CONFIG_READ' 'COMPLETE'
    Set-InstallPhase 'PRIOR_TRANSACTION_CHECK'
    if(Test-Path -LiteralPath $transaction){throw 'PRIOR_RECOVERY_REQUIRES_RECONCILIATION'}
    Set-InstallPhase 'PRIOR_TRANSACTION_CHECK' 'COMPLETE'
    Set-InstallPhase 'INSTALLED_HASH_CHECK'
    $expected=@{'TanukiFactoryWatcher.ps1'='7efb360445ed41a9b9ca353e0c5fb37be988bb947975641cb01f6eeeaf4ef63a';'TanukiFactoryCommon.ps1'='50ebb4ebcaf3c719b528f7fd1723e22b074c072ab4de57b9197195c35f79510a'}
    foreach($name in $expected.Keys){
        $p=Join-Path $root ('bin\'+$name)
        if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$name]){throw 'INSTALLED_SOURCE_DIVERGED'}
    }
    Set-InstallPhase 'INSTALLED_HASH_CHECK' 'COMPLETE'
    # Validate actual loopback descriptor/payload before stopping a healthy poller.
    Set-InstallPhase 'FEED_DOWNLOAD'
    $feed=Invoke-RestMethod -UseBasicParsing -Uri ([string]$config.feed_url) -TimeoutSec 15
    Set-InstallPhase 'FEED_DOWNLOAD' 'COMPLETE'
    Set-InstallPhase 'FEED_TARGET_CHECK'
    $items=@($feed.jobs|Where-Object {$_.job_id -eq $job})
    if($items.Count -ne 1 -or $items[0].target_factory_id -ne $config.factory_id){throw 'FEED_TARGET_MISMATCH'}
    Set-InstallPhase 'FEED_TARGET_CHECK' 'COMPLETE'
    Set-InstallPhase 'DESCRIPTOR_DOWNLOAD'
    $descriptor=Invoke-RestMethod -UseBasicParsing -Uri ([string]$items[0].descriptor_url) -TimeoutSec 15
    Set-InstallPhase 'DESCRIPTOR_DOWNLOAD' 'COMPLETE'
    Set-InstallPhase 'DESCRIPTOR_IDENTITY_CHECK'
    if($descriptor.target_r2_head -ne '203a2a3775dc06671de4733ec01cb9d4f503ce87' -or $descriptor.cipher_sha256 -ne $evidence.facts.cipher_sha){throw 'FEED_IDENTITY_MISMATCH'}
    Set-InstallPhase 'DESCRIPTOR_IDENTITY_CHECK' 'COMPLETE'
    Write-FactoryJson $transaction @{schema='factory-recovery-transaction-v1';state='PREPARING';mutation_started=$false}
    $report.transaction_state='PREPARING'
    Set-InstallPhase 'WATCHER_STOP'
    Stop-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $stopped=$true
    $deadline=(Get-Date).AddSeconds(15)
    while((Get-ScheduledTask -TaskName 'TanukiWindowsFactory').State -eq 'Running'){
        if((Get-Date) -gt $deadline){throw 'WATCHER_DID_NOT_STOP'}
        Start-Sleep -Milliseconds 200
    }
    Set-InstallPhase 'WATCHER_STOP' 'COMPLETE'
    Set-InstallPhase 'WATCHER_LOCK'
    $lock=[IO.File]::Open((Join-Path $root 'STATE\watcher.lock'),'OpenOrCreate','ReadWrite','None')
    Set-InstallPhase 'WATCHER_LOCK' 'COMPLETE'
    # Recheck after acquiring the single-executor lock. A race must not start a second job.
    Set-InstallPhase 'LOCKED_DIAGNOSTIC'
    $fresh=& (Join-Path $PSScriptRoot 'CollectFactoryEvidence.ps1') -OutputDirectory (Join-Path $OutputDirectory 'precommit')
    if($fresh.repair_decision -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'){throw 'STATE_CHANGED_BEFORE_APPLY'}
    Set-InstallPhase 'LOCKED_DIAGNOSTIC' 'COMPLETE'
    # Verify the exact installed sources again under lock before taking backup.
    foreach($name in $expected.Keys){
        if((Get-FileHash -LiteralPath (Join-Path $root ('bin\'+$name)) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$name]){throw 'INSTALLED_SOURCE_DIVERGED'}
    }
    Set-InstallPhase 'BACKUP_CREATE'
    $files=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'bin') -Filter '*.ps1' -File)
    $backup=Join-Path $root ('STATE\recovery-backup-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    Set-InstallPhase 'BACKUP_CREATE' 'COMPLETE'
    Set-InstallPhase 'BACKUP_WATCHERS'
    foreach($f in $files){
        $dest=Join-Path $root ('bin\'+$f.Name)
        if(Test-Path -LiteralPath $dest){Copy-Item -LiteralPath $dest -Destination (Join-Path $backup $f.Name);if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $backup $f.Name) -Algorithm SHA256).Hash){throw 'BACKUP_HASH_MISMATCH'};$backedUp+=$f.Name;$report.backup_files_copied++;$filePhase=switch($f.Name){'TanukiFactoryWatcher.ps1' {'WATCHER_BACKUP'};'TanukiFactoryCommon.ps1' {'COMMON_BACKUP'};default {'HELPER_BACKUP'}};Set-InstallPhase $filePhase 'COMPLETE'}else{$newFiles+=$f.Name}
    }
    Set-InstallPhase 'BACKUP_WATCHERS' 'COMPLETE'
    Set-InstallPhase 'BACKUP_PROCESSED'
    $processed=Join-Path $root 'STATE\processed.json'
    Copy-Item -LiteralPath $processed -Destination (Join-Path $backup 'processed.json')
    if((Get-FileHash -LiteralPath $processed -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $backup 'processed.json') -Algorithm SHA256).Hash){throw 'BACKUP_HASH_MISMATCH'}
    $report.processed_backup_complete=$true
    Set-InstallPhase 'BACKUP_PROCESSED' 'COMPLETE'
    $report.backup_complete=$true
    Set-InstallPhase 'BACKUP' 'COMPLETE'
    Write-FactoryJson $transaction @{schema='factory-recovery-transaction-v1';state='REPLACING';mutation_started=$true}
    $report.transaction_state='REPLACING'
    Set-InstallPhase 'BIN_REPLACEMENT'
    $replaced=$true
    foreach($f in $files){
        $dest=Join-Path $root ('bin\'+$f.Name)
        Copy-Item -LiteralPath $f.FullName -Destination ($dest+'.new') -Force
        Move-Item -LiteralPath ($dest+'.new') -Destination $dest -Force
        $filePhase=switch($f.Name){'TanukiFactoryWatcher.ps1' {'WATCHER_REPLACED'};'TanukiFactoryCommon.ps1' {'COMMON_REPLACED'};default {'HELPER_REPLACED'}}
        Set-InstallPhase $filePhase 'COMPLETE'
    }
    Set-InstallPhase 'BIN_REPLACEMENT' 'COMPLETE'
    Set-InstallPhase 'RETRY_STATE_UPDATE'
    $p=Get-Content -LiteralPath $processed -Raw -Encoding UTF8|ConvertFrom-Json
    $p.PSObject.Properties.Remove($job)
    Write-FactoryJson $processed $p
    Write-FactoryJson (Join-Path $root 'STATE\retry-authorization.json') @{schema='factory-retry-authorization-v1';job_id=$job;reason='MACHINE_CONFIRMED_HMAC_PRESPAWN';retry_budget=1;utc=[DateTime]::UtcNow.ToString('o')}
    Set-InstallPhase 'RETRY_STATE_UPDATE' 'COMPLETE'
    Write-FactoryJson $transaction @{schema='factory-recovery-transaction-v1';state='COMMITTED';mutation_started=$true}
    $report.transaction_state='COMMITTED'
    $report.installed=$true
    $lock.Dispose();$lock=$null
    Set-InstallPhase 'WATCHER_RESTART'
    $startAttempted=$true;$report.restart_attempted=$true
    Start-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $stopped=$false
    $report.restart_performed=$true
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    while((Get-ScheduledTask -TaskName 'TanukiWindowsFactory').State -ne 'Running'){
        if([DateTime]::UtcNow -gt $deadline){throw 'START_OUTCOME_REQUIRES_RECONCILIATION'}
        Start-Sleep -Milliseconds 200
    }
    $report.start_observation.task_state='Running'
    $report.code='INSTALLED_AWAITING_RUNTIME'
    Set-InstallPhase 'WATCHER_RESTART' 'COMPLETE'
} catch {
    # Fixed class and script line only: never export exception messages or paths.
    $cause=$_.Exception
    for($depth=0;$null -ne $cause -and $depth -lt 8;$depth++){
    $type=$cause.GetType().FullName
    $report.exception_class=switch($type){
        'System.Management.Automation.PropertyNotFoundException' {'MISSING_PROPERTY'}
        'System.Management.Automation.ParameterBindingException' {'PARAMETER_BINDING'}
        'System.UnauthorizedAccessException' {'ACCESS_DENIED'}
        'System.IO.IOException' {'IO_ERROR'}
        'System.Net.WebException' {'HTTP_ERROR'}
        default {'OTHER'}
    }
    if($report.exception_class -ne 'OTHER'){break}
    $cause=$cause.InnerException
    }
    $report.exception_line=[int]$_.InvocationInfo.ScriptLineNumber
    $safe=@('SHADOW_QUALIFICATION_REQUIRED','SHADOW_QUALIFICATION_INVALID','SHADOW_QUALIFICATION_NOT_PASS','SHADOW_QUALIFICATION_SOURCE_MISMATCH','SHADOW_QUALIFICATION_STALE','INSTALL_RECEIPT_STORAGE_FAILED','INSTALL_PRIMARY_RECEIPT_UNAVAILABLE','PRIOR_RECOVERY_REQUIRES_RECONCILIATION','BACKUP_HASH_MISMATCH','DIAGNOSTIC_INCOMPLETE','ACTIVE_ATTEMPT_REQUIRES_RECONCILIATION','EXACT_STOP_PHASE_NOT_YET_PROVEN','FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS','CRYPTO_EVIDENCE_INCONSISTENT','EXISTING_EXECUTION_REQUIRES_RECONCILIATION','TASK_USER_DIFFERS','PROCESSED_STATE_INCONSISTENT','FACTORY_ID_MISMATCH','INSTALLED_SOURCE_DIVERGED','FEED_TARGET_MISMATCH','FEED_IDENTITY_MISMATCH','WATCHER_DID_NOT_STOP','STATE_CHANGED_BEFORE_APPLY')
    $report.code=if($_.Exception.Message -in $safe){$_.Exception.Message}else{'RECOVERY_EXCEPTION'}
    if($startAttempted){
        try{
            $state=[string](Get-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop).State
            $report.start_observation.task_state=if($state -in @('Running','Ready','Disabled','Queued','Unknown')){$state}else{'OTHER'}
            $report.start_observation.active_attempt_exists=Test-Path -LiteralPath (Join-Path $root 'STATE\active-attempt.json')
            $prefix=(Join-Path $root 'WORK')+'\'
            foreach($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)){
                if($process.CommandLine -and ([string]$process.CommandLine).IndexOf($prefix,[StringComparison]::OrdinalIgnoreCase) -ge 0){$report.start_observation.work_process_count++}
            }
            $report.start_observation.complete=$true
        }catch{}
    }
    # Once the lock is released, a watcher may already have spawned a child.
    # Never roll back binaries or retry task start across that uncertain boundary.
    if($replaced -and $null -eq $lock){$report.code='START_OUTCOME_REQUIRES_RECONCILIATION'}
    if($replaced -and $null -ne $lock){
        try {
            foreach($name in $backedUp){Copy-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $root ('bin\'+$name)) -Force}
            foreach($name in $newFiles){Remove-Item -LiteralPath (Join-Path $root ('bin\'+$name)) -Force -ErrorAction SilentlyContinue}
            Copy-Item -LiteralPath (Join-Path $backup 'processed.json') -Destination (Join-Path $root 'STATE\processed.json') -Force
            Remove-Item -LiteralPath (Join-Path $root 'STATE\retry-authorization.json') -Force -ErrorAction SilentlyContinue
            $report.rollback='PASS';$report.installed=$false
            Write-FactoryJson $transaction @{schema='factory-recovery-transaction-v1';state='ROLLED_BACK';mutation_started=$true}
            $report.transaction_state='ROLLED_BACK'
        } catch {$report.rollback='FAIL';$report.code='ROLLBACK_FAILED'}
    }
} finally {
    if($null -ne $lock){try{$lock.Dispose()}catch{$report.code='LOCK_RELEASE_FAILED'}}
    if($stopped -and -not $startAttempted -and $report.rollback -ne 'FAIL'){
        try{Start-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop;$report.restart_performed=$true}catch{$report.code='TASK_RESTART_FAILED'}
    }
    # Keep the actual failed phase; terminal is an event, not a replacement phase.
    $report.events+=@{phase='TERMINAL_RESULT';state='COMPLETE';utc=[DateTime]::UtcNow.ToString('o')}
    if(-not (Save-InstallReceipt)){$report.code='INSTALL_RECEIPT_STORAGE_FAILED';$report.receipt_storage='FAILED'}
}
return [pscustomobject]$report
