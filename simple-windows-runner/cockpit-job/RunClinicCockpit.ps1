Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Out = $env:TANUKI_RUNNER_OUT
if(-not $Out){ throw 'RUNNER_OUTPUT_MISSING' }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ExpectedFrozen = '70ec03be3de89548bf61ceea2661bffb03dab18a'
$ExpectedReadyBranch = 'release-ready/v0.8.0-rc3-no-github-r2'
$ExpectedCandidate = 'v0.8.0 RC3'
$ExpectedZipName = '院長レントゲン_v0.8.0_RC3_WINDOWS.zip'

function Write-JobResult([string]$Status,[string]$Code,[hashtable]$Extra=@{}){
    $o=[ordered]@{
        schema='tanuki-cockpit-runner-result-v1'
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

function Find-ExactPackage {
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
                    foreach($req in @(
                        'tools\release_v080_rc3_bootstrap.ps1',
                        'tools\release_v080_rc3_builder.py',
                        'tools\release_v080_rc2_builder.py',
                        'tools\V080_RC2_SOURCE_BLOBS.json',
                        'tools\requirements-release-lock-v080.txt',
                        'BUILD_V080_RC3_WINDOWS.cmd',
                        'START_BUILD_V080_RC3.vbs',
                        'START_HERE_WINDOWS.bat'
                    )){
                        if(-not(Test-Path -LiteralPath (Join-Path $pkg $req) -PathType Leaf)){throw 'PACKAGE_INCOMPLETE'}
                    }
                    $hits += [pscustomobject]@{Root=$pkg;Stamp=$f.LastWriteTimeUtc}
                }catch{}
            }
        }catch{}
    }
    if($hits.Count -eq 0){return $null}
    return ($hits|Sort-Object Stamp -Descending|Select-Object -First 1).Root
}

try{
    Write-Host '[RUN] locate-exact-rc3-package'
    $Root=Find-ExactPackage
    if(-not $Root){
        Write-JobResult 'HOLD' 'EXACT_RC3_PACKAGE_NOT_FOUND'
        exit 20
    }
    Write-Host '[PASS] locate-exact-rc3-package'

    $Ready=Get-Content -LiteralPath (Join-Path $Root 'tools\V080_RC3_READY.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $Audit=Get-Content -LiteralPath (Join-Path $Root 'tools\V080_RC3_R2_STATIC_AUDIT.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$Audit.audit_status -ne 'PASS'){throw 'STATIC_AUDIT_NOT_PASS'}
    if([string]$Audit.frozen_source_commit -ne $ExpectedFrozen){throw 'STATIC_AUDIT_FROZEN_MISMATCH'}

    Write-Host '[RUN] exact-rc3-windows-gate'
    $Bootstrap=Join-Path $Root 'tools\release_v080_rc3_bootstrap.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Bootstrap
    $rc=$LASTEXITCODE
    Write-Host ('[INFO] exact-rc3-windows-gate exit='+$rc)

    $Release=Join-Path $Root 'RELEASE_OUTPUT_V080_RC3'
    $Build=Join-Path $Release 'BUILD_RESULT.json'
    if(-not(Test-Path -LiteralPath $Build -PathType Leaf)){
        Write-JobResult 'FAIL' 'BUILD_RESULT_MISSING' @{builder_exit=$rc}
        exit 21
    }

    Copy-Item -LiteralPath $Build -Destination (Join-Path $Out 'BUILD_RESULT.json') -Force
    $B=Get-Content -LiteralPath $Build -Raw -Encoding UTF8|ConvertFrom-Json

    $required=@(
      'frozen-source-verification',
      'integrated-source-completion-gate',
      'windows-runtime-product-gate',
      'portable-renamed-exe-runtime-gate',
      'final-zip-extracted-runtime-gate',
      'portable-privacy-scan'
    )
    $missing=@()
    foreach($name in $required){
      $step=@($B.steps|Where-Object{[string]$_.name -eq $name -and [string]$_.status -eq 'PASS'})|Select-Object -First 1
      if(-not $step){$missing+=$name}
    }

    $zip=Join-Path $Release $ExpectedZipName
    $ok=(
      $rc -eq 0 -and
      [string]$B.status -eq 'PASS' -and
      [bool]$B.windows_candidate_pass -eq $true -and
      [string]$B.frozen_commit -eq $ExpectedFrozen -and
      $missing.Count -eq 0 -and
      (Test-Path -LiteralPath $zip -PathType Leaf)
    )

    if(-not $ok){
        Write-JobResult 'FAIL' 'WINDOWS_CANDIDATE_NOT_PASS' @{
            builder_exit=$rc
            build_status=[string]$B.status
            windows_candidate_pass=[bool]$B.windows_candidate_pass
            failed_step=[string]$B.failed_step
            missing_required_gates=@($missing)
        }
        exit 22
    }

    $sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if($B.PSObject.Properties['output_zip_sha256']){
      if(([string]$B.output_zip_sha256).ToLowerInvariant() -ne $sha){
        Write-JobResult 'FAIL' 'FINAL_ZIP_SHA_MISMATCH' @{actual_sha256=$sha}
        exit 23
      }
    }

    Copy-Item -LiteralPath $zip -Destination (Join-Path $Out $ExpectedZipName) -Force
    $shaFile=Join-Path $Release 'SHA256.txt'
    if(Test-Path -LiteralPath $shaFile){Copy-Item -LiteralPath $shaFile -Destination (Join-Path $Out 'SHA256.txt') -Force}

    Write-JobResult 'PASS' 'WINDOWS_CANDIDATE_PASS' @{
        builder_exit=$rc
        output_zip=$ExpectedZipName
        output_zip_sha256=$sha
        required_gates=@($required)
    }
    Write-Host '[PASS] Clinic Cockpit Windows Candidate'
    exit 0
}catch{
    Write-JobResult 'FAIL' 'COCKPIT_JOB_EXCEPTION' @{exception_type=$_.Exception.GetType().Name}
    exit 30
}
