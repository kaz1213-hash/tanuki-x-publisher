Set-StrictMode -Version 2.0

function Protect-TanukiXSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$PlainText)
    $secure=ConvertTo-SecureString $PlainText -AsPlainText -Force
    return (ConvertFrom-SecureString $secure)
}

function Unprotect-TanukiXSecret {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$EncryptedText)
    $secure=ConvertTo-SecureString $EncryptedText
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}
    finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
}

function Get-TanukiXCredentialPath {
    [CmdletBinding()]
    param([string]$Path='')
    if(-not [string]::IsNullOrWhiteSpace($Path)){return [System.IO.Path]::GetFullPath($Path)}
    $base=$env:LOCALAPPDATA
    if([string]::IsNullOrWhiteSpace($base)){$base=$env:TEMP}
    return (Join-Path $base 'TanukiX\credentials.json')
}

function Save-TanukiXCredentialState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ApiKey,
        [Parameter(Mandatory=$true)][string]$ApiSecret,
        [Parameter(Mandatory=$true)][string]$AccessToken,
        [Parameter(Mandatory=$true)][string]$AccessTokenSecret,
        [string]$Path=''
    )
    foreach($value in @($ApiKey,$ApiSecret,$AccessToken,$AccessTokenSecret)){
        if([string]::IsNullOrWhiteSpace($value)){throw 'All four X API credentials are required.'}
    }
    $target=Get-TanukiXCredentialPath -Path $Path
    $dir=Split-Path -Parent $target
    if(-not (Test-Path $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
    $payload=[pscustomobject]@{
        Schema='tanuki-x-credentials/v0.1'
        ApiKey=(Protect-TanukiXSecret -PlainText $ApiKey)
        ApiSecret=(Protect-TanukiXSecret -PlainText $ApiSecret)
        AccessToken=(Protect-TanukiXSecret -PlainText $AccessToken)
        AccessTokenSecret=(Protect-TanukiXSecret -PlainText $AccessTokenSecret)
        SavedUtc=[DateTime]::UtcNow.ToString('o')
    }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $target -Encoding UTF8
    return $target
}

function Get-TanukiXCredentialState {
    [CmdletBinding()]
    param([string]$Path='')
    $target=Get-TanukiXCredentialPath -Path $Path
    if(-not (Test-Path $target -PathType Leaf)){return $null}
    $p=Get-Content -LiteralPath $target -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$p.Schema -ne 'tanuki-x-credentials/v0.1'){throw 'Unsupported Tanuki X credential schema.'}
    return [pscustomobject]@{
        ApiKey=(Unprotect-TanukiXSecret -EncryptedText ([string]$p.ApiKey))
        ApiSecret=(Unprotect-TanukiXSecret -EncryptedText ([string]$p.ApiSecret))
        AccessToken=(Unprotect-TanukiXSecret -EncryptedText ([string]$p.AccessToken))
        AccessTokenSecret=(Unprotect-TanukiXSecret -EncryptedText ([string]$p.AccessTokenSecret))
    }
}

Export-ModuleMember -Function Get-TanukiXCredentialPath,Save-TanukiXCredentialState,Get-TanukiXCredentialState
