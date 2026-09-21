Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$JobRoot = Join-Path $Root 'JOB'
$WorkRoot = Join-Path $Root '_work'
$ResultDir = Join-Path $Root '_result'
$ResultJson = Join-Path $Root 'RESULT.json'
$ResultZip = Join-Path $Root 'RESULT.zip'
$Stdout = Join-Path $Root '_stdout.txt'
$Stderr = Join-Path $Root '_stderr.txt'

$started = [DateTime]::UtcNow
$receipt = [ordered]@{
    schema = 'tanuki-windows-runner-result-v1'
    runner_version = '0.1'
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
}

function Save-Receipt {
    $receipt.finished_utc = [DateTime]::UtcNow.ToString('o')
    $json = $receipt | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($ResultJson, $json, (New-Object Text.UTF8Encoding($false)))
}

function Test-SafeRelativePath([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){ return $false }
    if([IO.Path]::IsPathRooted($Value)){ return $false }
    if($Value -match '(^|[\\/])\.\.([\\/]|$)'){ return $false }
    return $true
}

function Copy-Tail([string]$Source,[string]$Destination) {
    if(Test-Path -LiteralPath $Source -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $Source -Tail 200 -ErrorAction SilentlyContinue)
        [IO.File]::WriteAllLines($Destination, $lines, (New-Object Text.UTF8Encoding($false)))
    }
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
    $manifestPath = Join-Path $JobRoot 'job.json'
    if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ throw 'JOB_MANIFEST_MISSING' }
    $job = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if(-not $job.PSObject.Properties['job_id']){ throw 'JOB_ID_MISSING' }
    if(-not $job.PSObject.Properties['entrypoint']){ throw 'ENTRYPOINT_MISSING' }

    $receipt.job_id = [string]$job.job_id
    $receipt.entrypoint = [string]$job.entrypoint

    if(-not (Test-SafeRelativePath $receipt.entrypoint)){ throw 'ENTRYPOINT_UNSAFE' }

    $timeoutMinutes = 60
    if($job.PSObject.Properties['timeout_minutes']){ $timeoutMinutes = [int]$job.timeout_minutes }
    if($timeoutMinutes -lt 1 -or $timeoutMinutes -gt 1440){ throw 'TIMEOUT_INVALID' }

    $receipt.phase = 'STAGE_JOB'
    New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $JobRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $WorkRoot -Recurse -Force
    }

    $entry = Join-Path $WorkRoot $receipt.entrypoint
    $workCanonical = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\') + '\'
    $entryCanonical = [IO.Path]::GetFullPath($entry)
    if(-not $entryCanonical.StartsWith($workCanonical,[StringComparison]::OrdinalIgnoreCase)){ throw 'ENTRYPOINT_ESCAPE' }
    if(-not (Test-Path -LiteralPath $entryCanonical -PathType Leaf)){ throw 'ENTRYPOINT_NOT_FOUND' }

    $jobOutput = Join-Path $WorkRoot '_runner_output'
    New-Item -ItemType Directory -Path $jobOutput -Force | Out-Null
    $env:TANUKI_RUNNER_OUT = $jobOutput
    $env:TANUKI_RUNNER_JOB_ID = $receipt.job_id

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
    $completed = $proc.WaitForExit($timeoutMinutes * 60 * 1000)
    if(-not $completed) {
        try { $proc.Kill() } catch {}
        $receipt.status = 'HOLD'
        $receipt.error_code = 'TIMEOUT'
        $receipt.exit_code = 124
    } else {
        $proc.WaitForExit()
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
    if(Test-Path -LiteralPath $jobOutput -PathType Container) {
        $children = @(Get-ChildItem -LiteralPath $jobOutput -Force -ErrorAction SilentlyContinue)
        if($children.Count -gt 0) {
            $receipt.output_present = $true
            $outDest = Join-Path $ResultDir 'output'
            New-Item -ItemType Directory -Path $outDest -Force | Out-Null
            foreach($c in $children) {
                Copy-Item -LiteralPath $c.FullName -Destination $outDest -Recurse -Force
            }
        }
    }

    Copy-Tail $Stdout (Join-Path $ResultDir 'stdout_tail.txt')
    Copy-Tail $Stderr (Join-Path $ResultDir 'stderr_tail.txt')
}
catch {
    if($receipt.status -eq 'HOLD') {
        $receipt.error_code = [string]$_.Exception.Message
    }
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
        try {
            $receipt.result_zip_created = $false
            if(-not $receipt.error_code){ $receipt.error_code='RESULT_ZIP_FAILED' }
            Save-Receipt
        } catch {}
    }
}

if($receipt.status -eq 'PASS'){ exit 0 }
if($receipt.status -eq 'FAIL'){ exit 1 }
exit 2
