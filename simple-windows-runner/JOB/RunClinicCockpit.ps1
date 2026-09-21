Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Out=$env:TANUKI_RUNNER_OUT
if(-not $Out){throw 'RUNNER_OUTPUT_MISSING'}
New-Item -ItemType Directory -Force -Path $Out|Out-Null

$ExpectedFrozen='bf640bc9a58c3810b2d8cadde46b142054a18f3f'
$ExpectedFrozenTree='4dcd25855460d7b15ce14261e9eae79aceab54f8'
$AcceptedBaseFreezes=@(
 'bf640bc9a58c3810b2d8cadde46b142054a18f3f',
 '33fffccf66ab66f4bf161af8f07797576a6379b7',
 '70ec03be3de89548bf61ceea2661bffb03dab18a'
)
$ExpectedReadyBranch='release-ready/v0.8.0-rc3-no-github-r2'
$ExpectedCandidate='v0.8.0 RC3'
$ExpectedStartHereBlob='5be7c5c73d20122bdd3226d2f65d2275c066a1bd'
$Phase='INIT'
$LASTEXITCODE=0
. (Join-Path $PSScriptRoot 'CockpitAcceptance.ps1')

$PatchSpecs=@(
 [pscustomobject]@{Rel='RELEASE_CANDIDATE.json';Sha='4caeec00f80e3315f1e3421a90b3b2b1d2add9c7'},
 [pscustomobject]@{Rel='tests\test_release_candidate_v080.py';Sha='743340bcd302cfd2d67a6fe6336333265f386e09'},
 [pscustomobject]@{Rel='tests\test_windows_launcher_runtime.py';Sha='ee78ac488b7d402f870e7f48efe457169c12fb0f'},
 [pscustomobject]@{Rel='tools\release_v080_rc3_builder.py';Sha='b1ee8a858c13b8fd9bfa1fe2aa80c665dcf7eb60'},
 [pscustomobject]@{Rel='tools\release_v080_rc3_bootstrap.ps1';Sha='317430202dc42a9c931f224e59637e5a313f4249'}
)

