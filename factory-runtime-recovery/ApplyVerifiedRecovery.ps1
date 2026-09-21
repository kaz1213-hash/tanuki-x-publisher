param([string]$OutputDirectory)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='C:\TanukiFactory'
$job='clinic-cockpit-rc3-r2-20260921-001'
. (Join-Path $PSScriptRoot 'bin\RecoveryPolicy.ps1')
. (Join-Path $PSScriptRoot 'bin\FactoryRuntime.ps1')
$report=[ordered]@{schema='factory-recovery-install-v2';status='HOLD';code='STARTING';installed=$false;keys_read=$false;restart_performed=$false;runtime_verified=$false;started_utc=[DateTime]::UtcNow.ToString('o');backup_complete=$false;rollback='NOT_NEEDED'}
$stopped=$false;$replaced=$false;$backup=$null;$lock=$null;$backedUp=@();$newFiles=@()
try {
    # No mutation until the existing machine's diagnostic is eligible.
    $evidence=& (Join-Path $PSScriptRoot 'CollectFactoryEvidence.ps1') -OutputDirectory $OutputDirectory
    if($evidence.repair_decision -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'){throw $evidence.repair_decision}
    $config=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($config.factory_id -ne 'ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f'){throw 'FACTORY_ID_MISMATCH'}
    $expected=@{'TanukiFactoryWatcher.ps1'='7efb360445ed41a9b9ca353e0c5fb37be988bb947975641cb01f6eeeaf4ef63a';'TanukiFactoryCommon.ps1'='50ebb4ebcaf3c719b528f7fd1723e22b074c072ab4de57b9197195c35f79510a'}
    foreach($name in $expected.Keys){
        $p=Join-Path $root ('bin\'+$name)
        if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$name]){throw 'INSTALLED_SOURCE_DIVERGED'}
    }
    # Validate actual loopback descriptor/payload before stopping a healthy poller.
    $feed=Invoke-RestMethod -UseBasicParsing -Uri ([string]$config.feed_url) -TimeoutSec 15
    $items=@($feed.jobs|Where-Object {$_.job_id -eq $job})
    if($items.Count -ne 1 -or $items[0].target_factory_id -ne $config.factory_id){throw 'FEED_TARGET_MISMATCH'}
    $descriptor=Invoke-RestMethod -UseBasicParsing -Uri ([string]$items[0].descriptor_url) -TimeoutSec 15
    if($descriptor.target_r2_head -ne '203a2a3775dc06671de4733ec01cb9d4f503ce87' -or $descriptor.cipher_sha256 -ne $evidence.facts.cipher_sha){throw 'FEED_IDENTITY_MISMATCH'}
    $files=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'bin') -Filter '*.ps1' -File)
    $backup=Join-Path $root ('STATE\recovery-backup-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    foreach($f in $files){
        $dest=Join-Path $root ('bin\'+$f.Name)
        if(Test-Path -LiteralPath $dest){Copy-Item -LiteralPath $dest -Destination (Join-Path $backup $f.Name);$backedUp+=$f.Name}else{$newFiles+=$f.Name}
    }
    $processed=Join-Path $root 'STATE\processed.json'
    Copy-Item -LiteralPath $processed -Destination (Join-Path $backup 'processed.json')
    $report.backup_complete=$true
    Stop-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $stopped=$true
    $deadline=(Get-Date).AddSeconds(15)
    while((Get-ScheduledTask -TaskName 'TanukiWindowsFactory').State -eq 'Running'){
        if((Get-Date) -gt $deadline){throw 'WATCHER_DID_NOT_STOP'}
        Start-Sleep -Milliseconds 200
    }
    $lock=[IO.File]::Open((Join-Path $root 'STATE\watcher.lock'),'OpenOrCreate','ReadWrite','None')
    # Recheck after acquiring the single-executor lock. A race must not start a second job.
    $fresh=& (Join-Path $PSScriptRoot 'CollectFactoryEvidence.ps1') -OutputDirectory (Join-Path $OutputDirectory 'precommit')
    if($fresh.repair_decision -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'){throw 'STATE_CHANGED_BEFORE_APPLY'}
    $replaced=$true
    foreach($f in $files){
        $dest=Join-Path $root ('bin\'+$f.Name)
        Copy-Item -LiteralPath $f.FullName -Destination ($dest+'.new') -Force
        Move-Item -LiteralPath ($dest+'.new') -Destination $dest -Force
    }
    $p=Get-Content -LiteralPath $processed -Raw -Encoding UTF8|ConvertFrom-Json
    $p.PSObject.Properties.Remove($job)
    Write-FactoryJson $processed $p
    Write-FactoryJson (Join-Path $root 'STATE\retry-authorization.json') @{schema='factory-retry-authorization-v1';job_id=$job;reason='MACHINE_CONFIRMED_HMAC_PRESPAWN';retry_budget=1;utc=[DateTime]::UtcNow.ToString('o')}
    $lock.Dispose();$lock=$null
    Start-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $stopped=$false
    $report.installed=$true;$report.restart_performed=$true;$report.code='INSTALLED_AWAITING_RUNTIME'
} catch {
    $safe=@('DIAGNOSTIC_INCOMPLETE','ACTIVE_ATTEMPT_REQUIRES_RECONCILIATION','EXACT_STOP_PHASE_NOT_YET_PROVEN','FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS','CRYPTO_EVIDENCE_INCONSISTENT','EXISTING_EXECUTION_REQUIRES_RECONCILIATION','TASK_USER_DIFFERS','PROCESSED_STATE_INCONSISTENT','FACTORY_ID_MISMATCH','INSTALLED_SOURCE_DIVERGED','FEED_TARGET_MISMATCH','FEED_IDENTITY_MISMATCH','WATCHER_DID_NOT_STOP','STATE_CHANGED_BEFORE_APPLY')
    $report.code=if($_.Exception.Message -in $safe){$_.Exception.Message}else{'RECOVERY_EXCEPTION'}
    if($replaced){
        try {
            foreach($name in $backedUp){Copy-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $root ('bin\'+$name)) -Force}
            foreach($name in $newFiles){Remove-Item -LiteralPath (Join-Path $root ('bin\'+$name)) -Force -ErrorAction SilentlyContinue}
            Copy-Item -LiteralPath (Join-Path $backup 'processed.json') -Destination (Join-Path $root 'STATE\processed.json') -Force
            Remove-Item -LiteralPath (Join-Path $root 'STATE\retry-authorization.json') -Force -ErrorAction SilentlyContinue
            $report.rollback='PASS'
        } catch {$report.rollback='FAIL';$report.code='ROLLBACK_FAILED'}
    }
} finally {
    if($lock){$lock.Dispose()}
    if($stopped -and $report.rollback -ne 'FAIL'){try{Start-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop}catch{$report.code='TASK_RESTART_FAILED'}}
    # Primary receipt in the wrapper-owned fallback directory survives factory permission failures.
    Write-FactoryJson (Join-Path $OutputDirectory 'INSTALL_RESULT.json') $report
}
return [pscustomobject]$report
