param([switch]$Resume,[string]$SessionDirectory='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='C:\TanukiFactory'
$script:ExportResultsToDesktop=$true
$script:RunState=[ordered]@{schema='factory-one-shot-result-v1';status='RUNNING';code='PREFLIGHT';started_utc=[DateTime]::UtcNow.ToString('o');finished_utc=$null;repair_applied=$false;windows_ps51_preflight='UNVERIFIED';spectre_runtime='UNVERIFIED';automatic_result_return=$false;return_mode='MANUAL_SINGLE_ZIP';factory_completion_pass=$false;product_release_pass=$false;reboot_observed=$false;watcher_after_reboot='UNVERIFIED';diagnostic=$null;install=$null;attempt=$null;build_summary=$null;phase='INITIALIZING';phase_state='START';phase_events=@();exception_class='NONE';exception_line=0}
$script:RunDirectory=$SessionDirectory
$runLock=$null
function Save-RunResult([string]$Status,[string]$Code) {
    $script:RunState.status=$Status;$script:RunState.code=$Code
    if($Status -ne 'RUNNING'){$script:RunState.finished_utc=[DateTime]::UtcNow.ToString('o')}
    $path=Join-Path $script:RunDirectory 'FACTORY_RESULT.json'
    $script:RunState|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $path -Encoding UTF8
    if($Status -ne 'RUNNING'){
        $resultZip=Join-Path $script:RunDirectory 'RESULT.zip'
        Remove-Item -LiteralPath $resultZip -Force -ErrorAction SilentlyContinue
        try {Compress-Archive -LiteralPath $path -DestinationPath $resultZip -Force} catch {
            Remove-Item -LiteralPath $resultZip -Force -ErrorAction SilentlyContinue
            $script:RunState.status='HOLD';$script:RunState.code='RESULT_COMPRESSION_FAILED_JSON_RETAINED'
            $script:RunState|ConvertTo-Json -Depth 14|Set-Content -LiteralPath $path -Encoding UTF8
        }
        # Export only the allowlisted result, never raw logs or product/clinic files.
        try {
            if(-not $script:ExportResultsToDesktop){return}
            $desktop=[Environment]::GetFolderPath('Desktop')
            $ready=Join-Path $desktop 'TanukiFactory_Result'
            New-Item -ItemType Directory -Path $ready -Force|Out-Null
            $stamp=([DateTime]::Parse($script:RunState.started_utc)).ToString('yyyyMMdd-HHmmss')
            $zip=Join-Path $script:RunDirectory 'RESULT.zip'
            if(Test-Path -LiteralPath $zip){Copy-Item -LiteralPath $zip -Destination (Join-Path $ready ('FACTORY_RESULT_'+$stamp+'.zip')) -Force}
            else{Copy-Item -LiteralPath $path -Destination (Join-Path $ready ('FACTORY_RESULT_'+$stamp+'.json')) -Force}
        } catch {}
    }
}
function Set-RecoveryPhase([string]$Phase,[string]$State='START'){
    $script:RunState.phase=$Phase;$script:RunState.phase_state=$State
    $script:RunState.phase_events+=@{phase=$Phase;state=$State;utc=[DateTime]::UtcNow.ToString('o')}
    Save-RunResult 'RUNNING' $Phase
}
function Get-SafeAttempt($a) {
    $safe=[ordered]@{}
    foreach($k in @('job_id','attempt_id','phase','previous_phase','status','started_utc','updated_utc','exit_code','error_code','product_gate','retry_eligibility','target_r2_head')){
        $p=$a.PSObject.Properties[$k]
        if(-not $p){continue}
        if($k -eq 'exit_code'){if($null -ne $p.Value){$safe[$k]=[int]$p.Value};continue}
        $v=[string]$p.Value
        if($v.Length -le 128 -and $v -match '^[a-zA-Z0-9_:.+T -]*$'){$safe[$k]=$v}
    }
    return $safe
}
try {
    if(-not $script:RunDirectory){
        $base=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TanukiFactoryRecovery\runs'
        $script:RunDirectory=Join-Path $base ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:RunDirectory -Force|Out-Null
    }
    # Shared recovery mutex is separate from the executor's kernel file lock.
    $mutex=New-Object Threading.Mutex($false,'Local\TanukiFactoryOneShotV2')
    if(-not $mutex.WaitOne(0)){Save-RunResult 'HOLD' 'RECOVERY_ALREADY_RUNNING';exit 2}
    $runLock=$mutex
    if($Resume){
        $prior=Join-Path $script:RunDirectory 'FACTORY_RESULT.json'
        if(Test-Path -LiteralPath $prior){
            $old=Get-Content -LiteralPath $prior -Raw -Encoding UTF8|ConvertFrom-Json
            foreach($k in @($script:RunState.Keys)){if($old.PSObject.Properties[$k]){$script:RunState[$k]=$old.$k}}
        }
    } else {Save-RunResult 'RUNNING' 'PREFLIGHT'}
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or -not [Environment]::Is64BitProcess){throw 'WINDOWS_PS51_X64_REQUIRED'}
    Set-RecoveryPhase 'PACKAGE_VERIFY'
    # Parse EVERY executable PS1 and verify each byte hash before executing helpers.
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PACKAGE_MANIFEST.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($item in $manifest.files){
        if([string]$item.path -match '(^|[\\/])\.\.([\\/]|$)|:' -or [IO.Path]::IsPathRooted([string]$item.path)){throw 'PACKAGE_PATH_INVALID'}
        $path=Join-Path $PSScriptRoot ([string]$item.path)
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256){throw 'PACKAGE_HASH_MISMATCH'}
        if([IO.Path]::GetExtension($path) -eq '.ps1'){
            $tokens=$null;$errors=$null
            [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
            if($errors.Count){throw 'WINDOWS_PARSER_REJECTED'}
        }
    }
    Set-RecoveryPhase 'PACKAGE_VERIFY' 'COMPLETE'
    if(-not $Resume){
        Set-RecoveryPhase 'WINDOWS_PREFLIGHT'
        & $ps -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests\Windows.Preflight.ps1') *> (Join-Path $script:RunDirectory 'windows-preflight-local.log')
        if($LASTEXITCODE -ne 0){throw 'WINDOWS_SYNTHETIC_RUNTIME_FAILED'}
        & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests\Runtime.Smoke.ps1') *> (Join-Path $script:RunDirectory 'native-smoke-local.log')
        if($LASTEXITCODE -ne 0){throw 'WINDOWS_SYNTHETIC_RUNTIME_FAILED'}
        & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests\RecoveryPolicy.Smoke.ps1') *> (Join-Path $script:RunDirectory 'native-policy-local.log')
        if($LASTEXITCODE -ne 0){throw 'WINDOWS_SYNTHETIC_RUNTIME_FAILED'}
        foreach($fixtureTest in @('InstallerFailure.Smoke.ps1','InstallerTransaction.Smoke.ps1','ResultDelivery.Smoke.ps1')){
            & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot ('tests\'+$fixtureTest)) *> (Join-Path $script:RunDirectory ($fixtureTest+'.local.log'))
            if($LASTEXITCODE -ne 0){throw 'WINDOWS_SYNTHETIC_RUNTIME_FAILED'}
        }
        $script:RunState.windows_ps51_preflight='PASS'
        Set-RecoveryPhase 'WINDOWS_PREFLIGHT' 'COMPLETE'
    }
    $statusScript=Join-Path $PSScriptRoot 'bin\FactoryStatus.ps1'
    $arguments='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$statusScript+'" -SessionDirectory "'+$script:RunDirectory+'"'
    Start-Process -FilePath $ps -ArgumentList $arguments -WindowStyle Hidden|Out-Null
    if(-not $Resume){
        Set-RecoveryPhase 'MACHINE_DIAGNOSTIC'
        $evidence=& (Join-Path $PSScriptRoot 'CollectFactoryEvidence.ps1') -OutputDirectory $script:RunDirectory
        $script:RunState.diagnostic=$evidence
        Set-RecoveryPhase 'MACHINE_DIAGNOSTIC' 'COMPLETE'
        if($evidence.repair_decision -ne 'ELIGIBLE_HMAC_PRESPAWN_REPAIR'){throw $evidence.repair_decision}
        Set-RecoveryPhase 'INSTALLER'
        $install=& (Join-Path $PSScriptRoot 'ApplyVerifiedRecovery.ps1') -OutputDirectory $script:RunDirectory
        $script:RunState.install=$install
        $script:RunState.repair_applied=$install.installed
        if(-not $install.installed -or $install.code -ne 'INSTALLED_AWAITING_RUNTIME'){throw ([string]$install.code)}
        Set-RecoveryPhase 'INSTALLER' 'COMPLETE'
        # Persist controller for next natural restart/logon; never force-reboot the user's PC.
        $boot=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
        @{boot_utc=$boot;directory=$script:RunDirectory;started_utc=$script:RunState.started_utc}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'STATE\recovery-session.json') -Encoding UTF8
        $startup=[Environment]::GetFolderPath('Startup')
        $vbs=Join-Path $startup 'TanukiFactoryRecoveryStatus.vbs'
        $command='"'+$ps+'" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $PSScriptRoot 'RunRecovery.ps1')+'" -Resume -SessionDirectory "'+$script:RunDirectory+'"'
        $vbsText='CreateObject("WScript.Shell").Run "'+$command.Replace('"','""')+'", 0, False'
        [IO.File]::WriteAllText($vbs,$vbsText,[Text.Encoding]::Unicode)
    } else {
        $session=Get-Content -LiteralPath (Join-Path $root 'STATE\recovery-session.json') -Raw -Encoding UTF8|ConvertFrom-Json
        $boot=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime()
        $script:RunState.reboot_observed=$boot -gt [DateTime]::Parse([string]$session.boot_utc).ToUniversalTime()
    }
    Set-RecoveryPhase 'CANARY_OBSERVE'
    $deadline=[DateTime]::UtcNow.AddMinutes(135)
    $pickupDeadline=[DateTime]::UtcNow.AddMinutes(3)
    $activePath=Join-Path $root 'STATE\active-attempt.json'
    while([DateTime]::UtcNow -lt $deadline){
        if(Test-Path -LiteralPath $activePath){
            $a=Get-Content -LiteralPath $activePath -Raw -Encoding UTF8|ConvertFrom-Json
            if($a.job_id -ne 'clinic-cockpit-rc3-r2-20260921-001'){throw 'UNEXPECTED_ACTIVE_JOB'}
            $script:RunState.attempt=Get-SafeAttempt $a
            if($a.status -in @('PASS','FAIL','HOLD')){
                if($script:RunState.reboot_observed){
                    $h=Get-Content -LiteralPath (Join-Path $root 'STATE\watcher-heartbeat.json') -Raw -Encoding UTF8|ConvertFrom-Json
                    if([DateTime]::Parse([string]$h.utc).ToUniversalTime() -gt $boot){$script:RunState.watcher_after_reboot='OBSERVED'}
                }
                if($a.status -eq 'PASS'){
                    $summary=Get-Content -LiteralPath (Join-Path $root 'STATE\cockpit-build-summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
                    if($summary.final_zip_sha256 -notmatch '^[0-9a-f]{64}$' -or $summary.target_r2_head -ne '203a2a3775dc06671de4733ec01cb9d4f503ce87'){throw 'BUILD_SUMMARY_INVALID'}
                    $script:RunState.build_summary=@{status='PASS';candidate='v0.8.0 RC3';final_zip_sha256=[string]$summary.final_zip_sha256;target_r2_head='203a2a3775dc06671de4733ec01cb9d4f503ce87'}
                    $script:RunState.spectre_runtime='WINDOWS_CANDIDATE_PASS'
                    Save-RunResult 'PASS' 'CANARY_PASS_FACTORY_COMPLETION_PENDING'
                } else {Save-RunResult ([string]$a.status) 'CANARY_NOT_PASS'}
                break
            }
        } elseif([DateTime]::UtcNow -gt $pickupDeadline){throw 'NO_NEW_ATTEMPT_AFTER_RESTART'}
        $heartbeatPath=Join-Path $root 'STATE\watcher-heartbeat.json'
        if(Test-Path -LiteralPath $heartbeatPath){
            $heartbeat=Get-Content -LiteralPath $heartbeatPath -Raw -Encoding UTF8|ConvertFrom-Json
            if(([DateTime]::UtcNow-[DateTime]::Parse([string]$heartbeat.utc).ToUniversalTime()).TotalSeconds -gt 180){throw 'WATCHER_HEARTBEAT_STALE'}
        }
        Start-Sleep -Seconds 2
    }
    if($script:RunState.status -eq 'RUNNING'){throw 'OBSERVATION_TIMEOUT_QUEUE_BLOCKED'}
} catch {
    $script:RunState.exception_line=[int]$_.InvocationInfo.ScriptLineNumber
    $script:RunState.exception_class=if($_.Exception -is [IO.IOException]){'IO_ERROR'}elseif($_.Exception -is [UnauthorizedAccessException]){'ACCESS_DENIED'}else{'OTHER'}
    $codes=@('INSTALL_RECEIPT_STORAGE_FAILED','INSTALL_PRIMARY_RECEIPT_UNAVAILABLE','PRIOR_RECOVERY_REQUIRES_RECONCILIATION','BACKUP_HASH_MISMATCH','START_OUTCOME_REQUIRES_RECONCILIATION','LOCK_RELEASE_FAILED','WINDOWS_PS51_X64_REQUIRED','PACKAGE_PATH_INVALID','PACKAGE_HASH_MISMATCH','WINDOWS_PARSER_REJECTED','WINDOWS_SYNTHETIC_RUNTIME_FAILED','DIAGNOSTIC_INCOMPLETE','ACTIVE_ATTEMPT_REQUIRES_RECONCILIATION','EXACT_STOP_PHASE_NOT_YET_PROVEN','FAILURE_NOT_IN_VERIFIED_REPAIR_CLASS','CRYPTO_EVIDENCE_INCONSISTENT','EXISTING_EXECUTION_REQUIRES_RECONCILIATION','TASK_USER_DIFFERS','PROCESSED_STATE_INCONSISTENT','FACTORY_ID_MISMATCH','INSTALLED_SOURCE_DIVERGED','FEED_TARGET_MISMATCH','FEED_IDENTITY_MISMATCH','WATCHER_DID_NOT_STOP','STATE_CHANGED_BEFORE_APPLY','RECOVERY_EXCEPTION','ROLLBACK_FAILED','TASK_RESTART_FAILED','NO_NEW_ATTEMPT_AFTER_RESTART','UNEXPECTED_ACTIVE_JOB','BUILD_SUMMARY_INVALID','OBSERVATION_TIMEOUT_QUEUE_BLOCKED','WATCHER_HEARTBEAT_STALE')
    $code=if($_.Exception.Message -in $codes){$_.Exception.Message}else{'ONE_SHOT_EXCEPTION'}
    if($script:RunDirectory){try{Save-RunResult 'HOLD' $code}catch{
        # Last-resort result beside the extracted package, never raw exception text.
        try{[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'FACTORY_RESULT.json'),($script:RunState|ConvertTo-Json -Depth 16))}catch{
            try{[IO.File]::WriteAllText((Join-Path ([IO.Path]::GetTempPath()) ('FACTORY_RESULT_'+[Guid]::NewGuid().ToString('N')+'.json')),($script:RunState|ConvertTo-Json -Depth 16))}catch{}
        }
    }}
} finally {
    if($runLock){try{$runLock.ReleaseMutex();$runLock.Dispose()}catch{}}
    if($script:RunState.status -ne 'RUNNING'){
        try{
            $returned=Join-Path $script:RunDirectory 'RESULT.zip'
            if(-not (Test-Path -LiteralPath $returned)){$returned=Join-Path $script:RunDirectory 'FACTORY_RESULT.json'}
            if(Test-Path -LiteralPath $returned){Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"'+$returned+'"')|Out-Null}
        }catch{}
    }
}
