Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Out = $env:TANUKI_RUNNER_OUT
$Artifacts = $env:TANUKI_RUNNER_ARTIFACTS
$JobId = $env:TANUKI_RUNNER_JOB_ID
$RunId = $env:TANUKI_RUNNER_RUN_ID

$checks = [ordered]@{
    output_env_present = -not [string]::IsNullOrWhiteSpace($Out)
    artifact_env_present = -not [string]::IsNullOrWhiteSpace($Artifacts)
    job_id_matches = ($JobId -eq 'runner-selftest-v1')
    run_id_present = -not [string]::IsNullOrWhiteSpace($RunId)
}

if($checks.output_env_present){ New-Item -ItemType Directory -Path $Out -Force | Out-Null }
if($checks.artifact_env_present){ New-Item -ItemType Directory -Path $Artifacts -Force | Out-Null }

if($checks.output_env_present) {
    [IO.File]::WriteAllText((Join-Path $Out 'UNLISTED_PRIVATE_PROBE.txt'),'must-not-enter-result-zip',(New-Object Text.UTF8Encoding($false)))
}

$artifactWrite = $false
if($checks.artifact_env_present) {
    $artifactPath = Join-Path $Artifacts 'runner-selftest-artifact.txt'
    [IO.File]::WriteAllText($artifactPath,'runner-selftest-artifact',(New-Object Text.UTF8Encoding($false)))
    $artifactWrite = Test-Path -LiteralPath $artifactPath -PathType Leaf
}
$checks['artifact_write'] = $artifactWrite

$pass = $true
foreach($v in $checks.Values){ if($v -ne $true){ $pass = $false } }

$result = [ordered]@{
    schema = 'tanuki-windows-runner-selftest-v1'
    status = $(if($pass){'PASS'}else{'FAIL'})
    checks = $checks
}

if($checks.output_env_present) {
    $json = $result | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $Out 'SELFTEST_RESULT.json'),$json,(New-Object Text.UTF8Encoding($false)))
}

if($pass){ exit 0 }
exit 10
