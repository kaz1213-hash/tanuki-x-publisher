param([string]$OutputDirectory)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
# AI-owned disposable Windows 11 guest only; not a Director diagnostic launcher.
$record=[ordered]@{schema='factory-windows-qualification-v1';status='HOLD';phase='PLATFORM';ps51=$false;windows11=$false;fixture_tests='UNVERIFIED';native_task='UNVERIFIED';identity='UNVERIFIED';spectre_pass=$false;factory_completion_pass=$false;package_manifest_sha256=$null;exception_line=0}
$taskName='TanukiQualification-'+[Guid]::NewGuid().ToString('N')
$registered=$false;$dir=$null
try {
    if(-not $OutputDirectory){throw 'OUTPUT_DIRECTORY_REQUIRED'}
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or $PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'WINDOWS_PS51_REQUIRED'}
    $record.ps51=$true
    $record.package_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\PACKAGE_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $os=Get-CimInstance Win32_OperatingSystem
    if([int]$os.BuildNumber -lt 22000 -or [int]$os.ProductType -ne 1){throw 'WINDOWS11_CLIENT_REQUIRED'}
    $record.windows11=$true
    $record.phase='IDENTITY'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $account=New-Object Security.Principal.NTAccount($identity.Name)
    if($account.Translate([Security.Principal.SecurityIdentifier]).Value -ne $identity.User.Value){throw 'IDENTITY_ROUNDTRIP_FAILED'}
    $record.identity='PASS'
    $record.phase='FIXTURE_TESTS'
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach($test in @('Windows.Preflight.ps1','Runtime.Smoke.ps1','RecoveryPolicy.Smoke.ps1','InstallerFailure.Smoke.ps1','InstallerTransaction.Smoke.ps1','ResultDelivery.Smoke.ps1')){
        & $exe -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test) *> (Join-Path $OutputDirectory ($test+'.local.log'))
        if($LASTEXITCODE -ne 0){throw 'FIXTURE_TEST_FAILED'}
    }
    $record.fixture_tests='PASS'
    $record.phase='NATIVE_TASK'
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('日本語 Task Fixture '+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    $marker=Join-Path $dir 'started.txt';$scriptFile=Join-Path $dir 'task.ps1'
    $body="[IO.File]::WriteAllText('"+$marker.Replace("'","''")+"','STARTED'); Start-Sleep -Seconds 30; exit 7"
    [IO.File]::WriteAllText($scriptFile,$body,(New-Object Text.UTF8Encoding($true)))
    $action=New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$scriptFile+'"') -WorkingDirectory $dir
    $principal=New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Limited
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
    $record.native_task='PASS';$record.phase='COMPLETE';$record.status='PASS'
} catch {
    $record.status='HOLD';$record.exception_line=[int]$_.InvocationInfo.ScriptLineNumber
} finally {
    if($registered){try{Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop}catch{$record.status='HOLD';$record.phase='TASK_CLEANUP_FAILED'}}
    if($dir){Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
    if($OutputDirectory){try{$record|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputDirectory 'WINDOWS_QUALIFICATION.json') -Encoding UTF8}catch{}}
}
if($record.status -ne 'PASS'){exit 1}
