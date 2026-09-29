$ErrorActionPreference = "Stop"

$Root = Join-Path $env:LOCALAPPDATA "TanukiXPublisher"
$Repo = Join-Path $Root "repo"
$SecretPath = Join-Path $Root "x-secrets.dpapi.json"
$StateDir = Join-Path $Root "placement-state"
$ScoutStatus = Join-Path $StateDir "last_scout_status.txt"
$Python = Join-Path $Repo ".venv\Scripts\python.exe"

function Unprotect([string]$Cipher) {
    $secure = ConvertTo-SecureString $Cipher
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

if (!(Test-Path $Repo)) { throw "LOCAL_REPO_MISSING" }
if (!(Test-Path $SecretPath)) { throw "X_SECRETS_NOT_CONFIGURED" }
if (!(Test-Path $Python)) { throw "LOCAL_VENV_MISSING" }
if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw "GH_CLI_MISSING" }

$secrets = Get-Content -LiteralPath $SecretPath -Raw | ConvertFrom-Json
$env:X_API_KEY = Unprotect $secrets.X_API_KEY
$env:X_API_SECRET = Unprotect $secrets.X_API_SECRET
$env:TANUKI_SOURCE_REPO = "kaz1213-hash/tanuki-growth"
$env:TANUKI_SCOUT_STATE_DIR = $StateDir

$ghToken = (& gh auth token 2>$null).Trim()
if (!$ghToken) { throw "GH_AUTH_TOKEN_UNAVAILABLE" }
$env:TANUKI_GROWTH_READ_TOKEN = $ghToken

try {
    Set-Location $Repo
    git pull --ff-only origin main | Out-Null
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

    & $Python scout.py
    if ($LASTEXITCODE -ne 0) {
        "FAILED" | Set-Content -LiteralPath $ScoutStatus -Encoding UTF8
        Write-Warning "Scout scan failed. Opening saved candidates / manual hunting-ground fallback."
    } else {
        "OK" | Set-Content -LiteralPath $ScoutStatus -Encoding UTF8
    }

    Start-Process -FilePath $Python -ArgumentList @("placement_console.py")
}
finally {
    Remove-Item Env:X_API_KEY,Env:X_API_SECRET,Env:TANUKI_GROWTH_READ_TOKEN -ErrorAction SilentlyContinue
}
