$ErrorActionPreference = "Stop"

$Root = Join-Path $env:LOCALAPPDATA "TanukiXPublisher"
$SecretPath = Join-Path $Root "x-secrets.dpapi.json"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function Read-And-Protect([string]$Label) {
    $secure = Read-Host $Label -AsSecureString
    if ($secure.Length -le 0) { throw "$Label is required." }
    return ConvertFrom-SecureString $secure
}

$payload = [ordered]@{
    version = 1
    protection = "DPAPI_CURRENT_USER"
    X_API_KEY = Read-And-Protect "X API Key"
    X_API_SECRET = Read-And-Protect "X API Secret"
    X_ACCESS_TOKEN = Read-And-Protect "X Access Token"
    X_ACCESS_TOKEN_SECRET = Read-And-Protect "X Access Token Secret"
}

$payload | ConvertTo-Json | Set-Content -LiteralPath $SecretPath -Encoding UTF8
Write-Output "TANUKI_X_SECRETS_STORED=DPAPI_CURRENT_USER"
Write-Output "SECRET_PATH=$SecretPath"
