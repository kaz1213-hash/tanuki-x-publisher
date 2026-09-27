param([string]$StartupFolder='')
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($StartupFolder)){$StartupFolder=[Environment]::GetFolderPath('Startup')}
$launcher=Join-Path $StartupFolder 'TanukiXLocalPublisher.cmd'
if(Test-Path $launcher -PathType Leaf){Remove-Item -LiteralPath $launcher -Force}
Write-Host ('TANUKI_X_AUTOSTART_DISABLED '+$launcher)
