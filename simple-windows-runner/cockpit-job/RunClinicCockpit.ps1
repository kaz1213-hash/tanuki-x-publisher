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

function Write-JobResult([string]$Status,[string]$Code,[hashtable]$Extra=@{}){
    $o=[ordered]@{
        schema='tanuki-cockpit-runner-result-v2'
        status=$Status
        code=$Code
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
    $header=[Text.Encoding]::UTF8.GetBytes(('blob '+$raw.Length+"\0"))
    $all=New-Object byte[] ($header.Length+$raw.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($raw,0,$all,$header.Length,$raw.Length)
    $sha=[Security.Cryptography.SHA1]::Create()
    try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')}) -join '')}finally{$sha.Dispose()}
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
                    if([string]$j.candidate -ne $ExpectedCandidate){continue}
                    if([string]$j.frozen_product_commit -ne $ExpectedFrozen){continue}
                    if([string]$j.ready_branch -ne $ExpectedReadyBranch){continue}
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

$Stage=$null
try{
    $Original=Find-RC3Package
    if(-not $Original){Write-JobResult 'HOLD' 'RC3_PACKAGE_NOT_FOUND';exit 20}

    $Stage=Join-Path ([IO.Path]::GetTempPath()) ('TanukiCockpitR2_'+[Guid]::NewGuid().ToString('N'))
    Copy-PackageToStage $Original $Stage

    $StartHere=Join-Path $Stage 'START_HERE_WINDOWS.bat'
    $ExactText="@echo off\ncd /d %~dp0\npy -m pip install -r requirements.txt\npy -m streamlit run app.py\npause\n"
    [IO.File]::WriteAllBytes($StartHere,[Text.Encoding]::ASCII.GetBytes($ExactText))
    if((Git-BlobSha1 $StartHere) -ne $ExpectedStartHereBlob){Write-JobResult 'FAIL' 'START_HERE_FROZEN_BLOB_REPAIR_FAILED';exit 21}

    $Bootstrap=Join-Path $Stage 'tools\release_v080_rc3_bootstrap.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Bootstrap
    $rc=$LASTEXITCODE

    $Release=Join-Path $Stage 'RELEASE_OUTPUT_V080_RC3'
    $Build=Join-Path $Release 'BUILD_RESULT.json'
    if(-not(Test-Path -LiteralPath $Build -PathType Leaf)){Write-JobResult 'FAIL' 'BUILD_RESULT_MISSING' @{builder_exit=$rc};exit 22}

    Copy-Item -LiteralPath $Build -Destination (Join-Path $Out 'BUILD_RESULT.json') -Force
    $B=Get-Content -LiteralPath $Build -Raw -Encoding UTF8|ConvertFrom-Json

    $required=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
    $missing=@()
    foreach($name in $required){
      $step=@($B.steps|Where-Object{[string]$_.name -eq $name -and [string]$_.status -eq 'PASS'})|Select-Object -First 1
      if(-not $step){$missing+=$name}
    }

    $zip=Join-Path $Release $ExpectedZipName
    $ok=($rc -eq 0 -and [string]$B.status -eq 'PASS' -and [bool]$B.windows_candidate_pass -eq $true -and [string]$B.frozen_commit -eq $ExpectedFrozen -and $missing.Count -eq 0 -and (Test-Path -LiteralPath $zip -PathType Leaf))
    if(-not $ok){Write-JobResult 'FAIL' 'WINDOWS_CANDIDATE_NOT_PASS' @{builder_exit=$rc;build_status=[string]$B.status;windows_candidate_pass=[bool]$B.windows_candidate_pass;failed_step=[string]$B.failed_step;missing_required_gates=@($missing)};exit 23}

    $sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if($B.PSObject.Properties['output_zip_sha256']){
      if(([string]$B.output_zip_sha256).ToLowerInvariant() -ne $sha){Write-JobResult 'FAIL' 'FINAL_ZIP_SHA_MISMATCH' @{actual_sha256=$sha};exit 24}
    }

    Copy-Item -LiteralPath $zip -Destination (Join-Path $Out $ExpectedZipName) -Force
    Write-JobResult 'PASS' 'WINDOWS_CANDIDATE_PASS' @{builder_exit=$rc;output_zip=$ExpectedZipName;output_zip_sha256=$sha;repaired_stale_start_here_in_stage=$true;original_package_modified=$false;required_gates=@($required)}
    exit 0
}catch{
    Write-JobResult 'FAIL' 'COCKPIT_JOB_EXCEPTION' @{exception_type=$_.Exception.GetType().Name}
    exit 30
}finally{
    try{if($Stage -and (Test-Path -LiteralPath $Stage)){Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}
