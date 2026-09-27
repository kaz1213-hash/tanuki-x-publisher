param(
    [switch]$DryRun,
    [switch]$Continuous,
    [int]$PollMinutes=15,
    [string]$CredentialPath='',
    [string]$GhPath=''
)

$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'TanukiX.Credentials.psm1') -Force

function Resolve-GhPath {
    if(-not [string]::IsNullOrWhiteSpace($GhPath) -and (Test-Path $GhPath -PathType Leaf)){return $GhPath}
    if(-not [string]::IsNullOrWhiteSpace($env:TANUKI_GH_PATH) -and (Test-Path $env:TANUKI_GH_PATH -PathType Leaf)){return $env:TANUKI_GH_PATH}
    if($env:LOCALAPPDATA){
        $candidate=Join-Path $env:LOCALAPPDATA 'TanukiRunner\deps\gh-2.101.0\bin\gh.exe'
        if(Test-Path $candidate -PathType Leaf){return $candidate}
    }
    try{return [string](Get-Command gh.exe -ErrorAction Stop).Source}catch{return ''}
}

function Get-PythonPath {
    $venv=Join-Path $root '.venv\Scripts\python.exe'
    if(Test-Path $venv -PathType Leaf){return $venv}
    $python=(Get-Command python.exe -ErrorAction Stop).Source
    & $python -m venv (Join-Path $root '.venv')
    $venv=Join-Path $root '.venv\Scripts\python.exe'
    & $venv -m pip install -q -r (Join-Path $root 'requirements.txt')
    if($LASTEXITCODE -ne 0){throw 'Tanuki X Python dependencies could not be prepared.'}
    return $venv
}

function Invoke-OnePublisherRun {
    $gh=Resolve-GhPath
    if([string]::IsNullOrWhiteSpace($gh)){throw 'GitHub CLI is not available. Prepare Tanuki Runner GitHub connection first.'}

    $env:TANUKI_GH_PATH=$gh
    $env:TANUKI_SOURCE_REPO='kaz1213-hash/tanuki-growth'
    $python=Get-PythonPath

    if($DryRun){
        & $python (Join-Path $root 'publisher.py') --dry-run
        if($LASTEXITCODE -ne 0){throw 'Tanuki X dry-run failed.'}
        return
    }

    $cred=Get-TanukiXCredentialState -Path $CredentialPath
    if($null -eq $cred){throw 'X API credentials are not configured on this PC.'}
    try{
        $env:X_API_KEY=$cred.ApiKey
        $env:X_API_SECRET=$cred.ApiSecret
        $env:X_ACCESS_TOKEN=$cred.AccessToken
        $env:X_ACCESS_TOKEN_SECRET=$cred.AccessTokenSecret
        & $python (Join-Path $root 'publisher.py')
        if($LASTEXITCODE -ne 0){throw 'Tanuki X publisher failed.'}
    }finally{
        Remove-Item Env:X_API_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:X_API_SECRET -ErrorAction SilentlyContinue
        Remove-Item Env:X_ACCESS_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:X_ACCESS_TOKEN_SECRET -ErrorAction SilentlyContinue
    }
}

$mutex=New-Object Threading.Mutex($false,'Local\TanukiX.LocalPublisher')
$owns=$false
try{
    try{$owns=$mutex.WaitOne(0,$false)}catch [Threading.AbandonedMutexException]{$owns=$true}
    if(-not $owns){Write-Host 'TANUKI_X_ALREADY_RUNNING';exit 0}

    do{
        try{Invoke-OnePublisherRun}catch{Write-Host ('TANUKI_X_ERROR '+$_.Exception.Message)}
        if(-not $Continuous){break}
        Start-Sleep -Seconds ([Math]::Max(60,$PollMinutes*60))
    }while($true)
}finally{
    if($owns){try{$mutex.ReleaseMutex()}catch{}}
    $mutex.Dispose()
}