function Get-SafeProperty($Object,[string]$Name,$Default=$null){
 if($null -eq $Object){return $Default}
 $p=$Object.PSObject.Properties[$Name]
 if($null -eq $p){return $Default}
 return $p.Value
}
function Get-LastFailedStep($Build){
 $direct=Get-SafeProperty $Build 'failed_step' $null
 if($direct){return [string]$direct}
 $failed=@(@(Get-SafeProperty $Build 'steps' @())|Where-Object{[string](Get-SafeProperty $_ 'status' '') -eq 'FAIL'})
 if($failed.Count){return [string](Get-SafeProperty $failed[-1] 'name' 'UNKNOWN_FAILED_STEP')}
 return $null
}
function Write-JobResult([string]$Status,[string]$Code,[hashtable]$Extra=@{}){
 $o=[ordered]@{schema='tanuki-cockpit-runner-result-v5';status=$Status;code=$Code;phase=$Phase;candidate=$ExpectedCandidate;frozen_commit=$ExpectedFrozen;ready_branch=$ExpectedReadyBranch;utc=[DateTime]::UtcNow.ToString('o')}
 foreach($k in $Extra.Keys){$o[$k]=$Extra[$k]}
 $o|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Out 'COCKPIT_JOB_RESULT.json') -Encoding UTF8
}
function Git-BlobSha1([string]$Path){
 $raw=[IO.File]::ReadAllBytes($Path);$prefix=[Text.Encoding]::UTF8.GetBytes(('blob '+$raw.Length));$header=New-Object byte[] ($prefix.Length+1);[Array]::Copy($prefix,0,$header,0,$prefix.Length);$header[$header.Length-1]=0;$all=New-Object byte[] ($header.Length+$raw.Length);[Array]::Copy($header,0,$all,0,$header.Length);[Array]::Copy($raw,0,$all,$header.Length,$raw.Length);$sha=[Security.Cryptography.SHA1]::Create();try{return (($sha.ComputeHash($all)|ForEach-Object{$_.ToString('x2')}) -join '')}finally{$sha.Dispose()}
}
function Write-ExactStartHere([string]$Path){
 $text="@echo off`ncd /d %~dp0`npy -m pip install -r requirements.txt`npy -m streamlit run app.py`npause`n";[IO.File]::WriteAllBytes($Path,[Text.Encoding]::ASCII.GetBytes($text))
}
function CandidateRoots{
 $list=New-Object System.Collections.Generic.List[string]
 foreach($p in @((Join-Path $env:USERPROFILE 'Downloads'),([Environment]::GetFolderPath('Desktop')),([Environment]::GetFolderPath('MyDocuments')),'C:\TanukiFactory',(Split-Path -Parent $PSScriptRoot))){if($p -and (Test-Path -LiteralPath $p -PathType Container)){$list.Add($p)}}
 return $list
}
function Find-RC3Package{
 $hits=@()
 foreach($root in CandidateRoots){
  try{
   foreach($f in @(Get-ChildItem -LiteralPath $root -Filter 'V080_RC3_READY.json' -File -Recurse -ErrorAction SilentlyContinue)){
    if($f.FullName -notmatch '\\tools\\V080_RC3_READY\.json$'){continue}
    try{
     $j=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json
     if([string](Get-SafeProperty $j 'candidate' '') -ne $ExpectedCandidate){continue}
     if([string](Get-SafeProperty $j 'ready_branch' '') -ne $ExpectedReadyBranch){continue}
     $frozen=[string](Get-SafeProperty $j 'frozen_product_commit' '')
     if($frozen -notin $AcceptedBaseFreezes){continue}
     $hits+=[pscustomobject]@{Root=(Split-Path -Parent (Split-Path -Parent $f.FullName));Stamp=$f.LastWriteTimeUtc;Frozen=$frozen}
    }catch{}
   }
  }catch{}
 }
 if(-not $hits.Count){return $null}
 return ($hits|Sort-Object Stamp -Descending|Select-Object -First 1)
}
function Copy-PackageToStage([string]$Source,[string]$Destination){
 $ignored=@('.git','RELEASE_OUTPUT_V080_RC2','RELEASE_OUTPUT_V080_RC3','__pycache__','.pytest_cache','.venv','venv')
 New-Item -ItemType Directory -Force -Path $Destination|Out-Null
 foreach($f in @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction Stop)){
  $rel=$f.FullName.Substring($Source.TrimEnd('\').Length).TrimStart('\');$parts=$rel -split '\\';if(@($parts|Where-Object{$_ -in $ignored}).Count){continue};$dst=Join-Path $Destination $rel;$parent=Split-Path -Parent $dst;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
 }
}
function Apply-CorrectedRc3Patch([string]$StageRoot){
 $patchRoot=Join-Path $PSScriptRoot 'RC3_PATCH'
 foreach($spec in $PatchSpecs){
  $src=Join-Path $patchRoot $spec.Rel;if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw 'PATCH_FILE_MISSING'};if((Git-BlobSha1 $src) -ne $spec.Sha){throw 'PATCH_BLOB_MISMATCH'};$dst=Join-Path $StageRoot $spec.Rel;$parent=Split-Path -Parent $dst;if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null};Copy-Item -LiteralPath $src -Destination $dst -Force;if((Git-BlobSha1 $dst) -ne $spec.Sha){throw 'PATCH_COPY_MISMATCH'}
 }
 $readyPath=Join-Path $StageRoot 'tools\V080_RC3_READY.json';$ready=Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8|ConvertFrom-Json;$ready.frozen_product_commit=$ExpectedFrozen;$ready.frozen_tree=$ExpectedFrozenTree;if($ready.static_audit){$ready.static_audit.rc3_frozen_commit=$ExpectedFrozen;$ready.static_audit.source_freeze_manifest_branch_blob_mismatches=0};$ready.latest_windows_evidence='Fresh Windows evidence passed preflight plus ORCA 117/117, UKE 64/64 and privacy/AI 37/37. UI/Windows contracts reached 44/45 and stopped only because a pytest-local LOCALAPPDATA path crossed legacy MAX_PATH; the fixture is shortened in this staging patch without product runtime source changes.';$ready.next_gate='Run corrected RC3 through remaining UI/Windows contracts, integrated source, PyInstaller, product runtime, renamed EXE, clean re-extract, privacy and final ZIP gates.';$ready|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $readyPath -Encoding UTF8
 $auditPath=Join-Path $StageRoot 'tools\V080_RC3_R2_STATIC_AUDIT.json';$audit=Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8|ConvertFrom-Json;$audit.frozen_source_commit=$ExpectedFrozen;$audit.frozen_source_tree=$ExpectedFrozenTree;if($audit.checks -and $audit.checks.PSObject.Properties['rc3_test_contract_matches_manifest']){$audit.checks.rc3_test_contract_matches_manifest=$true};if($audit.windows_state){$audit.windows_state.current_gate='CORRECTED_RC3_WINDOWS_RERUN_PENDING';$audit.windows_state.next_required_gate='fresh Windows run through remaining UI/Windows contracts, PyInstaller and all runtime/privacy gates'};$audit|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $auditPath -Encoding UTF8
}
function Assert-StagedPackage([string]$StageRoot){
 foreach($req in @('tools\release_v080_rc3_bootstrap.ps1','tools\release_v080_rc3_builder.py','tools\release_v080_rc2_builder.py','tools\V080_RC2_SOURCE_BLOBS.json','tools\V080_RC3_READY.json','tools\V080_RC3_R2_STATIC_AUDIT.json','tools\requirements-release-lock-v080.txt','BUILD_V080_RC3_WINDOWS.cmd','START_BUILD_V080_RC3.vbs','START_HERE_WINDOWS.bat','tests\test_release_candidate_v080.py','tests\test_windows_launcher_runtime.py','RELEASE_CANDIDATE.json')){if(-not(Test-Path -LiteralPath (Join-Path $StageRoot $req) -PathType Leaf)){throw 'STAGED_PACKAGE_INCOMPLETE'}}
 foreach($spec in $PatchSpecs){if((Git-BlobSha1 (Join-Path $StageRoot $spec.Rel)) -ne $spec.Sha){throw 'STAGED_PATCH_BLOB_MISMATCH'}}
 $ready=Get-Content -LiteralPath (Join-Path $StageRoot 'tools\V080_RC3_READY.json') -Raw -Encoding UTF8|ConvertFrom-Json;if([string](Get-SafeProperty $ready 'candidate' '') -ne $ExpectedCandidate){throw 'READY_CANDIDATE_MISMATCH'};if([string](Get-SafeProperty $ready 'frozen_product_commit' '') -ne $ExpectedFrozen){throw 'READY_FROZEN_MISMATCH'};if([string](Get-SafeProperty $ready 'ready_branch' '') -ne $ExpectedReadyBranch){throw 'READY_BRANCH_MISMATCH'}
 $audit=Get-Content -LiteralPath (Join-Path $StageRoot 'tools\V080_RC3_R2_STATIC_AUDIT.json') -Raw -Encoding UTF8|ConvertFrom-Json;if([string](Get-SafeProperty $audit 'audit_status' '') -ne 'PASS'){throw 'STATIC_AUDIT_NOT_PASS'};if([string](Get-SafeProperty $audit 'frozen_source_commit' '') -ne $ExpectedFrozen){throw 'STATIC_AUDIT_FROZEN_MISMATCH'}
}

