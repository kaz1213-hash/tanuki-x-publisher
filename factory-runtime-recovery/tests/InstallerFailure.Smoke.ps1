Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Qualification.Fixture.ps1')
# Run the actual installer in a disposable fixture; no scheduled task or real Factory access.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('i_'+[Guid]::NewGuid().ToString('N').Substring(0,12))
New-Item -ItemType Directory -Path (Join-Path $fixture 'bin') -Force|Out-Null
try {
    Copy-Item (Join-Path $PSScriptRoot '..\bin\FactoryRuntime.ps1') (Join-Path $fixture 'bin')
    Copy-Item (Join-Path $PSScriptRoot '..\bin\QualificationPolicy.ps1') (Join-Path $fixture 'bin')
    $qualificationArgs=New-QualificationFixtureReceipt $fixture
    Copy-Item (Join-Path $PSScriptRoot '..\bin\RecoveryPolicy.ps1') (Join-Path $fixture 'bin')
    $source=Get-Content (Join-Path $PSScriptRoot '..\ApplyVerifiedRecovery.ps1') -Raw
    $source=$source.Replace("`$root='C:\TanukiFactory'",("`$root='"+$fixture.Replace("'","''")+"'"))
    $installer=Join-Path $fixture 'ApplyVerifiedRecovery.ps1'
    $source|Set-Content $installer -Encoding UTF8
    @'
param($OutputDirectory)
[pscustomobject]@{repair_decision='ELIGIBLE_HMAC_PRESPAWN_REPAIR';facts=@{cipher_sha='fixture'}}
'@|Set-Content (Join-Path $fixture 'CollectFactoryEvidence.ps1') -Encoding UTF8
    function Get-FileHash {
        param($LiteralPath,$Algorithm)
        if($LiteralPath -notlike '*Watcher.ps1' -and $LiteralPath -notlike '*Common.ps1'){return (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256)}
        $hash=if($LiteralPath -like '*Watcher.ps1'){'7efb360445ed41a9b9ca353e0c5fb37be988bb947975641cb01f6eeeaf4ef63a'}else{'50ebb4ebcaf3c719b528f7fd1723e22b074c072ab4de57b9197195c35f79510a'}
        if($LiteralPath -like '*Common.ps1'){$hash='50ebb4ebcaf3c719b528f7fd1723e22b074c072ab4de57b9197195c35f79510a'}
        [pscustomobject]@{Hash=$hash}
    }
    function Stop-ScheduledTask {throw 'TEST_UNEXPECTED_MUTATION'}
    function Start-ScheduledTask {throw 'TEST_UNEXPECTED_MUTATION'}
    function Invoke-RestMethod {
        param([switch]$UseBasicParsing,$Uri,$TimeoutSec)
        if($Uri -eq 'http://fixture/descriptor'){throw [Net.WebException]::new('PRIVATE_SENTINEL')}
        if($FailureCase -eq 'FEED_DOWNLOAD'){throw [Net.WebException]::new('PRIVATE_SENTINEL')}
        [pscustomobject]@{jobs=@([pscustomobject]@{job_id='clinic-cockpit-rc3-r2-20260921-001';target_factory_id='ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f';descriptor_url='http://fixture/descriptor'})}
    }
    foreach($case in @('CONFIG_READ','FEED_DOWNLOAD','DESCRIPTOR_DOWNLOAD')){
        $FailureCase=$case
        if($case -ne 'CONFIG_READ'){
            @{factory_id='ed813f7bf5ebbd7fabb4819b769ac2182116d41a7c172992dae03d4e4c4cf10f';feed_url='http://fixture/feed'}|ConvertTo-Json|Set-Content (Join-Path $fixture 'config.json')
        }
        $out=Join-Path $fixture $case
        $r=& $installer -OutputDirectory $out @qualificationArgs
        $raw=Get-Content (Join-Path $out 'INSTALL_RESULT.json') -Raw
        if($r.phase -ne $case){throw "Unexpected failure phase: $($r.phase), code $($r.code), line $($r.exception_line), expected $case"}
        if($r.installed -or $r.restart_performed -or $r.backup_complete -or $r.status -ne 'HOLD'){throw 'Failure mutated Factory'}
        if($r.exception_line -le 0 -or $raw.Contains('PRIVATE_SENTINEL') -or $raw.Contains($fixture)){throw 'Unsafe or missing exception evidence'}
        if($case -ne 'CONFIG_READ' -and $r.exception_class -ne 'HTTP_ERROR'){throw 'HTTP failure classification missing'}
    }
    'INSTALLER_FAILURE_PASS=3'
} finally {Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue}
