# Staged recovery. Not approved for Director handoff until Windows/return gates pass.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='C:\TanukiFactory'
$job='clinic-cockpit-rc3-r2-20260921-001'
$report=[ordered]@{schema='factory-recovery-install-v1';status='HOLD';code='STARTING';installed=$false;keys_read=$false;restart_performed=$false;runtime_verified=$false}
$backups=@();$stopped=$false;$replaced=$false
try {
    & (Join-Path $PSScriptRoot 'CollectFactoryEvidence.ps1')
    # Mandatory native parser + synthetic crypto/result checks before any task mutation.
    foreach($path in @(Get-ChildItem (Join-Path $PSScriptRoot 'bin') -Filter '*.ps1' -File)){
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)
        if($errors.Count -gt 0){throw 'PARSER_REJECTED'}
    }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests\Runtime.Smoke.ps1')
    if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_RUNTIME_TEST_FAILED'}
    # Never replace an unknown/custom installed watcher.
    $expected=@{'TanukiFactoryWatcher.ps1'='7efb360445ed41a9b9ca353e0c5fb37be988bb947975641cb01f6eeeaf4ef63a';'TanukiFactoryCommon.ps1'='50ebb4ebcaf3c719b528f7fd1723e22b074c072ab4de57b9197195c35f79510a'}
    foreach($name in $expected.Keys){
        $p=Join-Path $root ('bin\'+$name)
        if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$name]){throw 'INSTALLED_SOURCE_DIVERGED'}
    }
    $config=Get-Content (Join-Path $root 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($config.factory_id -ne 'ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f'){throw 'FACTORY_ID_MISMATCH'}
    $task=Get-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $owner=New-Object Security.Principal.NTAccount([string]$task.Principal.UserId)
    if($owner.Translate([Security.Principal.SecurityIdentifier]).Value -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'TASK_USER_DIFFERS'}
    $resultPath=Join-Path $root ('OUTBOX\'+$job+'\FACTORY_RESULT.json')
    if(-not (Test-Path -LiteralPath $resultPath)){throw 'EXACT_STOP_PHASE_NOT_YET_PROVEN'}
    $prior=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json
    # Only the bounded pre-spawn constructor failure is eligible for automatic retry.
    if($prior.status -ne 'FAIL' -or -not $prior.PSObject.Properties['detail'] -or [string]$prior.detail -notmatch 'HMACSHA256'){throw 'FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS'}
    $source=Join-Path $root ('WORK\'+$job+'\source')
    if(Test-Path -LiteralPath $source){throw 'EXISTING_EXECUTION_REQUIRES_RECONCILIATION'}
    if(Test-Path -LiteralPath (Join-Path $root 'STATE\active-attempt.json')){throw 'V2_ATTEMPT_ALREADY_EXISTS'}
    $backup=Join-Path $root ('STATE\recovery-backup-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup|Out-Null
    foreach($name in $expected.Keys){Copy-Item -LiteralPath (Join-Path $root ('bin\'+$name)) -Destination (Join-Path $backup $name)}
    $processed=Join-Path $root 'STATE\processed.json'
    Copy-Item -LiteralPath $processed -Destination (Join-Path $backup 'processed.json')
    Stop-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $stopped=$true
    $deadline=(Get-Date).AddSeconds(15)
    while((Get-ScheduledTask -TaskName 'TanukiWindowsFactory').State -eq 'Running'){
        if((Get-Date) -gt $deadline){throw 'WATCHER_DID_NOT_STOP'}
        Start-Sleep -Milliseconds 200
    }
    # Reuse the actual kernel file lock; never delete a possibly live lock file.
    $lock=[IO.File]::Open((Join-Path $root 'STATE\watcher.lock'),'OpenOrCreate','ReadWrite','None')
    try {
        $replaced=$true
        foreach($f in @(Get-ChildItem (Join-Path $PSScriptRoot 'bin') -Filter '*.ps1' -File)){
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $root ('bin\'+$f.Name)) -Force
        }
        $p=Get-Content -LiteralPath $processed -Raw -Encoding UTF8|ConvertFrom-Json
        $p.PSObject.Properties.Remove($job)
        $p|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $processed -Encoding UTF8
    } finally {$lock.Dispose()}
    Start-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
    $stopped=$false
    $report.installed=$true;$report.restart_performed=$true;$report.code='INSTALLED_AWAITING_RUNTIME';$report.status='HOLD'
} catch {
    $safe=@('PARSER_REJECTED','SYNTHETIC_RUNTIME_TEST_FAILED','INSTALLED_SOURCE_DIVERGED','FACTORY_ID_MISMATCH','TASK_USER_DIFFERS','EXACT_STOP_PHASE_NOT_YET_PROVEN','FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS','EXISTING_EXECUTION_REQUIRES_RECONCILIATION','V2_ATTEMPT_ALREADY_EXISTS','WATCHER_DID_NOT_STOP')
    $report.code=if($_.Exception.Message -in $safe){$_.Exception.Message}else{'RECOVERY_EXCEPTION'}
    if($replaced){
        try {
            foreach($name in $expected.Keys){Copy-Item (Join-Path $backup $name) (Join-Path $root ('bin\'+$name)) -Force}
            Copy-Item (Join-Path $backup 'processed.json') (Join-Path $root 'STATE\processed.json') -Force
            # Extra runtime helper is inert with the restored original watcher.
        } catch {$report.code='ROLLBACK_FAILED'}
    }
} finally {
    if($stopped){try{Start-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop}catch{$report.code='TASK_RESTART_FAILED'}}
    $out=Join-Path $root 'OUTBOX\FACTORY_RECOVERY_INSTALL_RESULT.json'
    New-Item -ItemType Directory -Path (Split-Path $out -Parent) -Force|Out-Null
    $report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
}
