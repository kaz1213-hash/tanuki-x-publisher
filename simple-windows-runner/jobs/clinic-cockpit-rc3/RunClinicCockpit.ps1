Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Out = $env:TANUKI_RUNNER_OUT
if(-not $Out){ throw 'RUNNER_OUTPUT_MISSING' }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$ExpectedFrozen = 'bf640bc9a58c3810b2d8cadde46b142054a18f3f'
$ExpectedFrozenTree = '4dcd25855460d7b15ce14261e9eae79aceab54f8'
$ExpectedReadyBranch = 'release-ready/v0.8.0-rc3-no-github-r2'
$ExpectedReadyCommit = '7bd55eb7010fe20f233506cea0ac11a6a48c9449'
$ExpectedCandidate = 'v0.8.0 RC3'
$ExpectedStartHereBlob = '5be7c5c73d20122bdd3226d2f65d2275c066a1bd'
$ExpectedReleaseBlob = '4caeec00f80e3315f1e3421a90b3b2b1d2add9c7'
$ExpectedLauncherTestBlob = 'ee78ac488b7d402f870e7f48efe457169c12fb0f'
$ExpectedAdapterBlob = '7fc0b9e9252adef250654db645c20db86f323aad'
$ExpectedBootstrapBlob = '50dd8176ab2183c0f5daa82971964ef0a3ac86f1'
$ExpectedBaseBuilderBlob = '866bf993f83a6add72f2593b579ba7f408eb8536'
$ReadyArchiveUrl = 'https://github.com/kaz1213-hash/clinic-cockpit-lite/archive/' + $ExpectedReadyCommit + '.zip'
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
        schema='tanuki-cockpit-runner-result-v5'
        status=$Status
        code=$Code
        phase=$Phase
        candidate=$ExpectedCandidate
        frozen_commit=$ExpectedFrozen
        ready_branch=$ExpectedReadyBranch
        ready_commit=$ExpectedReadyCommit
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
    [Array]::Copy($Raw,0,$all,$header.Length,$Raw.Length)
    $sha=[Security.Cryptography.SHA1]::Create()
    try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')}) -join '')}finally{$sha.Dispose()}
}

function Test-GitBlob([string]$Path,[string]$Expected){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
    $raw=[IO.File]::ReadAllBytes($Path)
    $hash=Git-BlobSha1Bytes $raw
    if($hash -eq $Expected){ return $true }
    $text=[Text.Encoding]::UTF8.GetString($raw)
    if($text.Contains("`r`n")){
        $normalized=[Text.Encoding]::UTF8.GetBytes($text.Replace("`r`n","`n"))
        if((Git-BlobSha1Bytes $normalized) -eq $Expected){ return $true }
    }
    return $false
}

function Acquire-CanonicalReadyPackage([string]$ExtractRoot,[string]$ArchivePath){
    $script:Phase='DOWNLOAD_CANONICAL_READY_PACKAGE'
    if(Test-Path -LiteralPath $ArchivePath){Remove-Item -LiteralPath $ArchivePath -Force}
    if(Test-Path -LiteralPath $ExtractRoot){Remove-Item -LiteralPath $ExtractRoot -Recurse -Force}
    New-Item -ItemType Directory -Path $ExtractRoot -Force|Out-Null

    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $ReadyArchiveUrl -OutFile $ArchivePath
    if(-not(Test-Path -LiteralPath $ArchivePath -PathType Leaf)){throw 'READY_ARCHIVE_DOWNLOAD_MISSING'}
    if((Get-Item -LiteralPath $ArchivePath).Length -lt 1024){throw 'READY_ARCHIVE_DOWNLOAD_TOO_SMALL'}

    $script:Phase='EXPAND_CANONICAL_READY_PACKAGE'
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractRoot -Force
    $readyFiles=@(Get-ChildItem -LiteralPath $ExtractRoot -Filter 'V080_RC3_READY.json' -File -Recurse -ErrorAction Stop | Where-Object {$_.FullName -match '\\tools\\V080_RC3_READY\.json$'})
    if($readyFiles.Count -ne 1){throw 'READY_MANIFEST_NOT_UNIQUE'}

    $ready=Get-Content -LiteralPath $readyFiles[0].FullName -Raw -Encoding UTF8|ConvertFrom-Json
    if([string](Get-SafeProperty $ready 'candidate' '') -ne $ExpectedCandidate){throw 'READY_CANDIDATE_MISMATCH'}
    if([string](Get-SafeProperty $ready 'ready_branch' '') -ne $ExpectedReadyBranch){throw 'READY_BRANCH_MISMATCH'}
    if([string](Get-SafeProperty $ready 'frozen_product_commit' '') -ne $ExpectedFrozen){throw 'READY_FROZEN_COMMIT_MISMATCH'}
    if([string](Get-SafeProperty $ready 'frozen_tree' '') -ne $ExpectedFrozenTree){throw 'READY_FROZEN_TREE_MISMATCH'}

    return (Split-Path -Parent (Split-Path -Parent $readyFiles[0].FullName))
}

