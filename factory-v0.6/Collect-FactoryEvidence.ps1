param(
    [Parameter(Mandatory=$true)]
    [string]$PackageRoot,
    [Parameter(Mandatory=$true)]
    [string]$RunnerRoot,
    [Parameter(Mandatory=$true)]
    [string]$OutputZip
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$package=[IO.Path]::GetFullPath($PackageRoot)
$runner=[IO.Path]::GetFullPath($RunnerRoot)
$output=[IO.Path]::GetFullPath($OutputZip)
$temp=Join-Path ([IO.Path]::GetTempPath()) ('TWR_EVIDENCE_'+[Guid]::NewGuid().ToString('N').Substring(0,10))

$summary=[ordered]@{
    schema='tanuki-windows-factory-evidence-v1'
    status='FAIL'
    preflight_status='MISSING'
    runner_status='MISSING'
    verify_status='MISSING'
    job_id=$null
    product=$null
    evidence_files=@()
}

function Read-JsonSafe([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
    try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}
}
function Copy-Safe([string]$Source,[string]$Name){
    if(Test-Path -LiteralPath $Source -PathType Leaf){
        Copy-Item -LiteralPath $Source -Destination (Join-Path $temp $Name) -Force
        $script:summary.evidence_files+= $Name
    }
}

try{
    New-Item -ItemType Directory -Path $temp -Force|Out-Null

    $preflightPath=Join-Path $package 'PREFLIGHT_RESULT.json'
    $verifyPath=Join-Path $package 'FACTORY_VERIFY_RESULT.json'
    $runnerJson=Join-Path $runner 'RESULT.json'
    $runnerZip=Join-Path $runner 'RESULT.zip'

    $p=Read-JsonSafe $preflightPath
    if($null -ne $p){
        $summary.preflight_status=[string]$p.status
        $summary.job_id=[string]$p.job_id
        $summary.product=[string]$p.product
    }

    $r=Read-JsonSafe $runnerJson
    if($null -ne $r){$summary.runner_status=[string]$r.status}

    $v=Read-JsonSafe $verifyPath
    if($null -ne $v){$summary.verify_status=[string]$v.status}

    Copy-Safe $preflightPath 'PREFLIGHT_RESULT.json'
    Copy-Safe $runnerJson 'RESULT.json'
    Copy-Safe $runnerZip 'RESULT.zip'
    Copy-Safe $verifyPath 'FACTORY_VERIFY_RESULT.json'

    if($summary.preflight_status -eq 'PASS' -and $summary.runner_status -eq 'PASS' -and $summary.verify_status -eq 'PASS'){
        $summary.status='PASS'
    }

    $summaryPath=Join-Path $temp 'EVIDENCE_SUMMARY.json'
    $summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $summaryPath -Encoding UTF8

    if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Force}
    Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $output -Force
}catch{
    try{
        $summary.status='FAIL'
        $summaryPath=Join-Path $temp 'EVIDENCE_SUMMARY.json'
        if(-not(Test-Path -LiteralPath $temp)){New-Item -ItemType Directory -Path $temp -Force|Out-Null}
        $summary|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $summaryPath -Encoding UTF8
        if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Force}
        Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $output -Force
    }catch{}
}finally{
    try{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}

if($summary.status -eq 'PASS'){exit 0}
exit 1
