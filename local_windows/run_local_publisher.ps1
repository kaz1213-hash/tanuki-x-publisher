$ErrorActionPreference = "Stop"

$Root = Join-Path $env:LOCALAPPDATA "TanukiXPublisher"
$Repo = Join-Path $Root "repo"
$SecretPath = Join-Path $Root "x-secrets.dpapi.json"
$LogDir = Join-Path $Root "logs"
$Python = Join-Path $Repo ".venv\Scripts\python.exe"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogPath = Join-Path $LogDir ("run-" + $stamp + ".log")

$mutex = New-Object System.Threading.Mutex($false, "Local\TanukiXPublisherSingleton")
if (-not $mutex.WaitOne(0)) {
    "ALREADY_RUNNING" | Tee-Object -FilePath $LogPath
    exit 0
}

function Unprotect([string]$Cipher) {
    $secure = ConvertTo-SecureString $Cipher
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

try {
    if (!(Test-Path $Repo)) { throw "LOCAL_REPO_MISSING" }
    if (!(Test-Path $SecretPath)) { throw "X_SECRETS_NOT_CONFIGURED" }
    if (!(Test-Path $Python)) { throw "LOCAL_VENV_MISSING" }
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw "GH_CLI_MISSING" }

    $secrets = Get-Content -LiteralPath $SecretPath -Raw | ConvertFrom-Json
    $env:X_API_KEY = Unprotect $secrets.X_API_KEY
    $env:X_API_SECRET = Unprotect $secrets.X_API_SECRET
    $env:X_ACCESS_TOKEN = Unprotect $secrets.X_ACCESS_TOKEN
    $env:X_ACCESS_TOKEN_SECRET = Unprotect $secrets.X_ACCESS_TOKEN_SECRET
    $env:TANUKI_SOURCE_REPO = "kaz1213-hash/tanuki-growth"

    $ghToken = (& gh auth token 2>$null).Trim()
    if (!$ghToken) { throw "GH_AUTH_TOKEN_UNAVAILABLE" }
    $env:TANUKI_GROWTH_READ_TOKEN = $ghToken

    Set-Location $Repo

    $dirtyOther = @(git status --porcelain | Where-Object { $_ -notmatch 'state/published\.jsonl$' })
    if ($dirtyOther.Count -gt 0) { throw "LOCAL_REPO_DIRTY_OUTSIDE_RECEIPT" }

    $receiptDirty = @(git status --porcelain -- state/published.jsonl)
    if ($receiptDirty.Count -gt 0) {
        git add state/published.jsonl
        git -c user.name="tanuki-x-local-publisher" -c user.email="local@users.noreply.github.com" commit -m "Recover Tanuki X local receipt [skip ci]"
        git push origin main
    }

    git pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) { throw "GIT_PULL_FAILED" }

    & $Python publisher.py 2>&1 | Tee-Object -FilePath $LogPath
    if ($LASTEXITCODE -ne 0) { throw "PUBLISHER_FAILED" }

    $receiptDirty = @(git status --porcelain -- state/published.jsonl)
    if ($receiptDirty.Count -gt 0) {
        git add state/published.jsonl
        git -c user.name="tanuki-x-local-publisher" -c user.email="local@users.noreply.github.com" commit -m "Record Tanuki X local publication [skip ci]"
        if ($LASTEXITCODE -ne 0) { throw "RECEIPT_COMMIT_FAILED" }
        git push origin main
        if ($LASTEXITCODE -ne 0) { throw "RECEIPT_PUSH_FAILED" }
        "RECEIPT_PUSHED=true" | Tee-Object -FilePath $LogPath -Append
    } else {
        "RECEIPT_PUSHED=false" | Tee-Object -FilePath $LogPath -Append
    }

    "TANUKI_X_LOCAL_RUN=PASS" | Tee-Object -FilePath $LogPath -Append
}
catch {
    ("TANUKI_X_LOCAL_RUN=FAIL " + $_.Exception.Message) | Tee-Object -FilePath $LogPath -Append
    exit 1
}
finally {
    Remove-Item Env:X_API_KEY,Env:X_API_SECRET,Env:X_ACCESS_TOKEN,Env:X_ACCESS_TOKEN_SECRET,Env:TANUKI_GROWTH_READ_TOKEN -ErrorAction SilentlyContinue
    try { $mutex.ReleaseMutex() | Out-Null } catch {}
    $mutex.Dispose()
}
