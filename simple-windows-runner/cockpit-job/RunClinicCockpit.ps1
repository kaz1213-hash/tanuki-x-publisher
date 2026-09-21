Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Out = $env:TANUKI_RUNNER_OUT
if(-not $Out){ throw 'RUNNER_OUTPUT_MISSING' }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ExpectedFrozen = '70ec03be3de89548bf61ceea2661bffb03dab18a'
$ExpectedReadyBranch = 'release-ready/v0.8.0-rc3-no-github-r2'
$ExpectedCandidate = 'v0.8.0 RC3'
$ExpectedZipName = '院長レントゲン_v0.8.0_RC3_WINDOWS.zip'
$ExpectedStartHereBlob = '5be7c5c73d20122bdd3226d2f65d2275c066a1bd'
$Phase = 'INIT'

function Get-SafeProperty($Object,[string]$Name,$Default=$null){
    if($null -eq $Object){ return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if($null -eq $p){ return $Default }
    return $p.Value
}

function Get-LastFailedStep($BuildResult){
    $direct = Get-SafeProperty $BuildResult 'failed_step' $null
    if($direct){ return [string]$direct }
    $steps = @(Get-SafeProperty $BuildResult 'steps' @())
    $failed = @($steps | Where-Object { [string](Get-SafeProperty $_ 'status' '') -eq 'FAIL' })
    if($failed.Count -gt 0){ return [string](Get-SafeProperty $failed[-1] 'name' 'UNKNOWN_FAILED_STEP') }
    return $null
}

function Write-JobResult([string]$Status,[string]$Code,[hashtable]$Extra=@{}){
    $o=[ordered]@{
        schema='tanuki-cockpit-runner-result-v3'
        status=$Status
        code=$Code
        phase=$Phase
        candidate=$ExpectedCandidate
        frozen_commit=$ExpectedFrozen
        ready_branch=$ExpectedReadyBranch
        utc=[DateTime]::UtcNow.ToString('o')
    }
    foreach($k in $Extra.Keys){$o[$k]=$Extra[$k]}
    $o|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Out 'COCKPIT_JOB_RESULT.json') -Encoding UTF8
}

function Git-BlobSha1([string]$Path){
    $raw=[IO.File]::ReadAllBytes($Path)
    $prefix=[Text.Encoding]::UTF8.GetBytes(('blob '+$raw.Length))
    $header=New-Object byte[] ($prefix.Length+1)
    [Array]::Copy($prefix,0,$header,0,$prefix.Length)
    $header[$header.Length-1]=0
    $all=New-Object byte[] ($header.Length+$raw.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($raw,0,$all,$header.Length,$raw.Length)
    $sha=[Security.Cryptography.SHA1]::Create()
    try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')}) -join '')}finally{$sha.Dispose()}
}

function Write-ExactStartHere([string]$Path){
    $text="@echo off`ncd /d %~dp0`npy -m pip install -r requirements.txt`npy -m streamlit run app.py`npause`n"
    [IO.File]::WriteAllBytes($Path,[Text.Encoding]::ASCII.GetBytes($text))
}

function CandidateRoots {
    $list=New-Object System.Collections.Generic.List[string]
    foreach($p in @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        ([Environment]::GetFolderPath('Desktop')),
        ([Environment]::GetFolderPath('MyDocuments')),
        'C:\TanukiFactory',
        (Split-Path -Parent $PSScriptRoot)
    )){
        if($p -and (Test-Path -LiteralPath $p -PathType Container)){$list.Add($p)}
    }
    return $list
}

