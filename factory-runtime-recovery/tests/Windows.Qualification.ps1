param([string]$OutputDirectory,[string]$Nonce)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
# Phase A: disposable Spectre shadow fixtures; no installed Factory access.
$record=[ordered]@{schema='factory-windows-qualification-v2';nonce=$Nonce;qualification='UNVERIFIED';cleanup='UNVERIFIED';finished_utc=$null;exception_class='NONE';code='STARTING';tests_completed=0;status='HOLD';phase='PLATFORM';ps51=$false;windows11=$false;fixture_tests='UNVERIFIED';native_task='UNVERIFIED';identity='UNVERIFIED';spectre_pass=$false;factory_completion_pass=$false;package_manifest_sha256=$null;exception_line=0}
$taskName='TanukiQualification-'+[Guid]::NewGuid().ToString('N')
$registered=$false;$registrationAttempted=$false;$dir=$null;$shadow=$null;$shadowOwned=$false;$outputReady=$false
$originalTemp=$env:TEMP;$originalTmp=$env:TMP
function Save-Qualification {
    $record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputDirectory 'WINDOWS_QUALIFICATION.json') -Encoding UTF8
}
try {
    if($Nonce -notmatch '^[0-9a-f]{32}$'){throw 'QUALIFICATION_NONCE_REQUIRED'}
    if(-not $OutputDirectory){throw 'OUTPUT_DIRECTORY_REQUIRED'}
    $outputFull=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
    if($outputFull -ieq 'C:\TanukiFactory' -or $outputFull.StartsWith('C:\TanukiFactory\',[StringComparison]::OrdinalIgnoreCase)){throw 'OUTPUT_DIRECTORY_UNSAFE'}
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $outputReady=$true
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or $PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'WINDOWS_PS51_REQUIRED'}
    Save-Qualification
    $record.ps51=$true
    $record.package_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\PACKAGE_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $os=Get-CimInstance Win32_OperatingSystem
    if([int]$os.BuildNumber -lt 22000 -or [int]$os.ProductType -ne 1){throw 'WINDOWS11_CLIENT_REQUIRED'}
    $record.windows11=$true
    $shadow=Join-Path ([IO.Path]::GetTempPath()) ('TanukiFactoryQualification_'+$Nonce)
    if($shadow.StartsWith('C:\TanukiFactory\',[StringComparison]::OrdinalIgnoreCase)){throw 'SHADOW_DIRECTORY_UNSAFE'}
    if(Test-Path -LiteralPath $shadow){throw 'SHADOW_ROOT_ALREADY_EXISTS'}
    [void][IO.Directory]::CreateDirectory($shadow)
    $shadowOwned=$true
    $env:TEMP=$shadow;$env:TMP=$shadow
    $record.phase='PARSER';Save-Qualification
    foreach($psFile in @(Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -Filter '*.ps1' -Recurse)){
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($psFile.FullName,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'SHADOW_PARSER_FAILED'}
    }
    $record.phase='IDENTITY';Save-Qualification
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $account=New-Object Security.Principal.NTAccount($identity.Name)
    if($account.Translate([Security.Principal.SecurityIdentifier]).Value -ne $identity.User.Value){throw 'IDENTITY_ROUNDTRIP_FAILED'}
    $record.identity='PASS'
    $record.phase='FIXTURE_TESTS';Save-Qualification
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach($test in @('Windows.Preflight.ps1','Runtime.Smoke.ps1','RecoveryPolicy.Smoke.ps1','InstallerFailure.Smoke.ps1','InstallerTransaction.Smoke.ps1','ResultDelivery.Smoke.ps1','QualificationGate.Smoke.ps1','DeliveryPath.Smoke.ps1')){
        $record.phase=$test;Save-Qualification
        & $exe -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test) *> (Join-Path $OutputDirectory ($test+'.local.log'))
        if($LASTEXITCODE -ne 0){throw 'FIXTURE_TEST_FAILED'}
        $record.tests_completed++
    }
    $record.fixture_tests='PASS'
    $record.phase='NATIVE_TASK';Save-Qualification
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('日本語 Task Fixture '+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    $marker=Join-Path $dir 'started.txt';$scriptFile=Join-Path $dir 'task.ps1'
    $body="[IO.File]::WriteAllText('"+$marker.Replace("'","''")+"','STARTED'); Start-Sleep -Seconds 30; exit 7"
    [IO.File]::WriteAllText($scriptFile,$body,(New-Object Text.UTF8Encoding($true)))
    $action=New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$scriptFile+'"') -WorkingDirectory $dir
    $principal=New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Limited
    $registrationAttempted=$true
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -ErrorAction Stop|Out-Null
    $registered=$true
    Start-ScheduledTask -TaskName $taskName
    $deadline=[DateTime]::UtcNow.AddSeconds(25)
    while(-not (Test-Path -LiteralPath $marker)){
        if([DateTime]::UtcNow -gt $deadline){throw 'NATIVE_TASK_DID_NOT_RUN'}
        Start-Sleep -Milliseconds 200
    }
    if((Get-ScheduledTask -TaskName $taskName).State -ne 'Running'){throw 'NATIVE_TASK_RUNNING_NOT_OBSERVED'}
    [void](Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
    Stop-ScheduledTask -TaskName $taskName
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    while((Get-ScheduledTask -TaskName $taskName).State -eq 'Running'){
        if([DateTime]::UtcNow -gt $deadline){throw 'NATIVE_TASK_DID_NOT_STOP'}
        Start-Sleep -Milliseconds 200
    }
    $record.native_task='PASS';$record.phase='COMPLETE';$record.status='PASS';$record.code='QUALIFICATION_TESTS_PASSED'
} catch {
    $record.status='HOLD';$record.exception_line=[int]$_.InvocationInfo.ScriptLineNumber
    $record.exception_class=if($_.Exception -is [UnauthorizedAccessException]){'ACCESS_DENIED'}elseif($_.Exception -is [IO.IOException]){'IO_ERROR'}else{'OTHER'}
    $record.code=if($_.Exception.Message -in @('QUALIFICATION_NONCE_REQUIRED','OUTPUT_DIRECTORY_UNSAFE','SHADOW_DIRECTORY_UNSAFE','OUTPUT_DIRECTORY_REQUIRED','WINDOWS_PS51_REQUIRED','WINDOWS11_CLIENT_REQUIRED','SHADOW_ROOT_ALREADY_EXISTS','SHADOW_PARSER_FAILED','IDENTITY_ROUNDTRIP_FAILED','FIXTURE_TEST_FAILED','NATIVE_TASK_DID_NOT_RUN','NATIVE_TASK_RUNNING_NOT_OBSERVED','NATIVE_TASK_DID_NOT_STOP')){$_.Exception.Message}else{'SHADOW_QUALIFICATION_EXCEPTION'}
} finally {
    $clean=$true
    if($registrationAttempted){
        try{
            $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if($task){
                if($task.State -eq 'Running'){Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop}
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            }
            if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){throw 'Fixture task remains'}
        }catch{$clean=$false}
    }
    $env:TEMP=$originalTemp;$env:TMP=$originalTmp
    if($shadowOwned){try{Remove-Item -LiteralPath $shadow -Recurse -Force -ErrorAction Stop}catch{$clean=$false}}
    $record.cleanup=if($clean){'PASS'}else{'HOLD'}
    if(-not $clean){$record.status='HOLD';$record.code='SHADOW_CLEANUP_FAILED'}
    if($record.status -eq 'PASS' -and $clean){$record.qualification='WINDOWS_PS51_SHADOW_QUALIFICATION_PASS'}
    $record.finished_utc=[DateTime]::UtcNow.ToString('o')
    if($outputReady){try{Save-Qualification}catch{$record.status='HOLD'}}
}
if($record.status -ne 'PASS'){exit 1}
