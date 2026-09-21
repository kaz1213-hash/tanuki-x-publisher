Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Qualification.Fixture.ps1')
$base=Join-Path ([IO.Path]::GetTempPath()) ('復旧 fixture '+[Guid]::NewGuid().ToString('N'))
$assertions=0
function Assert($Condition,$Message){if(-not $Condition){throw $Message};$script:assertions++}
# Functions replace only platform/network operations and designated failure points.
# The installer, filesystem, JSON, byte-copy, lock and rollback logic are real.
function Get-FileHash {
    param($LiteralPath,$Algorithm)
    $content=[IO.File]::ReadAllText($LiteralPath)
    if($content -eq 'LEGACY_WATCHER'){return [pscustomobject]@{Hash='7efb360445ed41a9b9ca353e0c5fb37be988bb947975641cb01f6eeeaf4ef63a'}}
    if($content -eq 'LEGACY_COMMON'){return [pscustomobject]@{Hash='50ebb4ebcaf3c719b528f7fd1723e22b074c072ab4de57b9197195c35f79510a'}}
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256
}
function Get-ScheduledTask {param($TaskName) [pscustomobject]@{State=$ctx.task}}
function Stop-ScheduledTask {param($TaskName,$ErrorAction) $ctx.stops++;$ctx.task='Ready'}
function Start-ScheduledTask {
    param($TaskName,$ErrorAction)
    $ctx.starts++;$ctx.task='Running'
    if($ctx.case -eq 'START_AMBIGUOUS'){throw 'PRIVATE_SENTINEL'}
}
function Invoke-RestMethod {
    param([switch]$UseBasicParsing,$Uri,$TimeoutSec)
    if($Uri -eq 'http://fixture/descriptor'){return [pscustomobject]@{target_r2_head='203a2a3775dc06671de4733ec01cb9d4f503ce87';cipher_sha256='fixture'}}
    [pscustomobject]@{jobs=@([pscustomobject]@{job_id='clinic-cockpit-rc3-r2-20260921-001';target_factory_id='ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f';descriptor_url='http://fixture/descriptor'})}
}
function Copy-Item {
    param($LiteralPath,$Destination,[switch]$Force)
    if($ctx.case -eq 'BACKUP_FAIL' -and $Destination -like '*recovery-backup-*processed.json'){throw [IO.IOException]::new('PRIVATE_SENTINEL')}
    if($Destination -like '*.new'){$ctx.newCopies++}
    if($ctx.case -eq 'REPLACE_FAIL' -and $Destination -like '*.new' -and $ctx.newCopies -eq 2){$ctx.injected=$true;throw [IO.IOException]::new('PRIVATE_SENTINEL')}
    Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
}
try {
    foreach($case in @('SUCCESS','BACKUP_FAIL','REPLACE_FAIL','START_AMBIGUOUS','STATE_CHANGED','RECEIPT_FAIL')){
        $ctx=@{case=$case;task='Running';starts=0;stops=0;injected=$false;newCopies=0}
        $fixture=Join-Path $base $case
        $root=Join-Path $fixture 'Factory';$package=Join-Path $fixture 'Package';$out=Join-Path $fixture 'Result'
        foreach($dir in @('bin','STATE','WORK','OUTBOX')){[void][IO.Directory]::CreateDirectory((Join-Path $root $dir))}
        [void][IO.Directory]::CreateDirectory((Join-Path $package 'bin'))
        foreach($file in @(Get-ChildItem (Join-Path $PSScriptRoot '..\bin') -Filter '*.ps1')){
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $package ('bin/'+$file.Name))
        }
        [IO.File]::WriteAllText((Join-Path $root 'bin/TanukiFactoryWatcher.ps1'),'LEGACY_WATCHER')
        [IO.File]::WriteAllText((Join-Path $root 'bin/TanukiFactoryCommon.ps1'),'LEGACY_COMMON')
        $job='clinic-cockpit-rc3-r2-20260921-001'
        $legacyDir=Join-Path $root ('OUTBOX/'+$job);[void][IO.Directory]::CreateDirectory($legacyDir)
        @{schema='tanuki-windows-factory-result-v1';job_id=$job;status='FAIL';detail='HMACSHA256 argument count 32 overload fixture'}|ConvertTo-Json|Set-Content (Join-Path $legacyDir 'FACTORY_RESULT.json') -Encoding UTF8
        $remote=Join-Path $root ('WORK/remote_'+$job);[void][IO.Directory]::CreateDirectory($remote)
        [IO.File]::WriteAllBytes((Join-Path $remote 'payload.bin'),[byte[]](1,2,3,4))
        $processed=Join-Path $root 'STATE/processed.json'
        @{ $job='FAIL'; unrelated='PASS'}|ConvertTo-Json|Set-Content $processed -Encoding UTF8
        $originalProcessed=[IO.File]::ReadAllBytes($processed)
        @{factory_id='ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f';feed_url='http://fixture/feed'}|ConvertTo-Json|Set-Content (Join-Path $root 'config.json') -Encoding UTF8
        @'
param($OutputDirectory)
$decision=if($ctx.case -eq 'STATE_CHANGED' -and $ctx.stops -gt 0){'ACTIVE_ATTEMPT_REQUIRES_RECONCILIATION'}else{'ELIGIBLE_HMAC_PRESPAWN_REPAIR'}
[pscustomobject]@{repair_decision=$decision;facts=@{cipher_sha='fixture'}}
'@|Set-Content (Join-Path $package 'CollectFactoryEvidence.ps1') -Encoding UTF8
        $source=Get-Content (Join-Path $PSScriptRoot '..\ApplyVerifiedRecovery.ps1') -Raw
        $source=$source.Replace("`$root='C:\TanukiFactory'",("`$root='"+$root.Replace("'","''")+"'"))
        $source=$source.Replace("[Environment]::GetFolderPath('LocalApplicationData')", ("'"+(Join-Path $fixture 'Fallback').Replace("'","''")+"'"))
        $installer=Join-Path $package 'ApplyVerifiedRecovery.ps1';$source|Set-Content $installer -Encoding UTF8
        $qualificationArgs=New-QualificationFixtureReceipt $package
        if($case -eq 'RECEIPT_FAIL'){[IO.File]::WriteAllText($out,'not a directory')}
        $r=& $installer -OutputDirectory $out @qualificationArgs
        Assert ($r.status -eq 'HOLD') 'Installer may not assert product PASS'
        Assert (($r|ConvertTo-Json -Depth 16) -notmatch 'PRIVATE_SENTINEL') 'Raw exception exported'
        if($case -eq 'RECEIPT_FAIL'){
            Assert ($r.receipt_storage -eq 'FALLBACK' -and $ctx.stops -eq 0) 'Receipt failure did not stop mutation'
            continue
        }
        $receipt=Get-Content (Join-Path $out 'FACTORY_RECOVERY_INSTALL_RESULT.json') -Raw|ConvertFrom-Json
        Assert ($receipt.phase -eq $r.phase) 'Receipt phase mismatch'
        if($case -in @('SUCCESS','START_AMBIGUOUS')){
            Assert $r.installed 'Commit not marked installed'
            Assert (([IO.File]::ReadAllText((Join-Path $root 'bin/TanukiFactoryWatcher.ps1'))) -ne 'LEGACY_WATCHER') 'New watcher missing'
            $p=Get-Content $processed -Raw|ConvertFrom-Json
            Assert ($null -eq $p.PSObject.Properties[$job] -and $p.unrelated -eq 'PASS') 'Processed reconciliation changed other job'
            Assert ($ctx.starts -eq 1 -and $ctx.stops -eq 1) 'Task started twice'
            if($case -eq 'START_AMBIGUOUS'){
                Assert ($r.code -eq 'START_OUTCOME_REQUIRES_RECONCILIATION' -and $r.rollback -eq 'NOT_NEEDED') 'Ambiguous start rolled back without lock'
            }else{
                Assert ($r.code -eq 'INSTALLED_AWAITING_RUNTIME') 'Successful transaction not completed'
                $ctx.starts=0;$ctx.stops=0
                $again=& $installer -OutputDirectory (Join-Path $fixture 'Repeat') @qualificationArgs
                Assert ($again.code -eq 'PRIOR_RECOVERY_REQUIRES_RECONCILIATION' -and $ctx.stops -eq 0) 'Repeat overwrote existing transaction'
            }
        }else{
            Assert (-not $r.installed) 'Failed transaction installed'
            Assert (([IO.File]::ReadAllText((Join-Path $root 'bin/TanukiFactoryWatcher.ps1'))) -eq 'LEGACY_WATCHER') 'Legacy watcher not preserved'
            Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($processed)) -eq [Convert]::ToBase64String($originalProcessed)) 'Processed changed on failure'
            if($case -eq 'REPLACE_FAIL'){Assert ($r.rollback -eq 'PASS') 'Rollback failed'}
            if($case -eq 'BACKUP_FAIL'){Assert ($r.phase -eq 'BACKUP_PROCESSED' -and -not $r.backup_complete -and $r.backup_files_copied -eq 2) 'Partial backup evidence missing'}
            if($case -eq 'STATE_CHANGED'){Assert (-not $r.backup_complete -and $r.code -eq 'STATE_CHANGED_BEFORE_APPLY') 'State change reached backup'}
        }
    }
    "INSTALLER_TRANSACTION_PASS=$assertions"
} finally {Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue}
