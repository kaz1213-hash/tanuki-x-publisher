param([string]$TestScript,[string]$ReceiptPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$r=[ordered]@{schema='factory-shadow-worker-v1';status='HOLD';code='WORKER_NOT_FINISHED';exception_class='NONE';exception_line=0;source='NONE'}
$allowed=@('Windows.Preflight.ps1','Runtime.Smoke.ps1','RecoveryPolicy.Smoke.ps1','InstallerFailure.Smoke.ps1','InstallerTransaction.Smoke.ps1','ResultDelivery.Smoke.ps1','QualificationGate.Smoke.ps1','DeliveryPath.Smoke.ps1','QualificationWorker.Smoke.ps1')
try {
    if([IO.Path]::GetFileName($TestScript) -notin $allowed){throw 'Unknown shadow test'}
    $global:LASTEXITCODE=0
    & $TestScript
    if($LASTEXITCODE -ne 0){throw 'SHADOW_TEST_EXIT_NONZERO'}
    $r.status='PASS';$r.code='SHADOW_TEST_PASS'
} catch {
    $r.code='SHADOW_TEST_EXCEPTION';$r.exception_line=[int]$_.InvocationInfo.ScriptLineNumber
    $name=[IO.Path]::GetFileName([string]$_.InvocationInfo.ScriptName)
    if($name -in ($allowed+@('FactoryRuntime.ps1','TanukiFactoryCommon.ps1','RecoveryPolicy.ps1','QualificationPolicy.ps1','ApplyVerifiedRecovery.ps1','RunRecovery.ps1'))){$r.source=$name}else{$r.source='OTHER'}
    $cause=$_.Exception
    for($depth=0;$cause -and $depth -lt 8;$depth++){
        $r.exception_class=if($cause -is [IO.PathTooLongException]){'PATH_TOO_LONG'}elseif($cause -is [UnauthorizedAccessException]){'ACCESS_DENIED'}elseif($cause -is [IO.DirectoryNotFoundException]){'DIRECTORY_NOT_FOUND'}elseif($cause -is [IO.IOException]){'IO_ERROR'}elseif($cause -is [Security.Cryptography.CryptographicException]){'CRYPTO_ERROR'}else{'OTHER'}
        if($r.exception_class -ne 'OTHER'){break};$cause=$cause.InnerException
    }
} finally {
    try{$r|ConvertTo-Json|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}catch{exit 2}
}
if($r.status -ne 'PASS'){exit 1}
