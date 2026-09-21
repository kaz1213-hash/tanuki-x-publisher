Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$preflight=Join-Path $here 'Test-JobPackage.ps1'
$template=Join-Path $here 'TEMPLATE'
$root=Join-Path ([IO.Path]::GetTempPath()) ('TWR_JOB_CONTRACT_'+[Guid]::NewGuid().ToString('N').Substring(0,10))
New-Item -ItemType Directory -Path $root -Force|Out-Null

function Copy-Fixture([string]$Name){
    $dst=Join-Path $root $Name
    Copy-Item -LiteralPath $template -Destination $dst -Recurse -Force
    return $dst
}
function Run-Preflight([string]$Path){
    $result=Join-Path $Path 'PREFLIGHT_RESULT.json'
    & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight -PackageRoot $Path -ResultPath $result | Out-Null
    $rc=$LASTEXITCODE
    $payload=$null
    if(Test-Path -LiteralPath $result -PathType Leaf){
        $payload=Get-Content -LiteralPath $result -Raw -Encoding UTF8|ConvertFrom-Json
    }
    return [pscustomobject]@{ExitCode=$rc;Payload=$payload}
}
function Save-Json([string]$Path,$Object){
    $Object|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Path -Encoding UTF8
}
function Expect-Pass([string]$Name,[scriptblock]$Mutate){
    $p=Copy-Fixture $Name
    & $Mutate $p
    $r=Run-Preflight $p
    if($r.ExitCode -ne 0 -or [string]$r.Payload.status -ne 'PASS'){throw ('EXPECTED_PASS_'+$Name)}
}
function Expect-Fail([string]$Name,[scriptblock]$Mutate){
    $p=Copy-Fixture $Name
    & $Mutate $p
    $r=Run-Preflight $p
    if($r.ExitCode -eq 0 -or [string]$r.Payload.status -ne 'FAIL'){throw ('EXPECTED_FAIL_'+$Name)}
}

$count=0
try{
    Expect-Pass 'valid' {param($p)}
    $count++

    Expect-Fail 'wrong-package-schema' {
        param($p)
        $f=Join-Path $p 'PACKAGE.json';$j=Get-Content $f -Raw|ConvertFrom-Json;$j.schema='wrong';Save-Json $f $j
    };$count++

    Expect-Fail 'id-mismatch' {
        param($p)
        $f=Join-Path $p 'JOB\job.json';$j=Get-Content $f -Raw|ConvertFrom-Json;$j.job_id='different-id';Save-Json $f $j
    };$count++

    Expect-Fail 'entrypoint-traversal' {
        param($p)
        $f=Join-Path $p 'JOB\job.json';$j=Get-Content $f -Raw|ConvertFrom-Json;$j.entrypoint='..\escape.ps1';Save-Json $f $j
    };$count++

    Expect-Fail 'console-tail-enabled' {
        param($p)
        $f=Join-Path $p 'JOB\job.json';$j=Get-Content $f -Raw|ConvertFrom-Json;$j.include_console_tail=$true;Save-Json $f $j
    };$count++

    Expect-Fail 'required-not-allowlisted' {
        param($p)
        $f=Join-Path $p 'JOB\job.json';$j=Get-Content $f -Raw|ConvertFrom-Json;$j.required_result_files=@('OTHER.json');Save-Json $f $j
    };$count++

    Expect-Fail 'director-operation' {
        param($p)
        $f=Join-Path $p 'PACKAGE.json';$j=Get-Content $f -Raw|ConvertFrom-Json;$j.director_operations_required=1;Save-Json $f $j
    };$count++

    Expect-Fail 'reserved-output' {
        param($p)
        [IO.File]::WriteAllText((Join-Path $p 'JOB\RESULT.json'),'{}')
    };$count++

    "JOB_PACKAGE_PREFLIGHT_CONTRACT_PASS=$count"
}finally{
    try{Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}catch{}
}
