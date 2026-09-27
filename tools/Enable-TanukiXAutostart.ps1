param([string]$StartupFolder='')

$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root 'tools\Run-TanukiXLocal.ps1'
if(-not (Test-Path $worker -PathType Leaf)){throw 'Tanuki X local worker was not found.'}
if([string]::IsNullOrWhiteSpace($StartupFolder)){$StartupFolder=[Environment]::GetFolderPath('Startup')}
if(-not (Test-Path $StartupFolder -PathType Container)){New-Item -ItemType Directory -Path $StartupFolder -Force | Out-Null}
$launcher=Join-Path $StartupFolder 'TanukiXLocalPublisher.cmd'
$line='@start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$worker+'" -Continuous -PollMinutes 15'
Set-Content -LiteralPath $launcher -Value $line -Encoding ASCII
Write-Host ('TANUKI_X_AUTOSTART_ENABLED '+$launcher)
