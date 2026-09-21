$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$LASTEXITCODE = 0
try { $Host.UI.RawUI.WindowTitle = "Clinic Cockpit v0.8.0 RC3 Builder" } catch {}

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutputDir = Join-Path $Root "RELEASE_OUTPUT_V080_RC3"
$ResultPath = Join-Path $OutputDir "BUILD_RESULT.json"
$ShaPath = Join-Path $OutputDir "SHA256.txt"
$PythonVersion = "3.12.10"
$LocalAppData = [Environment]::GetFolderPath("LocalApplicationData")
if (-not $LocalAppData) { throw "LocalApplicationData is unavailable. Windows per-user tool storage cannot be resolved." }

$PreferredToolRoot = Join-Path $LocalAppData "TanukiReleaseTools\Python31210"
$InstallerDir = Join-Path $LocalAppData "TanukiReleaseTools\installers"
$InstallerPath = Join-Path $InstallerDir "python-3.12.10-amd64.exe"
$InstallerLog = Join-Path $InstallerDir "python-3.12.10-install.log"
$InstallerUrl = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
$ExpectedInstallerBytes = 26964224
$CurrentStep = "bootstrap-init"

function Write-BootstrapFailure([string]$Detail) {
    New-Item -ItemType Directory -Force $OutputDir | Out-Null
    Get-ChildItem -Path $OutputDir -Filter "*.zip" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item $ShaPath -Force -ErrorAction SilentlyContinue
    $payload = [ordered]@{
        schema = "clinic-cockpit-no-github-windows-release-gate-v1"
        product = "Clinic Cockpit Lite"
        candidate = "v0.8.0 RC3"
        frozen_commit = "33fffccf66ab66f4bf161af8f07797576a6379b7"
        gate = "NO_GITHUB_WINDOWS_RELEASE_GATE"
        status = "FAIL"
        windows_candidate_pass = $false
        release_pass = $false
        director_debug_required = $false
        github_actions_used = $false
        failed_step = $CurrentStep
        detail = $Detail
        finished_utc = [DateTime]::UtcNow.ToString("o")
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $ResultPath
}

function Test-PythonCandidate([string]$Candidate) {
    if (-not $Candidate) { return $false }
    if (-not (Test-Path $Candidate -PathType Leaf)) { return $false }
    try {
        $actual = & $Candidate -c "import platform,struct; print(platform.python_version()); print(struct.calcsize('P')*8)" 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $lines = @($actual)
        return ($lines.Count -ge 2 -and $lines[0].Trim() -eq $PythonVersion -and $lines[1].Trim() -eq "64")
    } catch { return $false }
}

function Find-ExactPython {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $PreferredToolRoot "python.exe"))
    $candidates.Add((Join-Path $LocalAppData "Programs\Python\Python312\python.exe"))
    $candidates.Add((Join-Path $LocalAppData "Programs\Python\Python312-64\python.exe"))
    $registryKeys = @("HKCU:\Software\Python\PythonCore\3.12\InstallPath","HKLM:\Software\Python\PythonCore\3.12\InstallPath","HKLM:\Software\WOW6432Node\Python\PythonCore\3.12\InstallPath")
    foreach ($key in $registryKeys) {
        try {
            if (Test-Path $key) {
                $regKey = Get-Item $key
                $installPath = $regKey.GetValue("")
                $exePath = $regKey.GetValue("ExecutablePath")
                if ($installPath) { $candidates.Add((Join-Path ([string]$installPath) "python.exe")) }
                if ($exePath) { $candidates.Add([string]$exePath) }
            }
        } catch {}
    }
    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $key = $candidate.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (Test-PythonCandidate $candidate) { return $candidate }
    }
    return $null
}

try {
    New-Item -ItemType Directory -Force $OutputDir | Out-Null
    Get-ChildItem -Path $OutputDir -Filter "*.zip" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item $ShaPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ResultPath -Force -ErrorAction SilentlyContinue

    $CurrentStep = "python-bootstrap"
    Write-Host "[RUN] python-bootstrap"
    $PythonExe = Find-ExactPython
    if (-not $PythonExe) {
        New-Item -ItemType Directory -Force $InstallerDir | Out-Null
        New-Item -ItemType Directory -Force (Split-Path -Parent $PreferredToolRoot) | Out-Null
        $needDownload = $true
        if (Test-Path $InstallerPath) {
            $existing = Get-Item $InstallerPath
            if ($existing.Length -eq $ExpectedInstallerBytes) {
                $sig = Get-AuthenticodeSignature $InstallerPath
                if ($sig.Status -eq "Valid" -and $sig.SignerCertificate.Subject -match "Python Software Foundation") { $needDownload = $false }
            }
        }
        if ($needDownload) {
            $CurrentStep = "python-download"
            Write-Host "[RUN] download-python-3.12.10"
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing -Uri $InstallerUrl -OutFile $InstallerPath
            $downloaded = Get-Item $InstallerPath
            if ($downloaded.Length -ne $ExpectedInstallerBytes) { throw "Python installer size verification failed." }
            $sig = Get-AuthenticodeSignature $InstallerPath
            if ($sig.Status -ne "Valid") { throw "Python installer Authenticode signature is not valid." }
            if ($sig.SignerCertificate.Subject -notmatch "Python Software Foundation") { throw "Python installer signer is not Python Software Foundation." }
        }
        if (Test-Path $PreferredToolRoot) { Remove-Item $PreferredToolRoot -Recurse -Force }
        Remove-Item $InstallerLog -Force -ErrorAction SilentlyContinue
        $installArgs = @("/quiet","/log",$InstallerLog,"InstallAllUsers=0","Include_launcher=0","Include_pip=1","Include_test=0","PrependPath=0","AppendPath=0","Shortcuts=0","AssociateFiles=0","CompileAll=0",("TargetDir=" + $PreferredToolRoot))
        $CurrentStep = "python-install"
        Write-Host "[RUN] install-python-3.12.10"
        & $InstallerPath @installArgs
        $installerExit = $LASTEXITCODE
        if ($installerExit -ne 0 -and $installerExit -ne 3010) { throw "Python installer exit code: $installerExit" }
        $PythonExe = Find-ExactPython
        if (-not $PythonExe) { throw "Python 3.12.10 64-bit installation completed but no exact runtime was found." }
    }
    Write-Host "[PASS] python-bootstrap"

    $BuilderPath = Join-Path $Root "tools\release_v080_rc3_builder.py"
    $CurrentStep = "builder-syntax-gate"
    Write-Host "[RUN] builder-syntax-gate"
    & $PythonExe -m py_compile $BuilderPath
    if ($LASTEXITCODE -ne 0) { throw "Release builder Python syntax gate failed." }
    Write-Host "[PASS] builder-syntax-gate"

    $CurrentStep = "no-github-release-gate"
    Write-Host "[RUN] no-github-release-gate"
    & $PythonExe $BuilderPath
    $rc = $LASTEXITCODE
    if (Test-Path $OutputDir) { Start-Process explorer.exe $OutputDir | Out-Null }
    exit $rc
} catch {
    $safe = $_.Exception.GetType().Name + ": " + $_.Exception.Message
    Write-BootstrapFailure $safe
    if (Test-Path $OutputDir) { Start-Process explorer.exe $OutputDir | Out-Null }
    exit 1
}
