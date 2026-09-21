Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Out = $env:TANUKI_RUNNER_OUT
if(-not $Out){ throw 'RUNNER_OUTPUT_MISSING' }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ExpectedFrozen = 'bf640bc9a58c3810b2d8cadde46b142054a18f3f'
$PreviousFrozen = '33fffccf66ab66f4bf161af8f07797576a6379b7'
$ExpectedReadyBranch = 'release-ready/v0.8.0-rc3-no-github-r2'
$ExpectedCandidate = 'v0.8.0 RC3'
$ExpectedStartHereBlob = '5be7c5c73d20122bdd3226d2f65d2275c066a1bd'
$ExpectedReleaseBlob = '4caeec00f80e3315f1e3421a90b3b2b1d2add9c7'
$PreviousReleaseBlob = 'efe49a3ee7a97e6bb58270653df33bf1acb3caf6'
$ExpectedLauncherTestBlob = 'ee78ac488b7d402f870e7f48efe457169c12fb0f'
$PreviousLauncherTestBlob = '5ba963462b55a33555c9ca10ef906fd2618a6e69'
$ExpectedAdapterBlob = '7fc0b9e9252adef250654db645c20db86f323aad'
$PreviousAdapterBlob = '1e422cb5d207ab7c44e39c923b34267a6c90d048'
$ExpectedBootstrapBlob = '50dd8176ab2183c0f5daa82971964ef0a3ac86f1'
$PreviousBootstrapBlob = '313613ce6ac899b03bd54587af9382cd04bd345b'
$ExpectedBaseBuilderBlob = '866bf993f83a6add72f2593b579ba7f408eb8536'
$Phase = 'INIT'
$LASTEXITCODE = 0
. (Join-Path $PSScriptRoot 'CockpitAcceptance.ps1')

function Get-SafeProperty($Object,[string]$Name,$Default=$null){
    if($null -eq $Object){ return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if($null -eq $p){ return $Default }
    return $p.Value
}

function Write-JobResult([string]$Status,[string]$Code,[hashtable]$Extra=@{}){
    $o=[ordered]@{
        schema='tanuki-cockpit-runner-result-v4'
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

function Git-BlobSha1Bytes([byte[]]$Raw){
    $prefix=[Text.Encoding]::UTF8.GetBytes(('blob '+$Raw.Length))
    $header=New-Object byte[] ($prefix.Length+1)
    [Array]::Copy($prefix,0,$header,0,$prefix.Length)
    $header[$header.Length-1]=0
    $all=New-Object byte[] ($header.Length+$Raw.Length)
    [Array]::Copy($header,0,$all,0,$header.Length)
    [Array]::Copy($Raw,0,$all,$header.Length,$raw.Length)
    $sha=[Security.Cryptography.SHA1]::Create()
    try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')}) -join '')}finally{$sha.Dispose()}
}

function Git-BlobSha1([string]$Path){
    $raw=[IO.File]::ReadAllBytes($Path)
    $hash=Git-BlobSha1Bytes $raw
    return $hash
}

function Test-GitBlob([string]$Path,[string]$Expected){
    $raw=[IO.File]::ReadAllBytes($Path)
    $hash=Git-BlobSha1Bytes $raw
    if($hash -eq $Expected){ return $true }
    $text=[Text.Encoding]::UTF8.GetString($raw)
    if($text.Contains("`r`n")){
        $normalized=[Text.Encoding]::UTF8.GetBytes($text.Replace("`r`n","`n"))
        $normalizedHash=Git-BlobSha1Bytes $normalized
        if($normalizedHash -eq $Expected){ return $true }
    }
    return $false
}

function Write-Utf8Lf([string]$Path,[string]$Text){
    $Text=$Text.Replace("`r`n","`n").Replace("`r","`n")
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}

function Replace-One([string]$Text,[string]$Old,[string]$New){
    $count=([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if($count -ne 1){ throw 'PATCH_SOURCE_CONTRACT_MISMATCH' }
    return $Text.Replace($Old,$New)
}

function CandidateRoots {
    $list=New-Object System.Collections.Generic.List[string]
    foreach($p in @(
        'C:\TanukiFactory',
        (Join-Path $env:USERPROFILE 'Downloads'),
        ([Environment]::GetFolderPath('Desktop')),
        ([Environment]::GetFolderPath('MyDocuments')),
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
                    if([string](Get-SafeProperty $j 'ready_branch' '') -ne $ExpectedReadyBranch){continue}
                    $freeze=[string](Get-SafeProperty $j 'frozen_product_commit' '')
                    if($freeze -notin @($PreviousFrozen,$ExpectedFrozen)){continue}
                    $pkg=Split-Path -Parent (Split-Path -Parent $f.FullName)
                    $hits += [pscustomobject]@{Root=$pkg;Stamp=$f.LastWriteTimeUtc;Freeze=$freeze}
                }catch{}
            }
        }catch{}
    }
    if($hits.Count -eq 0){return $null}
    return ($hits|Sort-Object Stamp -Descending|Select-Object -First 1)
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
        'RELEASE_CANDIDATE.json',
        'tests\test_windows_launcher_runtime.py',
        'tools\release_v080_rc3_bootstrap.ps1',
        'tools\release_v080_rc3_builder.py',
        'tools\release_v080_rc2_builder.py',
        'tools\V080_RC2_SOURCE_BLOBS.json',
        'tools\V080_RC3_READY.json',
        'tools\requirements-release-lock-v080.txt',
        'BUILD_V080_RC3_WINDOWS.cmd',
        'START_BUILD_V080_RC3.vbs',
        'START_HERE_WINDOWS.bat'
    )){
        if(-not(Test-Path -LiteralPath (Join-Path $StageRoot $req) -PathType Leaf)){ throw 'STAGED_PACKAGE_INCOMPLETE' }
    }
    if(-not(Test-GitBlob (Join-Path $StageRoot 'tools\release_v080_rc2_builder.py') $ExpectedBaseBuilderBlob)){throw 'BASE_BUILDER_BLOB_MISMATCH'}
}

function Patch-ToCurrentFreeze([string]$StageRoot){
    $script:Phase='PATCH_CURRENT_FREEZE'

    $release=Join-Path $StageRoot 'RELEASE_CANDIDATE.json'
    if(-not(Test-GitBlob $release $ExpectedReleaseBlob)){
        if(-not(Test-GitBlob $release $PreviousReleaseBlob)){throw 'RELEASE_MANIFEST_SOURCE_UNEXPECTED'}
        $src=Join-Path $PSScriptRoot 'PATCH\RELEASE_CANDIDATE.json'
        if(-not(Test-GitBlob $src $ExpectedReleaseBlob)){throw 'PATCH_RELEASE_MANIFEST_INVALID'}
        Copy-Item -LiteralPath $src -Destination $release -Force
    }

    $test=Join-Path $StageRoot 'tests\test_windows_launcher_runtime.py'
    if(-not(Test-GitBlob $test $ExpectedLauncherTestBlob)){
        if(-not(Test-GitBlob $test $PreviousLauncherTestBlob)){throw 'LAUNCHER_TEST_SOURCE_UNEXPECTED'}
        $src=Join-Path $PSScriptRoot 'PATCH\test_windows_launcher_runtime.py'
        if(-not(Test-GitBlob $src $ExpectedLauncherTestBlob)){throw 'PATCH_LAUNCHER_TEST_INVALID'}
        Copy-Item -LiteralPath $src -Destination $test -Force
    }

    $adapter=Join-Path $StageRoot 'tools\release_v080_rc3_builder.py'
    if(-not(Test-GitBlob $adapter $ExpectedAdapterBlob)){
        if(-not(Test-GitBlob $adapter $PreviousAdapterBlob)){throw 'RC3_ADAPTER_SOURCE_UNEXPECTED'}
        $text=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
        $text=Replace-One $text 'RC3_FROZEN_COMMIT = "33fffccf66ab66f4bf161af8f07797576a6379b7"' 'RC3_FROZEN_COMMIT = "bf640bc9a58c3810b2d8cadde46b142054a18f3f"'
        $text=Replace-One $text 'RC3_FROZEN_TREE = "2a8eda04440baec5417bdb72f4e84f3f7e7f8930"' 'RC3_FROZEN_TREE = "4dcd25855460d7b15ce14261e9eae79aceab54f8"'
        $text=Replace-One $text '    "RELEASE_CANDIDATE.json": ("efe49a3ee7a97e6bb58270653df33bf1acb3caf6", 3819),' '    "RELEASE_CANDIDATE.json": ("4caeec00f80e3315f1e3421a90b3b2b1d2add9c7", 4104),'
        $needle='    "tests/test_release_candidate_v080.py": ("743340bcd302cfd2d67a6fe6336333265f386e09", 2442),'
        $insert=$needle+"`n"+'    "tests/test_windows_launcher_runtime.py": ("ee78ac488b7d402f870e7f48efe457169c12fb0f", 2691),'
        $text=Replace-One $text $needle $insert
        Write-Utf8Lf $adapter $text
    }

    $bootstrap=Join-Path $StageRoot 'tools\release_v080_rc3_bootstrap.ps1'
    if(-not(Test-GitBlob $bootstrap $ExpectedBootstrapBlob)){
        if(-not(Test-GitBlob $bootstrap $PreviousBootstrapBlob)){throw 'RC3_BOOTSTRAP_SOURCE_UNEXPECTED'}
        $text=[IO.File]::ReadAllText($bootstrap,[Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
        $text=Replace-One $text 'frozen_commit = "33fffccf66ab66f4bf161af8f07797576a6379b7"' 'frozen_commit = "bf640bc9a58c3810b2d8cadde46b142054a18f3f"'
        Write-Utf8Lf $bootstrap $text
    }

    if(-not(Test-GitBlob $release $ExpectedReleaseBlob)){throw 'CURRENT_RELEASE_MANIFEST_BLOB_MISMATCH'}
    if(-not(Test-GitBlob $test $ExpectedLauncherTestBlob)){throw 'CURRENT_LAUNCHER_TEST_BLOB_MISMATCH'}
    if(-not(Test-GitBlob $adapter $ExpectedAdapterBlob)){throw 'CURRENT_RC3_ADAPTER_BLOB_MISMATCH'}
    if(-not(Test-GitBlob $bootstrap $ExpectedBootstrapBlob)){throw 'CURRENT_RC3_BOOTSTRAP_BLOB_MISMATCH'}
}

function Write-ExactStartHere([string]$Path){
    $text="@echo off`ncd /d %~dp0`npy -m pip install -r requirements.txt`npy -m streamlit run app.py`npause`n"
    [IO.File]::WriteAllBytes($Path,[Text.Encoding]::ASCII.GetBytes($text))
}

function Start-FinalVisualTouch([string]$DeliveredZip,[string]$ArtifactRoot){
    $script:Phase='PREPARE_FINAL_VISUAL_TOUCH'
    $touchRoot=Join-Path $ArtifactRoot 'FINAL_TOUCH'
    if(Test-Path -LiteralPath $touchRoot){Remove-Item -LiteralPath $touchRoot -Recurse -Force}
    New-Item -ItemType Directory -Path $touchRoot -Force|Out-Null
    Expand-Archive -LiteralPath $DeliveredZip -DestinationPath $touchRoot -Force
    $exeName=([string][char]0x9662)+([string][char]0x9577)+([string][char]0x30EC)+([string][char]0x30F3)+([string][char]0x30C8)+([string][char]0x30B2)+([string][char]0x30F3)+'.exe'
    $matches=@(Get-ChildItem -LiteralPath $touchRoot -Filter $exeName -File -Recurse -ErrorAction Stop)
    if($matches.Count -ne 1){throw 'FINAL_TOUCH_EXE_NOT_UNIQUE'}
    Start-Process -FilePath $matches[0].FullName -WorkingDirectory $matches[0].DirectoryName | Out-Null
    return $true
}

$Stage=$null
try{
    $Phase='LOCATE_PACKAGE'
    $located=Find-RC3Package
    if($null -eq $located){Write-JobResult 'HOLD' 'RC3_PACKAGE_NOT_FOUND';exit 20}

    $Phase='STAGE_PACKAGE'
    $nonce=[Guid]::NewGuid().ToString('N').Substring(0,8)
    $Stage=Join-Path ([IO.Path]::GetTempPath()) ('TC3_'+$nonce)
    Copy-PackageToStage $located.Root $Stage
    Assert-StagedPackage $Stage
    Patch-ToCurrentFreeze $Stage

    $Phase='RESTORE_FROZEN_START_HERE'
    $StartHere=Join-Path $Stage 'START_HERE_WINDOWS.bat'
    Write-ExactStartHere $StartHere
    if((Git-BlobSha1 $StartHere) -ne $ExpectedStartHereBlob){Write-JobResult 'FAIL' 'START_HERE_FROZEN_BLOB_REPAIR_FAILED';exit 21}

    $Phase='RUN_EXISTING_RC3_GATE'
    $Bootstrap=Join-Path $Stage 'tools\release_v080_rc3_bootstrap.ps1'
    $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Bootstrap+'"'
    $builder=Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $Stage -RedirectStandardOutput (Join-Path $Stage 'builder.stdout.local.log') -RedirectStandardError (Join-Path $Stage 'builder.stderr.local.log') -PassThru
    $builderHandle=$builder.Handle
    $builder.WaitForExit()
    $rc=$builder.ExitCode
    if($null -eq $rc){throw 'BUILDER_EXIT_CODE_UNAVAILABLE'}

    $Phase='READ_BUILD_RESULT'
    $Release=Join-Path $Stage 'RELEASE_OUTPUT_V080_RC3'
    $Build=Join-Path $Release 'BUILD_RESULT.json'
    if(-not(Test-Path -LiteralPath $Build -PathType Leaf)){Write-JobResult 'FAIL' 'BUILD_RESULT_MISSING' @{builder_exit=$rc};exit 22}
    $B=Get-Content -LiteralPath $Build -Raw -Encoding UTF8|ConvertFrom-Json
    Get-SafeBuildSummary $B|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Out 'BUILD_RESULT_SUMMARY.json') -Encoding UTF8

    $Phase='VERIFY_FINAL_ZIP'
    $zip=Test-CockpitAcceptance $B $Release $rc
    $zipName=[IO.Path]::GetFileName($zip)
    $sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()

    $Phase='COLLECT_FINAL_ARTIFACT'
    $artifactRoot=$env:TANUKI_RUNNER_ARTIFACTS
    if(-not $artifactRoot){throw 'ARTIFACT_DIRECTORY_MISSING'}
    New-Item -ItemType Directory -Path $artifactRoot -Force|Out-Null
    $delivered=Join-Path $artifactRoot $zipName
    Copy-Item -LiteralPath $zip -Destination $delivered -Force
    if((Get-FileHash -LiteralPath $delivered -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha){throw 'DELIVERED_ZIP_SHA_MISMATCH'}

    $visual=Start-FinalVisualTouch $delivered $artifactRoot

    $Phase='TERMINAL_PASS'
    Write-JobResult 'PASS' 'WINDOWS_CANDIDATE_PASS_FINAL_TOUCH_LAUNCHED' @{
        builder_exit=$rc
        output_zip=$zipName
        output_zip_sha256=$sha
        source_package_freeze=[string]$located.Freeze
        staged_to_current_freeze=$true
        original_package_modified=$false
        product_gate_verified=$true
        visual_touch_launched=[bool]$visual
        visual_touch_required='confirm-dedicated-uke-and-chatgpt-tabs'
        release_pass=$false
    }
    exit 0
}catch{
    $safeType=$_.Exception.GetType().Name
    Write-JobResult 'FAIL' 'COCKPIT_JOB_EXCEPTION' @{exception_type=$safeType;exception_line=[int]$_.InvocationInfo.ScriptLineNumber;release_pass=$false}
    exit 30
}finally{
    try{if($Stage -and (Test-Path -LiteralPath $Stage)){Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}