function Find-RC3Package {
    $hits=@()
    foreach($root in CandidateRoots){
        try{
            $files=@(Get-ChildItem -LiteralPath $root -Filter 'V080_RC3_READY.json' -File -Recurse -ErrorAction SilentlyContinue)
            foreach($f in $files){
                if($f.FullName -notmatch '\\tools\\V080_RC3_READY\.json$'){continue}
                try{
                    $j=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json
                    if([string](Get-SafeProperty $j 'candidate' '') -ne $ExpectedCandidate){continue}
                    if([string](Get-SafeProperty $j 'frozen_product_commit' '') -ne $ExpectedFrozen){continue}
                    if([string](Get-SafeProperty $j 'ready_branch' '') -ne $ExpectedReadyBranch){continue}
                    $pkg=Split-Path -Parent (Split-Path -Parent $f.FullName)
                    $hits += [pscustomobject]@{Root=$pkg;Stamp=$f.LastWriteTimeUtc}
                }catch{}
            }
        }catch{}
    }
    if($hits.Count -eq 0){return $null}
    return ($hits|Sort-Object Stamp -Descending|Select-Object -First 1).Root
}

function Copy-PackageToStage([string]$Source,[string]$Destination){
    $ignored=@('.git','RELEASE_OUTPUT_V080_RC2','RELEASE_OUTPUT_V080_RC3','__pycache__','.pytest_cache','.venv','venv')
    New-Item -ItemType Directory -Force -Path $Destination|Out-Null
    foreach($f in @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction Stop)){
        $rel=$f.FullName.Substring($Source.TrimEnd('\').Length).TrimStart('\')
        $parts=$rel -split '\\'
        if(@($parts|Where-Object{$_ -in $ignored}).Count -gt 0){continue}
        $dst=Join-Path $Destination $rel
        $parent=Split-Path -Parent $dst
        if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
    }
}

function Assert-StagedPackage([string]$StageRoot){
    foreach($req in @(
        'tools\release_v080_rc3_bootstrap.ps1',
        'tools\release_v080_rc3_builder.py',
        'tools\release_v080_rc2_builder.py',
        'tools\V080_RC2_SOURCE_BLOBS.json',
        'tools\V080_RC3_READY.json',
        'tools\V080_RC3_R2_STATIC_AUDIT.json',
        'tools\requirements-release-lock-v080.txt',
        'BUILD_V080_RC3_WINDOWS.cmd',
        'START_BUILD_V080_RC3.vbs',
        'START_HERE_WINDOWS.bat'
    )){
        if(-not(Test-Path -LiteralPath (Join-Path $StageRoot $req) -PathType Leaf)){ throw 'STAGED_PACKAGE_INCOMPLETE' }
    }

    $ready=Get-Content -LiteralPath (Join-Path $StageRoot 'tools\V080_RC3_READY.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if([string](Get-SafeProperty $ready 'candidate' '') -ne $ExpectedCandidate){ throw 'READY_CANDIDATE_MISMATCH' }
    if([string](Get-SafeProperty $ready 'frozen_product_commit' '') -ne $ExpectedFrozen){ throw 'READY_FROZEN_MISMATCH' }
    if([string](Get-SafeProperty $ready 'ready_branch' '') -ne $ExpectedReadyBranch){ throw 'READY_BRANCH_MISMATCH' }

    $audit=Get-Content -LiteralPath (Join-Path $StageRoot 'tools\V080_RC3_R2_STATIC_AUDIT.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if([string](Get-SafeProperty $audit 'audit_status' '') -ne 'PASS'){ throw 'STATIC_AUDIT_NOT_PASS' }
    if([string](Get-SafeProperty $audit 'frozen_source_commit' '') -ne $ExpectedFrozen){ throw 'STATIC_AUDIT_FROZEN_MISMATCH' }
}

$Stage=$null
try{
    $Phase='LOCATE_PACKAGE'
    $Original=Find-RC3Package
    if(-not $Original){Write-JobResult 'HOLD' 'RC3_PACKAGE_NOT_FOUND';exit 20}

    $Phase='STAGE_PACKAGE'
    $Stage=Join-Path ([IO.Path]::GetTempPath()) ('TanukiCockpitR2_'+[Guid]::NewGuid().ToString('N'))
    Copy-PackageToStage $Original $Stage
    Assert-StagedPackage $Stage

    $Phase='RESTORE_FROZEN_START_HERE'
    $StartHere=Join-Path $Stage 'START_HERE_WINDOWS.bat'
    Write-ExactStartHere $StartHere
    if((Git-BlobSha1 $StartHere) -ne $ExpectedStartHereBlob){Write-JobResult 'FAIL' 'START_HERE_FROZEN_BLOB_REPAIR_FAILED';exit 21}

    $Phase='RUN_EXISTING_RC3_GATE'
    $Bootstrap=Join-Path $Stage 'tools\release_v080_rc3_bootstrap.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Bootstrap
    $rc=$LASTEXITCODE

    $Phase='READ_BUILD_RESULT'
    $Release=Join-Path $Stage 'RELEASE_OUTPUT_V080_RC3'
    $Build=Join-Path $Release 'BUILD_RESULT.json'
    if(-not(Test-Path -LiteralPath $Build -PathType Leaf)){Write-JobResult 'FAIL' 'BUILD_RESULT_MISSING' @{builder_exit=$rc};exit 22}

    Copy-Item -LiteralPath $Build -Destination (Join-Path $Out 'BUILD_RESULT.json') -Force
    $B=Get-Content -LiteralPath $Build -Raw -Encoding UTF8|ConvertFrom-Json

    $required=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
    $missing=@()
    $steps=@(Get-SafeProperty $B 'steps' @())
    foreach($name in $required){
      $step=@($steps|Where-Object{[string](Get-SafeProperty $_ 'name' '') -eq $name -and [string](Get-SafeProperty $_ 'status' '') -eq 'PASS'})|Select-Object -First 1
      if(-not $step){$missing+=$name}
    }

    $buildStatus=[string](Get-SafeProperty $B 'status' '')
    $windowsPass=[bool](Get-SafeProperty $B 'windows_candidate_pass' $false)
    $frozen=[string](Get-SafeProperty $B 'frozen_commit' '')
    $failedStep=Get-LastFailedStep $B
    $zip=Join-Path $Release $ExpectedZipName
    $ok=($rc -eq 0 -and $buildStatus -eq 'PASS' -and $windowsPass -and $frozen -eq $ExpectedFrozen -and $missing.Count -eq 0 -and (Test-Path -LiteralPath $zip -PathType Leaf))
    if(-not $ok){
        Write-JobResult 'FAIL' 'WINDOWS_CANDIDATE_NOT_PASS' @{
            builder_exit=$rc
            build_status=$buildStatus
            windows_candidate_pass=$windowsPass
            failed_step=$failedStep
            missing_required_gates=@($missing)
        }
        exit 23
    }

    $Phase='VERIFY_FINAL_ZIP'
    $sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $declaredSha=[string](Get-SafeProperty $B 'output_zip_sha256' '')
    if($declaredSha -and $declaredSha.ToLowerInvariant() -ne $sha){Write-JobResult 'FAIL' 'FINAL_ZIP_SHA_MISMATCH' @{actual_sha256=$sha};exit 24}

    $Phase='COLLECT_FINAL_ARTIFACT'
    Copy-Item -LiteralPath $zip -Destination (Join-Path $Out $ExpectedZipName) -Force
    $shaFile=Join-Path $Release 'SHA256.txt'
    if(Test-Path -LiteralPath $shaFile -PathType Leaf){Copy-Item -LiteralPath $shaFile -Destination (Join-Path $Out 'SHA256.txt') -Force}

    $Phase='TERMINAL_PASS'
    Write-JobResult 'PASS' 'WINDOWS_CANDIDATE_PASS' @{
        builder_exit=$rc
        output_zip=$ExpectedZipName
        output_zip_sha256=$sha
        repaired_stale_start_here_in_stage=$true
        original_package_modified=$false
        required_gates=@($required)
    }
    exit 0
}catch{
    $safeType=$_.Exception.GetType().Name
    Write-JobResult 'FAIL' 'COCKPIT_JOB_EXCEPTION' @{exception_type=$safeType}
    exit 30
}finally{
    try{if($Stage -and (Test-Path -LiteralPath $Stage)){Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}
