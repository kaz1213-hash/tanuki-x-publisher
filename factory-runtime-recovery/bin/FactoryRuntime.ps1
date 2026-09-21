Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:FactoryRoot='C:\TanukiFactory'
$script:Attempt=$null
function Write-FactoryJson($Path,$Value) {
    $parent=Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Set-FactoryPhase([string]$Phase) {
    if($null -eq $script:Attempt){return}
    $script:Attempt.previous_phase=$script:Attempt.phase
    $script:Attempt.phase=$Phase
    $script:Attempt.updated_utc=[DateTime]::UtcNow.ToString('o')
    Write-FactoryJson (Join-Path $script:FactoryRoot 'STATE\active-attempt.json') $script:Attempt
}
function Start-FactoryAttempt([string]$JobId) {
    if($JobId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$'){throw 'Invalid job ID.'}
    $script:Attempt=[ordered]@{schema='tanuki-factory-attempt-v2';job_id=$JobId;attempt_id=[Guid]::NewGuid().ToString('N');phase='accepted';previous_phase=$null;status='RUNNING';started_utc=[DateTime]::UtcNow.ToString('o');updated_utc=[DateTime]::UtcNow.ToString('o');child_pid=$null;exit_code=$null;error_code=$null;product_gate='UNVERIFIED';return_state='LOCAL_ONLY';factory_completion_pass=$false}
    Set-FactoryPhase 'accepted'
}
function Complete-FactoryAttempt([string]$Status,[string]$Code) {
    if($Status -notin @('PASS','FAIL','HOLD')){throw 'Invalid terminal state.'}
    # Persist terminal JSON BEFORE any log, notification or compression operation.
    $script:Attempt.status=$Status
    $script:Attempt.error_code=$Code
    $script:Attempt.updated_utc=[DateTime]::UtcNow.ToString('o')
    $dir=Join-Path $script:FactoryRoot ('OUTBOX\'+$script:Attempt.job_id+'\'+$script:Attempt.attempt_id)
    $path=Join-Path $dir 'FACTORY_RESULT.json'
    Write-FactoryJson $path $script:Attempt
    Write-FactoryJson (Join-Path $script:FactoryRoot 'STATE\active-attempt.json') $script:Attempt
    try {
        # Only the allowlisted scalar record is returned. No logs/source/medical files.
        $zip=Join-Path (Split-Path $dir -Parent) ($script:Attempt.attempt_id+'_RESULT.zip')
        Compress-Archive -LiteralPath $path -DestinationPath $zip -Force
    } catch {
        $script:Attempt.error_code='RESULT_BUNDLE_FAILED'
        $script:Attempt.status='HOLD'
        Write-FactoryJson $path $script:Attempt
        Write-FactoryJson (Join-Path $script:FactoryRoot 'STATE\active-attempt.json') $script:Attempt
    }
    return $script:Attempt.status
}
function Expand-FactorySafeZip([string]$Zip,[string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $base=[IO.Path]::GetFullPath($Destination).TrimEnd('\')+'\'
    $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach($entry in $archive.Entries){
            if($entry.FullName -match ':' -or $entry.FullName -match '^[\\/]'){throw 'Unsafe ZIP path.'}
            $target=[IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if(-not $target.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'ZIP traversal rejected.'}
        }
    } finally {$archive.Dispose()}
    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
}
function Test-FactoryCockpitResult([string]$Source,[DateTime]$Started) {
    # Exact RC3 gate names come from the frozen R2 release builder.
    $paths=@(Get-ChildItem -LiteralPath $Source -Filter 'BUILD_RESULT.json' -File -Recurse -ErrorAction Stop)
    $valid=@()
    foreach($path in $paths){
        try {
            $r=Get-Content -LiteralPath $path.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if($r.schema -ne 'clinic-cockpit-no-github-windows-release-gate-v1'){continue}
            if($r.candidate -ne 'v0.8.0 RC3' -or $r.frozen_commit -ne '70ec03be3de89548bf61ceea2661bffb03dab18a'){continue}
            if($path.LastWriteTimeUtc -lt $Started){continue}
            if($r.status -ne 'PASS' -or $r.windows_candidate_pass -ne $true){continue}
            $required=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
            foreach($name in $required){
                $matches=@($r.steps | Where-Object {$_.name -eq $name})
                if($matches.Count -ne 1 -or $matches[0].status -ne 'PASS'){throw 'Required product gate missing.'}
            }
            if(-not (Test-TanukiSafeRelativePath ([string]$r.output_zip))){continue}
            $zip=Join-Path $path.DirectoryName ([string]$r.output_zip)
            if(-not (Test-Path -LiteralPath $zip -PathType Leaf)){continue}
            if((Get-TanukiSha256Hex $zip) -ne [string]$r.output_zip_sha256){continue}
            $valid+=,$r
        } catch {continue}
    }
    return ($valid.Count -eq 1)
}
function Invoke-TanukiJobPackage([string]$JobZip,[string]$JobId) {
    $config=Get-TanukiFactoryConfig
    # Never delete an older attempt's source, logs or outputs.
    $source=Join-Path $script:FactoryRoot ('WORK\'+$JobId+'\'+$script:Attempt.attempt_id+'\source')
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    Set-FactoryPhase 'zip-expand'
    Expand-FactorySafeZip $JobZip $source
    $job=Get-Content -LiteralPath (Join-Path $source 'job.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-FactoryPhase 'job-target-and-entrypoint'
    if($job.schema -ne 'tanuki-windows-factory-job-v1' -or $job.job_id -ne $JobId){throw 'Job identity mismatch.'}
    # Outer encrypted descriptor is mandatory for remote targeting; reject conflicting inner target.
    if($job.PSObject.Properties['target_factory_id'] -and $job.target_factory_id -ne $config.factory_id){throw 'Inner factory target mismatch.'}
    if(-not (Test-TanukiSafeRelativePath ([string]$job.entrypoint)) -or $job.entrypoint -match '[":]'){throw 'Unsafe entrypoint.'}
    $entry=Join-Path $source ([string]$job.entrypoint)
    if(-not (Test-Path -LiteralPath $entry -PathType Leaf)){throw 'Entrypoint missing.'}
    $ext=[IO.Path]::GetExtension($entry).ToLowerInvariant()
    $minutes=60
    if($job.PSObject.Properties['timeout_minutes']){$minutes=[int]$job.timeout_minutes}
    if($minutes -lt 1 -or $minutes -gt [int]$config.max_job_minutes){throw 'Invalid timeout.'}
    $env:TANUKI_FACTORY='1';$env:TANUKI_FACTORY_ID=[string]$config.factory_id
    $env:TANUKI_FACTORY_JOB_ID=$JobId
    $localOutput=Join-Path $source '_factory_output'
    New-Item -ItemType Directory -Path $localOutput -Force | Out-Null
    $env:TANUKI_FACTORY_OUTBOX=$localOutput
    switch($ext){
        '.ps1' {$exe='powershell.exe';$arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$entry+'"'}
        '.vbs' {$exe='cscript.exe';$arguments='//nologo "'+$entry+'"'}
        '.cmd' {$exe='cmd.exe';$arguments='/d /s /c ""'+$entry+'""'}
        '.bat' {$exe='cmd.exe';$arguments='/d /s /c ""'+$entry+'""'}
        default {throw 'Unsupported entrypoint.'}
    }
    Set-FactoryPhase 'process-spawn'
    $started=[DateTime]::UtcNow
    $proc=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $source -RedirectStandardOutput (Join-Path $localOutput 'stdout.log') -RedirectStandardError (Join-Path $localOutput 'stderr.log') -PassThru -WindowStyle Hidden
    # Hold process handle so exit code remains available after rapid child exit.
    $handle=$proc.Handle
    $script:Attempt.child_pid=$proc.Id
    Set-FactoryPhase 'job-running'
    if(-not $proc.WaitForExit($minutes*60000)){
        # Do not kill an unverified PID tree or advance the queue after timeout.
        $script:Attempt.error_code='CHILD_TIMEOUT_STILL_POSSIBLY_RUNNING'
        throw 'Child timeout; queue remains blocked.'
    }
    $proc.WaitForExit()
    $script:Attempt.exit_code=$proc.ExitCode
    Set-FactoryPhase 'product-result-validation'
    if($null -eq $proc.ExitCode){throw 'Exit code unavailable.'}
    if($proc.ExitCode -ne 0){return 'FAIL'}
    if($JobId -eq 'clinic-cockpit-rc3-r2-20260921-001'){
        if(-not (Test-FactoryCockpitResult $source $started)){return 'HOLD'}
        $script:Attempt.product_gate='WINDOWS_CANDIDATE_PASS'
        return 'PASS'
    }
    # Other product gates are not yet integrated and must not inherit exit-code PASS.
    return 'HOLD'
}
