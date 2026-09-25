$ErrorActionPreference = "Stop"

$Root = Join-Path $env:LOCALAPPDATA "TanukiXPublisher"
$Repo = Join-Path $Root "repo"
$TaskName = "Tanuki X Local Publisher"

if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI (gh) is required." }
& gh auth status
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated." }

New-Item -ItemType Directory -Force -Path $Root | Out-Null

if (!(Test-Path (Join-Path $Repo ".git"))) {
    git clone https://github.com/kaz1213-hash/tanuki-x-publisher.git $Repo
    if ($LASTEXITCODE -ne 0) { throw "Clone failed." }
} else {
    git -C $Repo fetch origin main
    git -C $Repo checkout main
    git -C $Repo pull --ff-only origin main
}

$PythonLauncher = Get-Command py -ErrorAction SilentlyContinue
if (!$PythonLauncher) { throw "Python launcher (py) is required." }

if (!(Test-Path (Join-Path $Repo ".venv\Scripts\python.exe"))) {
    & py -3 -m venv (Join-Path $Repo ".venv")
}
$Python = Join-Path $Repo ".venv\Scripts\python.exe"
& $Python -m pip install --disable-pip-version-check -r (Join-Path $Repo "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "Dependency install failed." }

$SecretSetup = Join-Path $Repo "local_windows\setup_x_secrets.ps1"
$SecretPath = Join-Path $Root "x-secrets.dpapi.json"
if (!(Test-Path $SecretPath)) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SecretSetup
    if ($LASTEXITCODE -ne 0) { throw "Secret setup failed." }
}

$RunScript = Join-Path $Repo "local_windows\run_local_publisher.ps1"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $RunScript + '"')
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 30)
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Description "Zero-cost local Tanuki X publisher fallback while GitHub Actions is account-disabled." -Force | Out-Null

Write-Output "TANUKI_X_LOCAL_INSTALL=PASS"
Write-Output "TASK_NAME=$TaskName"
Write-Output "RUN_INTERVAL_MINUTES=30"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunScript
