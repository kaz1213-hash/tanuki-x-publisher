param(
    [Parameter(Mandatory=$true)]
    [string]$PackageRoot,
    [string]$RunnerRoot = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$here=Split-Path -Parent $MyInvocation.MyCommand.Path
if([string]::IsNullOrWhiteSpace($RunnerRoot)){
    $RunnerRoot=[IO.Path]::GetFullPath((Join-Path $here '..\simple-windows-runner'))
}

$package=[IO.Path]::GetFullPath($PackageRoot)
$job=Get-Content -LiteralPath (Join-Path $package 'JOB\job.json') -Raw -Encoding UTF8|ConvertFrom-Json
$resultJson=Join-Path $RunnerRoot 'RESULT.json'
$resultZip=Join-Path $RunnerRoot 'RESULT.zip'
$outPath=Join-Path $package 'FACTORY_VERIFY_RESULT.json'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('TWR_RESULT_VERIFY_'+[Guid]::NewGuid().ToString('N').Substring(0,10))

$summary=[ordered]@{
    schema='tanuki-windows-package-verify-result-v1'
    status='FAIL'
    code='NOT_RUN'
    job_id=[string]$job.job_id
    runner_schema_ok=$false
    runner_version_ok=$false
    runner_pass=$false
    required_results_present=$false
    collected_results_allowlisted=$false
    zip_contents_bounded=$false
}

function Save-Summary{
    $json=$script:summary|ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($outPath,$json,(New-Object Text.UTF8Encoding($false)))
}

try{
    if(-not(Test-Path -LiteralPath $resultJson -PathType Leaf)){throw 'RESULT_JSON_MISSING'}
    if(-not(Test-Path -LiteralPath $resultZip -PathType Leaf)){throw 'RESULT_ZIP_MISSING'}

    $r=Get-Content -LiteralPath $resultJson -Raw -Encoding UTF8|ConvertFrom-Json
    $summary.runner_schema_ok=([string]$r.schema -eq 'tanuki-windows-runner-result-v3')
    if(-not $summary.runner_schema_ok){throw 'RUNNER_SCHEMA_MISMATCH'}

    $summary.runner_version_ok=([string]$r.runner_version -eq '0.5')
    if(-not $summary.runner_version_ok){throw 'RUNNER_VERSION_MISMATCH'}

    if([string]$r.job_id -ne [string]$job.job_id){throw 'RUNNER_JOB_ID_MISMATCH'}
    $summary.runner_pass=([string]$r.status -eq 'PASS' -and [int]$r.exit_code -eq 0 -and $r.result_zip_created -eq $true)
    if(-not $summary.runner_pass){throw 'RUNNER_NOT_PASS'}

    $safe=@($job.safe_result_files|ForEach-Object{[string]$_})
    $required=@($job.required_result_files|ForEach-Object{[string]$_})
    $collected=@($r.safe_result_files_collected|ForEach-Object{[string]$_})
    $missing=@($r.required_result_files_missing)

    $allow=$true
    foreach($name in $collected){if($name -notin $safe){$allow=$false}}
    $summary.collected_results_allowlisted=$allow
    if(-not $allow){throw 'COLLECTED_RESULT_NOT_ALLOWLISTED'}

    $requiredOk=($missing.Count -eq 0)
    foreach($name in $required){if($name -notin $collected){$requiredOk=$false}}
    $summary.required_results_present=$requiredOk
    if(-not $requiredOk){throw 'REQUIRED_RESULT_MISSING'}

    New-Item -ItemType Directory -Path $temp -Force|Out-Null
    Expand-Archive -LiteralPath $resultZip -DestinationPath $temp -Force

    $actual=@()
    foreach($f in @(Get-ChildItem -LiteralPath $temp -File -Recurse -Force)){
        $rel=$f.FullName.Substring($temp.TrimEnd('\').Length).TrimStart('\').Replace('\','/')
        $actual+=$rel
    }

    $expected=@('RESULT.json')
    foreach($name in $collected){$expected+=('output/'+$name.Replace('\','/'))}

    $actualSorted=@($actual|Sort-Object)
    $expectedSorted=@($expected|Sort-Object)
    $bounded=($actualSorted.Count -eq $expectedSorted.Count)
    if($bounded){
        for($i=0;$i -lt $actualSorted.Count;$i++){
            if($actualSorted[$i] -ne $expectedSorted[$i]){$bounded=$false;break}
        }
    }
    $summary.zip_contents_bounded=$bounded
    if(-not $bounded){throw 'RESULT_ZIP_CONTENTS_UNBOUNDED'}

    $summary.status='PASS'
    $summary.code='VERIFY_PASS'
}catch{
    if($summary.code -eq 'NOT_RUN'){
        $m=[string]$_.Exception.Message
        if($m -match '^[A-Z0-9_]+$'){$summary.code=$m}else{$summary.code='VERIFY_REJECTED'}
    }
}finally{
    try{Save-Summary}catch{}
    try{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}

if($summary.status -eq 'PASS'){exit 0}
exit 1
