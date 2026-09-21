$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Join-Path ([IO.Path]::GetTempPath()) ('rc3-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root|Out-Null
try{
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path (Join-Path $PSScriptRoot 'JOB/RunClinicCockpit.ps1')),[ref]$t,[ref]$e)
foreach($name in @('Get-SafeProperty','Write-ExactStartHere','Git-BlobSha1')){
 $f=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $f.Extent.Text
}
. (Join-Path $PSScriptRoot 'JOB/CockpitAcceptance.ps1')
$start=Join-Path $root 'START_HERE_WINDOWS.bat';Write-ExactStartHere $start
if((Git-BlobSha1 $start) -ne '5be7c5c73d20122bdd3226d2f65d2275c066a1bd'){throw 'Frozen blob mismatch'}
$z=Join-Path $root 'candidate.zip';[IO.File]::WriteAllText($z,'synthetic')
$names=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
$valid=@{schema='clinic-cockpit-no-github-windows-release-gate-v1';candidate='v0.8.0 RC3';frozen_commit='bf640bc9a58c3810b2d8cadde46b142054a18f3f';status='PASS';windows_candidate_pass=$true;steps=@($names|ForEach-Object {@{name=$_;status='PASS'}});output_zip='candidate.zip';output_zip_sha256=(Get-FileHash $z).Hash}
function Clone{$valid|ConvertTo-Json -Depth 8|ConvertFrom-Json}
$b=Clone;if((Test-CockpitAcceptance $b $root 0) -ne $z){throw 'Valid fixture rejected'}
$count=2
foreach($change in @(
 {param($b)$b.output_zip_sha256=''},
 {param($b)$b.output_zip_sha256='0'*64},
 {param($b)$b.windows_candidate_pass='false'},
 {param($b)$b.candidate='v0.8.0 RC2'},
 {param($b)$b.schema='OTHER'},
 {param($b)$b.output_zip='../candidate.zip'},
 {param($b)$b.steps += $b.steps[0]},
 {param($b)$b.steps=$b.steps[1..5]},
 {param($b)$b.frozen_commit='33fffccf66ab66f4bf161af8f07797576a6379b7'}
)){$b=Clone;& $change $b;$rejected=$false;try{Test-CockpitAcceptance $b $root 0|Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'Invalid evidence accepted'};$count++}
$b=Clone;$b|Add-Member noteproperty error 'PRIVATE PATIENT PATH';$b.steps[0]|Add-Member noteproperty detail 'PRIVATE PATIENT PATH'
$s=Get-SafeBuildSummary $b|ConvertTo-Json -Depth 8
if($s -match 'PRIVATE|PATIENT|PATH'){throw 'Raw details leaked'};$count++
"ACCEPTANCE_AND_FROZEN_REPAIR_PASS=$count"
}finally{Remove-Item $root -Recurse -Force}
