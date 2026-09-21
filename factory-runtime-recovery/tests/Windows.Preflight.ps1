Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or -not [Environment]::Is64BitProcess){throw 'Windows PS5.1 x64 required'}
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($name in @('Get-FileHash','Compress-Archive','Get-ScheduledTask','Get-ScheduledTaskInfo','Stop-ScheduledTask','Start-ScheduledTask','Get-CimInstance')){[void](Get-Command $name -ErrorAction Stop)}
# Synthetic DPAPI data only. No installed Factory key is read or changed.
$plain=[Text.Encoding]::UTF8.GetBytes('Tanuki synthetic current-user DPAPI probe')
$protected=[Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
$roundtrip=[Security.Cryptography.ProtectedData]::Unprotect($protected,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
if([Convert]::ToBase64String($plain) -ne [Convert]::ToBase64String($roundtrip)){throw 'Synthetic DPAPI failed'}
$form=New-Object Windows.Forms.Form
try{[void]$form.Handle}finally{$form.Dispose()}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('Tanuki 事前確認 '+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir|Out-Null
try {
    [IO.File]::WriteAllBytes((Join-Path $dir 'synthetic.dpapi'),$protected)
    $lockPath=Join-Path $dir 'exclusive.lock'
    $lock=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')
    try{
        $second=$null;$rejected=$false
        try{$second=[IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')}catch{$rejected=$true}
        if($second){$second.Dispose()}
        if(-not $rejected){throw 'Exclusive lock allowed second owner'}
    }finally{$lock.Dispose()}
    $script=Join-Path $dir '日本語 試験.ps1'
    [IO.File]::WriteAllText($script,'exit 7',[Text.Encoding]::ASCII)
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $p=Start-Process -FilePath $exe -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$script+'"') -WorkingDirectory $dir -RedirectStandardOutput (Join-Path $dir 'stdout.txt') -RedirectStandardError (Join-Path $dir 'stderr.txt') -WindowStyle Hidden -PassThru
    $handle=$p.Handle
    if(-not $p.WaitForExit(15000)){throw 'Synthetic process timeout'}
    $p.WaitForExit()
    if($p.ExitCode -ne 7){throw 'ExitCode or Unicode quoting failure'}
    $vbs=Join-Path $dir 'UnicodeStartup.vbs'
    [IO.File]::WriteAllText($vbs,'WScript.Quit 7',[Text.Encoding]::Unicode)
    $c=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cscript.exe') -ArgumentList ('//nologo "'+$vbs+'"') -WindowStyle Hidden -PassThru
    $h=$c.Handle
    if(-not $c.WaitForExit(15000)){throw 'WSH synthetic timeout'}
    $c.WaitForExit()
    if($c.ExitCode -ne 7){throw 'UTF16 startup launcher failed'}
    Write-Output 'WINDOWS_PS51_GENERIC_PREFLIGHT=PASS'
} finally {Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
