param(
    [string]$RunnerRoot = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if([string]::IsNullOrWhiteSpace($RunnerRoot)){
    $RunnerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$RunnerRoot = [IO.Path]::GetFullPath($RunnerRoot)

$ResultJson = Join-Path $RunnerRoot 'RESULT.json'
$ResultZip = Join-Path $RunnerRoot 'RESULT.zip'
$FinalJson = Join-Path $RunnerRoot 'SELFTEST_FINAL.json'
$FinalZip = Join-Path $RunnerRoot 'FACTORY_SELFTEST_RESULT.zip'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('TWR_VERIFY_' + [Guid]::NewGuid().ToString('N').Substring(0,10))

$summary = [ordered]@{
    schema = 'tanuki-windows-runner-selftest-final-v1'
    status = 'FAIL'
    runner_version = $null
    run_id = $null
    result_schema_ok = $false
    manifest_schema_ok = $false
    runner_pass = $false
    allowlist_enforced = $false
    required_result_present = $false
    child_selftest_pass = $false
    artifact_separation = $false
    artifact_count = $null
    error_code = $null
    utc = [DateTime]::UtcNow.ToString('o')
}

function Save-Final {
    $json = $summary | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($FinalJson,$json,(New-Object Text.UTF8Encoding($false)))
}

try {
    if(-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)){ throw 'RESULT_JSON_MISSING' }
    if(-not (Test-Path -LiteralPath $ResultZip -PathType Leaf)){ throw 'RESULT_ZIP_MISSING' }

    $r = Get-Content -LiteralPath $ResultJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $summary.runner_version = [string]$r.runner_version
    $summary.run_id = [string]$r.run_id
    $summary.artifact_count = [int]$r.artifact_count

    $summary.result_schema_ok = ([string]$r.schema -eq 'tanuki-windows-runner-result-v3' -and [string]$r.runner_version -eq '0.5')
    $summary.manifest_schema_ok = ([string]$r.manifest_schema -eq 'tanuki-windows-runner-job-v1' -and [string]$r.job_id -eq 'runner-selftest-v1')
    $summary.runner_pass = ([string]$r.status -eq 'PASS' -and [int]$r.exit_code -eq 0 -and $r.result_zip_created -eq $true)

    $collected = @($r.safe_result_files_collected)
    $missing = @($r.required_result_files_missing)
    $summary.required_result_present = ($missing.Count -eq 0 -and $collected.Count -eq 1 -and [string]$collected[0] -eq 'SELFTEST_RESULT.json')

    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    Expand-Archive -LiteralPath $ResultZip -DestinationPath $Temp -Force

    $probe = Get-ChildItem -LiteralPath $Temp -Filter 'UNLISTED_PRIVATE_PROBE.txt' -Recurse -File -ErrorAction SilentlyContinue
    $summary.allowlist_enforced = (@($probe).Count -eq 0)

    $selfResult = Join-Path $Temp 'output\SELFTEST_RESULT.json'
    if(Test-Path -LiteralPath $selfResult -PathType Leaf){
        $s = Get-Content -LiteralPath $selfResult -Raw -Encoding UTF8 | ConvertFrom-Json
        $checkValues = @($s.checks.PSObject.Properties | ForEach-Object { $_.Value })
        $allChecks = $true
        foreach($v in $checkValues){ if($v -ne $true){ $allChecks = $false } }
        $summary.child_selftest_pass = ([string]$s.schema -eq 'tanuki-windows-runner-selftest-v1' -and [string]$s.status -eq 'PASS' -and $allChecks)
    }

    $artifact = Join-Path $RunnerRoot ('ARTIFACTS\' + $summary.run_id + '\runner-selftest-artifact.txt')
    $summary.artifact_separation = (
        $summary.artifact_count -eq 1 -and
        (Test-Path -LiteralPath $artifact -PathType Leaf) -and
        -not (Test-Path -LiteralPath (Join-Path $Temp 'runner-selftest-artifact.txt') -PathType Leaf) -and
        -not (Test-Path -LiteralPath (Join-Path $Temp 'output\runner-selftest-artifact.txt') -PathType Leaf)
    )

    $pass = (
        $summary.result_schema_ok -and
        $summary.manifest_schema_ok -and
        $summary.runner_pass -and
        $summary.allowlist_enforced -and
        $summary.required_result_present -and
        $summary.child_selftest_pass -and
        $summary.artifact_separation
    )

    if(-not $pass){ throw 'SELFTEST_CONTRACT_NOT_PASS' }

    $summary.status = 'PASS'
    Save-Final

    if(Test-Path -LiteralPath $FinalZip){ Remove-Item -LiteralPath $FinalZip -Force }
    $pack = Join-Path $Temp '_final'
    New-Item -ItemType Directory -Path $pack -Force | Out-Null
    Copy-Item -LiteralPath $FinalJson -Destination (Join-Path $pack 'SELFTEST_FINAL.json') -Force
    Copy-Item -LiteralPath $ResultJson -Destination (Join-Path $pack 'RESULT.json') -Force
    Copy-Item -LiteralPath (Join-Path $Temp 'output\SELFTEST_RESULT.json') -Destination (Join-Path $pack 'SELFTEST_RESULT.json') -Force
    Compress-Archive -Path (Join-Path $pack '*') -DestinationPath $FinalZip -Force

    try {
        $artifactDir = Split-Path -Parent $artifact
        if(Test-Path -LiteralPath $artifactDir -PathType Container){ Remove-Item -LiteralPath $artifactDir -Recurse -Force -ErrorAction SilentlyContinue }
    } catch {}

    exit 0
}
catch {
    if(-not $summary.error_code){ $summary.error_code = 'SELFTEST_VERIFIER_EXCEPTION' }
    try { Save-Final } catch {}
    try {
        if(Test-Path -LiteralPath $FinalZip){ Remove-Item -LiteralPath $FinalZip -Force }
        $pack = Join-Path $Temp '_fail'
        New-Item -ItemType Directory -Path $pack -Force | Out-Null
        if(Test-Path -LiteralPath $FinalJson){ Copy-Item -LiteralPath $FinalJson -Destination (Join-Path $pack 'SELFTEST_FINAL.json') -Force }
        if(Test-Path -LiteralPath $ResultJson){ Copy-Item -LiteralPath $ResultJson -Destination (Join-Path $pack 'RESULT.json') -Force }
        Compress-Archive -Path (Join-Path $pack '*') -DestinationPath $FinalZip -Force
    } catch {}
    exit 1
}
finally {
    try { if(Test-Path -LiteralPath $Temp){ Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
}
