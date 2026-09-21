param(
    [Parameter(Mandatory=$true)]
    [string]$PackageRoot,
    [string]$RunnerRoot = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$here=Split-Path -Parent $MyInvocation.MyCommand.Path
if([string]::IsNullOrWhiteSpace($RunnerRoot)){
    $RunnerRoot=[IO.Path]::GetFullPath((Join-Path $here '..\simple-windows-runner'))
}

$preflight=Join-Path $here 'Test-JobPackage.ps1'
$preflightResult=Join-Path ([IO.Path]::GetFullPath($PackageRoot)) 'PREFLIGHT_RESULT.json'
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight -PackageRoot $PackageRoot -ResultPath $preflightResult
if($LASTEXITCODE -ne 0){ exit 20 }

$p=Get-Content -LiteralPath $preflightResult -Raw -Encoding UTF8 | ConvertFrom-Json
if([string]$p.status -ne 'PASS' -or [string]$p.code -ne 'PREFLIGHT_PASS'){ exit 21 }

$runJob=Join-Path $RunnerRoot 'RunJob.ps1'
if(-not (Test-Path -LiteralPath $runJob -PathType Leaf)){ exit 22 }

$jobRoot=Join-Path ([IO.Path]::GetFullPath($PackageRoot)) 'JOB'
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runJob -JobDirectory $jobRoot
exit $LASTEXITCODE
