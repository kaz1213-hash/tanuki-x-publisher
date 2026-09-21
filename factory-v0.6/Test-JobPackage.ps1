param(
    [Parameter(Mandatory=$true)]
    [string]$PackageRoot,
    [string]$ResultPath = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath($PackageRoot)
if([string]::IsNullOrWhiteSpace($ResultPath)){
    $ResultPath = Join-Path $root 'PREFLIGHT_RESULT.json'
}

$checks = New-Object System.Collections.Generic.List[object]
$result = [ordered]@{
    schema = 'tanuki-windows-job-preflight-result-v1'
    status = 'FAIL'
    code = 'NOT_RUN'
    package_id = $null
    product = $null
    risk_class = $null
    source_repository = $null
    source_ref = $null
    job_id = $null
    entrypoint = $null
    safe_result_count = 0
    required_result_count = 0
    checks = $checks
}

function Add-Check([string]$Name,[string]$Status) {
    $script:checks.Add([ordered]@{name=$Name;status=$Status}) | Out-Null
    if($Status -ne 'PASS'){ throw ('CHECK_FAILED_' + $Name) }
}

function Write-Result {
    $json = $script:result | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($ResultPath,$json,(New-Object Text.UTF8Encoding($false)))
}

function Test-SafeToken([string]$Value) {
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
}

function Test-SafeRelativePath([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){ return $false }
    if([IO.Path]::IsPathRooted($Value)){ return $false }
    if($Value -match '[:*?"<>|]'){ return $false }
    if($Value -match '(^|[\\/])\.\.?([\\/]|$)'){ return $false }
    if($Value.EndsWith('\') -or $Value.EndsWith('/')){ return $false }
    return $true
}

function Get-StringList($Object,[string]$Property) {
    $p = $Object.PSObject.Properties[$Property]
    if($null -eq $p){ throw ($Property.ToUpperInvariant() + '_MISSING') }
    $seen=@{}
    $items=@()
    foreach($raw in @($p.Value)){
        $value=[string]$raw
        if(-not (Test-SafeRelativePath $value)){ throw ($Property.ToUpperInvariant() + '_UNSAFE') }
        $key=$value.ToLowerInvariant()
        if($seen.ContainsKey($key)){ throw ($Property.ToUpperInvariant() + '_DUPLICATE') }
        $seen[$key]=$true
        $items += $value
    }
    return $items
}

try {
    if(-not (Test-Path -LiteralPath $root -PathType Container)){ throw 'PACKAGE_ROOT_MISSING' }
    Add-Check 'package-root' 'PASS'

    $reparse=@(Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction Stop | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if($reparse.Count -ne 0){ throw 'PACKAGE_REPARSE_POINT_UNSUPPORTED' }
    Add-Check 'no-reparse-points' 'PASS'

    $packagePath=Join-Path $root 'PACKAGE.json'
    if(-not (Test-Path -LiteralPath $packagePath -PathType Leaf)){ throw 'PACKAGE_MANIFEST_MISSING' }
    $pkg=Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Check 'package-manifest-readable' 'PASS'

    if([string]$pkg.schema -ne 'tanuki-windows-job-package-v1'){ throw 'PACKAGE_SCHEMA_UNSUPPORTED' }
    Add-Check 'package-schema' 'PASS'

    if(-not (Test-SafeToken ([string]$pkg.package_id))){ throw 'PACKAGE_ID_INVALID' }
    $result.package_id=[string]$pkg.package_id
    Add-Check 'package-id' 'PASS'

    if([string]::IsNullOrWhiteSpace([string]$pkg.product)){ throw 'PRODUCT_MISSING' }
    $result.product=[string]$pkg.product
    Add-Check 'product' 'PASS'

    if(-not (Test-SafeToken ([string]$pkg.package_version))){ throw 'PACKAGE_VERSION_INVALID' }
    Add-Check 'package-version' 'PASS'

    $risk=[string]$pkg.risk_class
    if($risk -notin @('read-only','local-build','local-write')){ throw 'RISK_CLASS_INVALID' }
    $result.risk_class=$risk
    Add-Check 'risk-class' 'PASS'

    if($null -eq $pkg.PSObject.Properties['director_operations_required']){ throw 'DIRECTOR_OPERATIONS_MISSING' }
    if([int]$pkg.director_operations_required -ne 0){ throw 'DIRECTOR_OPERATIONS_NOT_ZERO' }
    Add-Check 'director-operations-zero' 'PASS'

    if([string]$pkg.job_directory -ne 'JOB'){ throw 'JOB_DIRECTORY_NOT_STANDARD' }
    Add-Check 'job-directory-standard' 'PASS'

    $source=$pkg.PSObject.Properties['source']
    if($null -eq $source){ throw 'SOURCE_PROVENANCE_MISSING' }
    $sourceRepo=[string]$pkg.source.repository
    $sourceRef=[string]$pkg.source.ref
    if($sourceRepo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){ throw 'SOURCE_REPOSITORY_INVALID' }
    if([string]::IsNullOrWhiteSpace($sourceRef)){ throw 'SOURCE_REF_MISSING' }
    $result.source_repository=$sourceRepo
    $result.source_ref=$sourceRef
    Add-Check 'source-provenance' 'PASS'

    $jobRoot=Join-Path $root 'JOB'
    if(-not (Test-Path -LiteralPath $jobRoot -PathType Container)){ throw 'JOB_ROOT_MISSING' }
    Add-Check 'job-root' 'PASS'

    foreach($reserved in @('RESULT.json','RESULT.zip','_result','_stdout.txt','_stderr.txt','ARTIFACTS')){
        if(Test-Path -LiteralPath (Join-Path $jobRoot $reserved)){ throw 'RESERVED_RUNNER_OUTPUT_PRESENT' }
    }
    Add-Check 'no-reserved-runner-output' 'PASS'

    $jobPath=Join-Path $jobRoot 'job.json'
    if(-not (Test-Path -LiteralPath $jobPath -PathType Leaf)){ throw 'JOB_MANIFEST_MISSING' }
    $job=Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Check 'job-manifest-readable' 'PASS'

    if([string]$job.schema -ne 'tanuki-windows-runner-job-v1'){ throw 'JOB_SCHEMA_UNSUPPORTED' }
    Add-Check 'job-schema' 'PASS'

    if(-not (Test-SafeToken ([string]$job.job_id))){ throw 'JOB_ID_INVALID' }
    $result.job_id=[string]$job.job_id
    if($result.job_id -ne $result.package_id){ throw 'PACKAGE_JOB_ID_MISMATCH' }
    Add-Check 'package-job-id-match' 'PASS'

    $entry=[string]$job.entrypoint
    if(-not (Test-SafeRelativePath $entry)){ throw 'ENTRYPOINT_UNSAFE' }
    $ext=[IO.Path]::GetExtension($entry).ToLowerInvariant()
    if($ext -notin @('.ps1','.cmd','.bat','.vbs','.exe')){ throw 'ENTRYPOINT_TYPE_UNSUPPORTED' }
    $entryPath=Join-Path $jobRoot $entry
    if(-not (Test-Path -LiteralPath $entryPath -PathType Leaf)){ throw 'ENTRYPOINT_NOT_FOUND' }
    $result.entrypoint=$entry
    Add-Check 'entrypoint' 'PASS'

    $timeout=[int]$job.timeout_minutes
    if($timeout -lt 1 -or $timeout -gt 1440){ throw 'TIMEOUT_INVALID' }
    Add-Check 'timeout' 'PASS'

    if($job.include_console_tail -isnot [bool] -or $job.include_console_tail -ne $false){ throw 'CONSOLE_TAIL_MUST_BE_FALSE' }
    Add-Check 'console-tail-disabled' 'PASS'

    $safe=@(Get-StringList $job 'safe_result_files')
    $required=@(Get-StringList $job 'required_result_files')
    if($safe.Count -lt 1){ throw 'SAFE_RESULT_REQUIRED' }
    if($required.Count -lt 1){ throw 'REQUIRED_RESULT_REQUIRED' }
    foreach($name in $required){
        if($name -notin $safe){ throw 'REQUIRED_RESULT_NOT_ALLOWLISTED' }
    }
    $result.safe_result_count=$safe.Count
    $result.required_result_count=$required.Count
    Add-Check 'result-contract' 'PASS'

    $result.status='PASS'
    $result.code='PREFLIGHT_PASS'
}
catch {
    $result.status='FAIL'
    if($result.code -eq 'NOT_RUN'){
        $message=[string]$_.Exception.Message
        if($message -match '^[A-Z0-9_]+$'){
            $result.code=$message
        } else {
            $result.code='PREFLIGHT_REJECTED'
        }
    }
}
finally {
    try { Write-Result } catch {}
}

if($result.status -eq 'PASS'){ exit 0 }
exit 1