function Assert-CanonicalPackage([string]$StageRoot){
    $script:Phase='VERIFY_CANONICAL_READY_PACKAGE'
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
        if(-not(Test-Path -LiteralPath (Join-Path $StageRoot $req) -PathType Leaf)){ throw 'CANONICAL_PACKAGE_INCOMPLETE' }
    }

    if(-not(Test-GitBlob (Join-Path $StageRoot 'RELEASE_CANDIDATE.json') $ExpectedReleaseBlob)){throw 'RELEASE_MANIFEST_BLOB_MISMATCH'}
    if(-not(Test-GitBlob (Join-Path $StageRoot 'tests\test_windows_launcher_runtime.py') $ExpectedLauncherTestBlob)){throw 'LAUNCHER_TEST_BLOB_MISMATCH'}
    if(-not(Test-GitBlob (Join-Path $StageRoot 'tools\release_v080_rc3_builder.py') $ExpectedAdapterBlob)){throw 'RC3_ADAPTER_BLOB_MISMATCH'}
    if(-not(Test-GitBlob (Join-Path $StageRoot 'tools\release_v080_rc3_bootstrap.ps1') $ExpectedBootstrapBlob)){throw 'RC3_BOOTSTRAP_BLOB_MISMATCH'}
    if(-not(Test-GitBlob (Join-Path $StageRoot 'tools\release_v080_rc2_builder.py') $ExpectedBaseBuilderBlob)){throw 'BASE_BUILDER_BLOB_MISMATCH'}
    if(-not(Test-GitBlob (Join-Path $StageRoot 'START_HERE_WINDOWS.bat') $ExpectedStartHereBlob)){throw 'START_HERE_FROZEN_BLOB_MISMATCH'}
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

$ExtractRoot=$null
$ArchivePath=$null
try{
    $nonce=[Guid]::NewGuid().ToString('N').Substring(0,8)
    $ExtractRoot=Join-Path ([IO.Path]::GetTempPath()) ('TC3_'+$nonce)
    $ArchivePath=Join-Path ([IO.Path]::GetTempPath()) ('TC3_'+$nonce+'.zip')
    $Stage=Acquire-CanonicalReadyPackage $ExtractRoot $ArchivePath
    Assert-CanonicalPackage $Stage

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
    if(-not(Test-Path -LiteralPath $Build -PathType Leaf)){Write-JobResult 'FAIL' 'BUILD_RESULT_MISSING' @{builder_exit=$rc;release_pass=$false};exit 22}
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
        source_package='canonical-release-ready-download'
        source_ready_commit=$ExpectedReadyCommit
        frozen_source_verified_by_builder=$true
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
    try{if($ExtractRoot -and (Test-Path -LiteralPath $ExtractRoot)){Remove-Item -LiteralPath $ExtractRoot -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
    try{if($ArchivePath -and (Test-Path -LiteralPath $ArchivePath)){Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue}}catch{}
}