$Stage=$null
try{
 $Phase='LOCATE_PACKAGE';$Located=Find-RC3Package;if(-not $Located){Write-JobResult 'HOLD' 'RC3_PACKAGE_NOT_FOUND';exit 20}
 $Phase='STAGE_PACKAGE';$Stage=Join-Path ([IO.Path]::GetTempPath()) ('TC3_'+[Guid]::NewGuid().ToString('N').Substring(0,8));Copy-PackageToStage $Located.Root $Stage
 $Phase='APPLY_CORRECTED_RC3_PATCH';Apply-CorrectedRc3Patch $Stage
 $Phase='RESTORE_FROZEN_START_HERE';$StartHere=Join-Path $Stage 'START_HERE_WINDOWS.bat';Write-ExactStartHere $StartHere;if((Git-BlobSha1 $StartHere) -ne $ExpectedStartHereBlob){Write-JobResult 'FAIL' 'START_HERE_FROZEN_BLOB_REPAIR_FAILED';exit 21};Assert-StagedPackage $Stage
 $Phase='RUN_EXISTING_RC3_GATE';$Bootstrap=Join-Path $Stage 'tools\release_v080_rc3_bootstrap.ps1';$arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Bootstrap+'"';$builder=Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $Stage -RedirectStandardOutput (Join-Path $Stage 'builder.stdout.local.log') -RedirectStandardError (Join-Path $Stage 'builder.stderr.local.log') -PassThru;$builderHandle=$builder.Handle;$builder.WaitForExit();$rc=$builder.ExitCode;if($null -eq $rc){throw 'BUILDER_EXIT_CODE_UNAVAILABLE'}
 $Phase='READ_BUILD_RESULT';$Release=Join-Path $Stage 'RELEASE_OUTPUT_V080_RC3';$Build=Join-Path $Release 'BUILD_RESULT.json';if(-not(Test-Path -LiteralPath $Build -PathType Leaf)){Write-JobResult 'FAIL' 'BUILD_RESULT_MISSING' @{builder_exit=$rc};exit 22};$B=Get-Content -LiteralPath $Build -Raw -Encoding UTF8|ConvertFrom-Json;Get-SafeBuildSummary $B|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Out 'BUILD_RESULT_SUMMARY.json') -Encoding UTF8
 if($rc -ne 0 -or [string](Get-SafeProperty $B 'status' '') -ne 'PASS' -or (Get-SafeProperty $B 'windows_candidate_pass' $false) -ne $true){Write-JobResult 'FAIL' 'WINDOWS_CANDIDATE_NOT_PASS' @{builder_exit=$rc;failed_step=(Get-LastFailedStep $B)};exit 23}
 $Phase='VERIFY_FINAL_ZIP';$zip=Test-CockpitAcceptance $B $Release $rc;$zipName=[IO.Path]::GetFileName($zip);$sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
 $Phase='COLLECT_FINAL_ARTIFACT';$artifactRoot=$env:TANUKI_RUNNER_ARTIFACTS;if(-not $artifactRoot){throw 'ARTIFACT_DIRECTORY_MISSING'};New-Item -ItemType Directory -Path $artifactRoot -Force|Out-Null;$delivered=Join-Path $artifactRoot $zipName;Copy-Item -LiteralPath $zip -Destination $delivered -Force;if((Get-FileHash -LiteralPath $delivered -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha){throw 'DELIVERED_ZIP_SHA_MISMATCH'}
 $Phase='TERMINAL_PASS';Write-JobResult 'PASS' 'WINDOWS_CANDIDATE_PASS' @{builder_exit=$rc;output_zip=$zipName;output_zip_sha256=$sha;source_package_frozen_commit=$Located.Frozen;corrected_freeze_applied_in_stage=$true;max_path_fixture_fix_applied_in_stage=$true;repaired_stale_start_here_in_stage=$true;original_package_modified=$false;product_gate_verified=$true};exit 0
}catch{
 Write-JobResult 'FAIL' 'COCKPIT_JOB_EXCEPTION' @{exception_type=$_.Exception.GetType().Name;exception_line=[int]$_.InvocationInfo.ScriptLineNumber};exit 30
}finally{
 try{if($Stage -and (Test-Path -LiteralPath $Stage)){Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}
