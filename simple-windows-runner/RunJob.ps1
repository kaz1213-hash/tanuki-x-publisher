param(
    [string]$JobDirectory = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunId = [Guid]::NewGuid().ToString('N')
if([string]::IsNullOrWhiteSpace($JobDirectory)){
    $JobRoot = Join-Path $Root 'JOB'
} elseif([IO.Path]::IsPathRooted($JobDirectory)) {
    $JobRoot = [IO.Path]::GetFullPath($JobDirectory)
} else {
    $JobRoot = [IO.Path]::GetFullPath((Join-Path $Root $JobDirectory))
}

$WorkBase = Join-Path ([IO.Path]::GetTempPath()) 'TanukiWindowsRunner'
$WorkRoot = Join-Path $WorkBase $RunId.Substring(0,12)
$ResultDir = Join-Path $Root '_result'
$ResultJson = Join-Path $Root 'RESULT.json'
$ResultZip = Join-Path $Root 'RESULT.zip'
$Stdout = Join-Path $Root '_stdout.txt'
$Stderr = Join-Path $Root '_stderr.txt'
$ArtifactRoot = Join-Path $Root ('ARTIFACTS\' + $RunId)

$started = [DateTime]::UtcNow
$receipt = [ordered]@{
    schema = 'tanuki-windows-runner-result-v3'
    runner_version = '0.5'
    run_id = $RunId
    manifest_schema = $null
    status = 'HOLD'
    phase = 'START'
    job_id = $null
    entrypoint = $null
    exit_code = $null
    error_code = $null
    started_utc = $started.ToString('o')
    finished_utc = $null
    result_zip_created = $false
    output_present = $false
    safe_result_files_collected = @()
    required_result_files_missing = @()
    artifact_count = 0
}

function Save-Receipt {
    $receipt.finished_utc = [DateTime]::UtcNow.ToString('o')
    $json = $receipt | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($ResultJson, $json, (New-Object Text.UTF8Encoding($false)))
}

function Test-SafeRelativePath([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){ return $false }
    if([IO.Path]::IsPathRooted($Value)){ return $false }
    if($Value -match '[:*?"<>|]'){ return $false }
    if($Value -match '(^|[\\/])\.\.?([\\/]|$)'){ return $false }
    if($Value.EndsWith('\') -or $Value.EndsWith('/')){ return $false }
    return $true
}

function Get-SafePathList($Object,[string]$Property,[bool]$RequiredProperty) {
    $p = $Object.PSObject.Properties[$Property]
    if($null -eq $p) {
        if($RequiredProperty){ throw ($Property.ToUpperInvariant() + '_MISSING') }
        return @()
    }

    $seen = @{}
    $items = @()
    foreach($raw in @($p.Value)) {
        $value = [string]$raw
        if(-not (Test-SafeRelativePath $value)){ throw ($Property.ToUpperInvariant() + '_UNSAFE') }
        $key = $value.ToLowerInvariant()
        if($seen.ContainsKey($key)){ throw ($Property.ToUpperInvariant() + '_DUPLICATE') }
        $seen[$key] = $true
        $items += $value
    }
    return $items
}

function Copy-Tail([string]$Source,[string]$Destination) {
    if(Test-Path -LiteralPath $Source -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $Source -Tail 200 -ErrorAction SilentlyContinue)
        [IO.File]::WriteAllLines($Destination, $lines, (New-Object Text.UTF8Encoding($false)))
    }
}

function Test-ContainedPath([string]$Base,[string]$Candidate) {
    $baseCanonical = [IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'
    $candidateCanonical = [IO.Path]::GetFullPath($Candidate)
    return $candidateCanonical.StartsWith($baseCanonical,[StringComparison]::OrdinalIgnoreCase)
}

try {
    foreach($p in @($WorkRoot,$ResultDir)) {
        if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Recurse -Force }
    }
    foreach($p in @($ResultJson,$ResultZip,$Stdout,$Stderr)) {
        if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Force }
    }

    $receipt.phase = 'LOAD_MANIFEST'
    if(-not (Test-Path -LiteralPath $JobRoot -PathType Container)){ throw 'JOB_DIRECTORY_MISSING' }

    $reparse = @(Get-ChildItem -LiteralPath $JobRoot -Force -Recurse -ErrorAction Stop | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if($reparse.Count -gt 0){ throw 'JOB_REPARSE_POINT_UNSUPPORTED' }

    $manifestPath = Join-Path $JobRoot 'job.json'
    if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ throw 'JOB_MANIFEST_MISSING' }
    $job = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if(-not $job.PSObject.Properties['schema']){ throw 'JOB_SCHEMA_MISSING' }
    $receipt.manifest_schema = [string]$job.schema
    if($receipt.manifest_schema -ne 'tanuki-windows-runner-job-v1'){ throw 'JOB_SCHEMA_UNSUPPORTED' }

    if(-not $job.PSObject.Properties['job_id']){ throw 'JOB_ID_MISSING' }
    if(-not $job.PSObject.Properties['entrypoint']){ throw 'ENTRYPOINT_MISSING' }

    $receipt.job_id = [string]$job.job_id
    if($receipt.job_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'){ throw 'JOB_ID_INVALID' }

    $receipt.entrypoint = [string]$job.entrypoint
    if(-not (Test-SafeRelativePath $receipt.entrypoint)){ throw 'ENTRYPOINT_UNSAFE' }

    $safeResultFiles = @(Get-SafePathList $job 'safe_result_files' $true)
    $requiredResultFiles = @(Get-SafePathList $job 'required_result_files' $false)
    foreach($required in $requiredResultFiles) {
        if($required -notin $safeResultFiles){ throw 'REQUIRED_RESULT_NOT_ALLOWLISTED' }
    }

    $timeoutMinutes = 60
    if($job.PSObject.Properties['timeout_minutes']){ $timeoutMinutes = [int]$job.timeout_minutes }
    if($timeoutMinutes -lt 1 -or $timeoutMinutes -gt 1440){ throw 'TIMEOUT_INVALID' }

    $includeConsoleTail = $false
    if($job.PSObject.Properties['include_console_tail']){
        if($job.include_console_tail -isnot [bool]){ throw 'INCLUDE_CONSOLE_TAIL_NOT_BOOLEAN' }
        $includeConsoleTail = [bool]$job.include_console_tail
    }

    $receipt.phase = 'STAGE_JOB'
    New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $JobRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $WorkRoot -Recurse -Force
    }

    $entry = Join-Path $WorkRoot $receipt.entrypoint
    if(-not (Test-ContainedPath $WorkRoot $entry)){ throw 'ENTRYPOINT_ESCAPE' }
    $entryCanonical = [IO.Path]::GetFullPath($entry)
    if(-not (Test-Path -LiteralPath $entryCanonical -PathType Leaf)){ throw 'ENTRYPOINT_NOT_FOUND' }

    $jobOutput = Join-Path $WorkRoot '_runner_output'
    New-Item -ItemType Directory -Path $jobOutput -Force | Out-Null
    New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null

    $env:TANUKI_RUNNER_OUT = $jobOutput
    $env:TANUKI_RUNNER_JOB_ID = $receipt.job_id
    $env:TANUKI_RUNNER_RUN_ID = $RunId
    $env:TANUKI_RUNNER_ARTIFACTS = $ArtifactRoot

    $ext = [IO.Path]::GetExtension($entryCanonical).ToLowerInvariant()
    $exe = $null
    $arguments = $null
    switch($ext) {
        '.ps1' { $exe='powershell.exe'; $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$entryCanonical+'"' }
        '.cmd' { $exe='cmd.exe'; $arguments='/d /s /c ""'+$entryCanonical+'""' }
        '.bat' { $exe='cmd.exe'; $arguments='/d /s /c ""'+$entryCanonical+'""' }
        '.vbs' { $exe='cscript.exe'; $arguments='//nologo "'+$entryCanonical+'"' }
        '.exe' { $exe=$entryCanonical; $arguments='' }
        default { throw 'ENTRYPOINT_TYPE_UNSUPPORTED' }
    }

    $receipt.phase = 'RUN_JOB'
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $WorkRoot -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
    $handle = $proc.Handle
    $completed = $proc.WaitForExit($timeoutMinutes * 60 * 1000)

    if(-not $completed) {
        try { & taskkill.exe /PID $proc.Id /T /F 2>$null | Out-Null } catch { try { $proc.Kill() } catch {} }
        try { $proc.WaitForExit(15000) | Out-Null } catch {}
        $receipt.status = 'HOLD'
        $receipt.error_code = 'TIMEOUT'
        $receipt.exit_code = 124
    } else {
        $proc.WaitForExit()
        if($null -eq $proc.ExitCode){ throw 'CHILD_EXIT_CODE_UNAVAILABLE' }
        $receipt.exit_code = [int]$proc.ExitCode
        if($proc.ExitCode -eq 0) {
            $receipt.status = 'PASS'
        } else {
            $receipt.status = 'FAIL'
            $receipt.error_code = 'CHILD_EXIT_NONZERO'
        }
    }

    $receipt.phase = 'COLLECT_RESULT'
    New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null
    $outDest = Join-Path $ResultDir 'output'
    $collected = @()

    $outputRootItem = Get-Item -LiteralPath $jobOutput -Force -ErrorAction Stop
    if(($outputRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ throw 'RESULT_REPARSE_POINT_UNSUPPORTED' }
    $outputReparse = @(Get-ChildItem -LiteralPath $jobOutput -Force -Recurse -ErrorAction Stop | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if($outputReparse.Count -gt 0){ throw 'RESULT_REPARSE_POINT_UNSUPPORTED' }

    foreach($rel in $safeResultFiles) {
        $src = Join-Path $jobOutput $rel
        if(-not (Test-ContainedPath $jobOutput $src)){ throw 'RESULT_PATH_ESCAPE' }
        if(Test-Path -LiteralPath $src -PathType Leaf) {
            if(-not (Test-Path -LiteralPath $outDest)){ New-Item -ItemType Directory -Path $outDest -Force | Out-Null }
            $dst = Join-Path $outDest $rel
            $parent = Split-Path -Parent $dst
            if($parent){ New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
            $collected += $rel
        }
    }

    $receipt.safe_result_files_collected = @($collected)
    $receipt.output_present = ($collected.Count -gt 0)

    $missing = @()
    foreach($rel in $requiredResultFiles) {
        if($rel -notin $collected){ $missing += $rel }
    }
    $receipt.required_result_files_missing = @($missing)

    if($receipt.status -eq 'PASS' -and $missing.Count -gt 0) {
        $receipt.status = 'FAIL'
        $receipt.error_code = 'REQUIRED_RESULT_MISSING'
    }

    if(Test-Path -LiteralPath $ArtifactRoot -PathType Container) {
        $receipt.artifact_count = @(Get-ChildItem -LiteralPath $ArtifactRoot -File -Recurse -ErrorAction SilentlyContinue).Count
    }

    if($includeConsoleTail) {
        Copy-Tail $Stdout (Join-Path $ResultDir 'stdout_tail.txt')
        Copy-Tail $Stderr (Join-Path $ResultDir 'stderr_tail.txt')
    }
}
catch {
    $failedPhase = [string]$receipt.phase
    $receipt.status = 'FAIL'
    $receipt.error_code = 'RUNNER_EXCEPTION_' + $failedPhase
}
finally {
    $receipt.phase = 'TERMINAL'
    try { Save-Receipt } catch {}
    try {
        if(-not (Test-Path -LiteralPath $ResultDir)){ New-Item -ItemType Directory -Path $ResultDir -Force | Out-Null }
        Copy-Item -LiteralPath $ResultJson -Destination (Join-Path $ResultDir 'RESULT.json') -Force

        if(Test-Path -LiteralPath $ResultZip){ Remove-Item -LiteralPath $ResultZip -Force }
        Compress-Archive -Path (Join-Path $ResultDir '*') -DestinationPath $ResultZip -Force

        $receipt.result_zip_created = $true
        Save-Receipt
        Copy-Item -LiteralPath $ResultJson -Destination (Join-Path $ResultDir 'RESULT.json') -Force

        if(Test-Path -LiteralPath $ResultZip){ Remove-Item -LiteralPath $ResultZip -Force }
        Compress-Archive -Path (Join-Path $ResultDir '*') -DestinationPath $ResultZip -Force
    } catch {
        $receipt.status = 'FAIL'
        $receipt.result_zip_created = $false
        $receipt.error_code = 'RESULT_ZIP_FAILED'
        try { Save-Receipt } catch {}
    }

    try {
        if(Test-Path -LiteralPath $WorkRoot){ Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if((Test-Path -LiteralPath $ArtifactRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $ArtifactRoot -Force -ErrorAction SilentlyContinue).Count -eq 0){
            Remove-Item -LiteralPath $ArtifactRoot -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

if($receipt.status -eq 'PASS'){ exit 0 }
if($receipt.status -eq 'FAIL'){ exit 1 }
exit 2
