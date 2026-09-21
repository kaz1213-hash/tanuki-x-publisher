Set-StrictMode -Version 2.0

function Get-TanukiFactoryConfig {
    $path = 'C:\TanukiFactory\config.json'
    if(-not (Test-Path $path -PathType Leaf)){ throw 'Factory config is missing.' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-TanukiPrivateRsa {
    Add-Type -AssemblyName System.Security
    $path = 'C:\TanukiFactory\KEYS\factory_private_key.dpapi'
    if(-not (Test-Path $path -PathType Leaf)){ throw 'Factory private key is missing.' }
    $protected = [Convert]::FromBase64String((Get-Content -LiteralPath $path -Raw -Encoding ASCII).Trim())
    $raw = [Security.Cryptography.ProtectedData]::Unprotect(
        $protected,
        $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $xml = [Text.Encoding]::UTF8.GetString($raw)
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(3072)
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString($xml)
    return $rsa
}

function Get-TanukiSha256Hex {
    param([string]$Path)
    if(-not (Test-Path $Path -PathType Leaf)){ throw ('Missing file for SHA256: ' + $Path) }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-TanukiLog {
    param([string]$Message,[string]$Level='INFO')
    $logDir='C:\TanukiFactory\LOGS'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $line = ('{0} [{1}] {2}' -f ([DateTime]::UtcNow.ToString('o')),$Level,$Message)
    Add-Content -LiteralPath (Join-Path $logDir ('factory-' + (Get-Date -Format 'yyyyMMdd') + '.log')) -Value $line -Encoding UTF8
}

function Test-TanukiSafeRelativePath {
    param([string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){ return $false }
    if([IO.Path]::IsPathRooted($Value)){ return $false }
    if($Value -match '(^|[\\/])\.\.([\\/]|$)'){ return $false }
    return $true
}

function Expand-TanukiEncryptedJob {
    param(
        [Parameter(Mandatory=$true)]$Descriptor,
        [Parameter(Mandatory=$true)][string]$CipherPath,
        [Parameter(Mandatory=$true)][string]$ZipOutPath
    )
    Set-FactoryPhase 'ciphertext-sha'
    $cipherSha = Get-TanukiSha256Hex $CipherPath
    if($cipherSha -ne ([string]$Descriptor.cipher_sha256).ToLowerInvariant()){
        throw 'Ciphertext SHA256 mismatch.'
    }

    Set-FactoryPhase 'rsa-key-access'
    $rsa = Get-TanukiPrivateRsa
    try {
        $encKey = [Convert]::FromBase64String([string]$Descriptor.encrypted_key_b64)
        Set-FactoryPhase 'rsa-unwrap'
        $keyMaterial = $rsa.Decrypt($encKey, $false)
    } finally {
        $rsa.Dispose()
    }
    if($keyMaterial.Length -ne 64){ throw 'Decrypted key material length mismatch.' }

    $aesKey = New-Object byte[] 32
    $macKey = New-Object byte[] 32
    [Array]::Copy($keyMaterial,0,$aesKey,0,32)
    [Array]::Copy($keyMaterial,32,$macKey,0,32)

    $iv = [Convert]::FromBase64String([string]$Descriptor.iv_b64)
    if($iv.Length -ne 16){ throw 'AES IV length mismatch.' }
    $cipher = [IO.File]::ReadAllBytes($CipherPath)

    Set-FactoryPhase 'hmac-verify'
    # Authenticate IV || ciphertext before decryption.
    $macInput = New-Object byte[] ($iv.Length + $cipher.Length)
    [Array]::Copy($iv,0,$macInput,0,$iv.Length)
    [Array]::Copy($cipher,0,$macInput,$iv.Length,$cipher.Length)
    $hmac = New-Object Security.Cryptography.HMACSHA256
    $hmac.Key = $macKey
    try {
        $actualMac = $hmac.ComputeHash($macInput)
    } finally {
        $hmac.Dispose()
    }
    $expectedMac = [Convert]::FromBase64String([string]$Descriptor.hmac_b64)
    if($actualMac.Length -ne $expectedMac.Length){ throw 'HMAC length mismatch.' }
    $diff = 0
    for($i=0;$i -lt $actualMac.Length;$i++){ $diff = $diff -bor ($actualMac[$i] -bxor $expectedMac[$i]) }
    if($diff -ne 0){ throw 'Encrypted job HMAC verification failed.' }

    Set-FactoryPhase 'aes-decrypt'
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.BlockSize = 128
    $aes.Mode = [Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $aesKey
    $aes.IV = $iv
    try {
        $decryptor = $aes.CreateDecryptor()
        try {
            $plain = $decryptor.TransformFinalBlock($cipher,0,$cipher.Length)
        } finally {
            $decryptor.Dispose()
        }
    } finally {
        $aes.Dispose()
    }

    Set-FactoryPhase 'plaintext-zip-sha'
    [IO.File]::WriteAllBytes($ZipOutPath,$plain)
    if(-not $Descriptor.plain_sha256){ throw 'Plaintext hash required.' }
    if($Descriptor.plain_sha256){
        $plainSha = Get-TanukiSha256Hex $ZipOutPath
        if($plainSha -ne ([string]$Descriptor.plain_sha256).ToLowerInvariant()){
            Remove-Item -LiteralPath $ZipOutPath -Force -ErrorAction SilentlyContinue
            throw 'Decrypted job ZIP SHA256 mismatch.'
        }
    }
}

