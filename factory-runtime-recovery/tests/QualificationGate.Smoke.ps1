Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\bin\QualificationPolicy.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\RunRecovery.ps1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-QualifiedFactoryRecovery'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$save=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-RunResult'},$true)
. ([scriptblock]::Create($save.Extent.Text))
$script:ExportResultsToDesktop=$false
function Set-RecoveryPhase($Phase,$State){$ctx.phases+=@($Phase)}
$base=Join-Path ([IO.Path]::GetTempPath()) ('資格 gate fixture '+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
$passed=0
try {
    $manifest=Join-Path $base 'PACKAGE_MANIFEST.json';[IO.File]::WriteAllText($manifest,'synthetic-manifest')
    $fake=Join-Path $base 'fake-qualifier.ps1'
    @'
param([switch]$NoProfile,[switch]$STA,[switch]$NonInteractive,$ExecutionPolicy,$File,$OutputDirectory,$Nonce)
$mode=Get-Content (Join-Path $PSScriptRoot 'case.txt') -Raw
if($mode -eq 'NO_RECEIPT'){exit 0}
$r=@{schema='factory-windows-qualification-v2';status='PASS';qualification='WINDOWS_PS51_SHADOW_QUALIFICATION_PASS';nonce=$Nonce;ps51=$true;windows11=$true;fixture_tests='PASS';native_task='PASS';identity='PASS';cleanup='PASS';package_manifest_sha256=(Get-FileHash (Join-Path $PSScriptRoot 'PACKAGE_MANIFEST.json')).Hash.ToLowerInvariant();finished_utc=[DateTime]::UtcNow.ToString('o')}
switch($mode){
    'FAIL_EXIT' {$r.status='HOLD'}
    'HOLD' {$r.status='HOLD'}
    'WRONG_NONCE' {$r.nonce='0'*32}
    'WRONG_SOURCE' {$r.package_manifest_sha256='0'*64}
    'STALE' {$r.finished_utc=[DateTime]::UtcNow.AddHours(-1).ToString('o')}
    'STRING_BOOLEAN' {$r.ps51='true'}
    'TASK_NOT_PASS' {$r.native_task='UNVERIFIED'}
    'CLEANUP_FAILED' {$r.cleanup='HOLD'}
}
$r|ConvertTo-Json|Set-Content (Join-Path $OutputDirectory 'WINDOWS_QUALIFICATION.json') -Encoding UTF8
if($mode -eq 'FAIL_EXIT'){exit 7}
exit 0
'@|Set-Content -LiteralPath $fake -Encoding UTF8
    @'
param($OutputDirectory)
$ctx.diagnostics++
[pscustomobject]@{repair_decision='ELIGIBLE_HMAC_PRESPAWN_REPAIR'}
'@|Set-Content (Join-Path $base 'CollectFactoryEvidence.ps1') -Encoding UTF8
    @'
param($OutputDirectory,$QualificationReceipt,$QualificationNonce)
$ctx.installs++
[pscustomobject]@{installed=$true;code='INSTALLED_AWAITING_RUNTIME'}
'@|Set-Content (Join-Path $base 'ApplyVerifiedRecovery.ps1') -Encoding UTF8
    foreach($mode in @('NO_RECEIPT','FAIL_EXIT','HOLD','WRONG_NONCE','WRONG_SOURCE','STALE','STRING_BOOLEAN','TASK_NOT_PASS','CLEANUP_FAILED','PASS')){
        $ctx=@{diagnostics=0;installs=0;phases=@()}
        $script:RunState=[ordered]@{qualification=$null;diagnostic=$null;install=$null;repair_applied=$false;windows_ps51_preflight='UNVERIFIED';status='RUNNING';code='START';started_utc=[DateTime]::UtcNow.ToString('o');finished_utc=$null;factory_completion_pass=$false}
        [IO.File]::WriteAllText((Join-Path $base 'case.txt'),$mode)
        $run=Join-Path $base $mode;[void][IO.Directory]::CreateDirectory($run)
        $script:RunDirectory=$run
        $threw=$false
        try{$r=Invoke-QualifiedFactoryRecovery $fake $base $run ([Guid]::NewGuid().ToString('N'))}catch{$threw=$true}
        if($mode -eq 'PASS'){
            if($threw -or $ctx.diagnostics -ne 1 -or $ctx.installs -ne 1 -or -not $script:RunState.repair_applied){throw 'Valid qualification never reached one repair'}
        }else{
            if(-not $threw -or $ctx.diagnostics -ne 0 -or $ctx.installs -ne 0 -or $script:RunState.repair_applied){throw ('Qualification failed open: '+$mode)}
            Save-RunResult 'HOLD' 'SHADOW_QUALIFICATION_NOT_PASS'
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $run 'RESULT.zip'))
            try{if($zip.Entries.Count -ne 1 -or $zip.Entries[0].FullName -ne 'FACTORY_RESULT.json'){throw 'Qualification failure return ZIP invalid'}}finally{$zip.Dispose()}
            $passed++
        }
        $passed++
    }
    # Direct installer invocation must also refuse to reach a real diagnostic without receipt.
    $direct=Join-Path $base 'direct';[void][IO.Directory]::CreateDirectory((Join-Path $direct 'bin'))
    foreach($name in @('FactoryRuntime.ps1','RecoveryPolicy.ps1','QualificationPolicy.ps1')){Copy-Item (Join-Path $PSScriptRoot ('..\bin\'+$name)) (Join-Path $direct 'bin')}
    Copy-Item (Join-Path $base 'CollectFactoryEvidence.ps1') $direct
    $source=Get-Content (Join-Path $PSScriptRoot '..\ApplyVerifiedRecovery.ps1') -Raw
    $source=$source.Replace("`$root='C:\TanukiFactory'",("`$root='"+$direct.Replace("'","''")+"'"))
    $source|Set-Content (Join-Path $direct 'ApplyVerifiedRecovery.ps1') -Encoding UTF8
    $ctx.diagnostics=0
    $r=& (Join-Path $direct 'ApplyVerifiedRecovery.ps1') -OutputDirectory (Join-Path $direct 'receipt')
    if($r.code -ne 'SHADOW_QUALIFICATION_REQUIRED' -or $ctx.diagnostics -ne 0 -or $r.installed){throw 'Direct installer bypassed qualification'}
    $passed++
    "QUALIFICATION_GATE_PASS=$passed"
} finally {Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue}
