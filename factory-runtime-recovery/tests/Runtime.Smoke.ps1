$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\bin\TanukiFactoryCommon.ps1')
. (Join-Path $PSScriptRoot '..\bin\FactoryRuntime.ps1')
$script:FactoryRoot=Join-Path ([IO.Path]::GetTempPath()) ('factory-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:FactoryRoot -Force | Out-Null
$script:Passed=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:Passed++}
function MustThrow([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action}catch{$threw=$true};Assert $threw $Message}
try {
    # Synthetic RSA only. Never touch any installed private key / DPAPI store.
    $rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(2048)
    $rsa.PersistKeyInCsp=$false
    $script:TestPrivateXml=$rsa.ToXmlString($true)
    function Get-TanukiPrivateRsa {
        $r=[Security.Cryptography.RSACryptoServiceProvider]::new(2048)
        $r.PersistKeyInCsp=$false;$r.FromXmlString($script:TestPrivateXml);return $r
    }
    $keys=New-Object byte[] 64
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create();$rng.GetBytes($keys);$rng.Dispose()
    $aes=[Security.Cryptography.Aes]::Create()
    $aes.Key=[byte[]]$keys[0..31];$aes.GenerateIV()
    $plain=[Text.Encoding]::UTF8.GetBytes('synthetic canary test; no clinic data')
    $enc=$aes.CreateEncryptor();$cipher=$enc.TransformFinalBlock($plain,0,$plain.Length);$enc.Dispose()
    $hmac=New-Object Security.Cryptography.HMACSHA256
    $hmac.Key=[byte[]]$keys[32..63]
    $mac=$hmac.ComputeHash([byte[]]($aes.IV+$cipher));$hmac.Dispose()
    $cipherPath=Join-Path $script:FactoryRoot 'cipher.bin';$plainPath=Join-Path $script:FactoryRoot 'plain.bin'
    [IO.File]::WriteAllBytes($cipherPath,$cipher)
    [IO.File]::WriteAllBytes($plainPath,$plain)
    $d=[pscustomobject]@{cipher_sha256=(Get-TanukiSha256Hex $cipherPath);plain_sha256=(Get-TanukiSha256Hex $plainPath);encrypted_key_b64=[Convert]::ToBase64String($rsa.Encrypt($keys,$false));iv_b64=[Convert]::ToBase64String($aes.IV);hmac_b64=[Convert]::ToBase64String($mac)}
    Remove-Item -LiteralPath $plainPath
    Start-FactoryAttempt 'synthetic-test'
    Expand-TanukiEncryptedJob $d $cipherPath $plainPath
    Assert ((Get-TanukiSha256Hex $plainPath) -eq $d.plain_sha256) 'Roundtrip failed'
    Assert ($script:Attempt.phase -eq 'plaintext-zip-sha') 'Phase missing'
    Remove-Item -LiteralPath $plainPath
    $original=$d.hmac_b64;$bad=New-Object byte[] 32;$d.hmac_b64=[Convert]::ToBase64String($bad)
    MustThrow {Expand-TanukiEncryptedJob $d $cipherPath $plainPath} 'Tampered HMAC accepted'
    Assert (-not (Test-Path $plainPath)) 'Unauthenticated plaintext written'
    $d.hmac_b64=$original;$old=$d.cipher_sha256;$d.cipher_sha256='0'*64
    MustThrow {Expand-TanukiEncryptedJob $d $cipherPath $plainPath} 'Bad ciphertext hash accepted'
    $d.cipher_sha256=$old;$d.plain_sha256='0'*64
    MustThrow {Expand-TanukiEncryptedJob $d $cipherPath $plainPath} 'Bad plaintext hash accepted'
    Assert (-not (Test-Path $plainPath)) 'Mismatched plaintext retained'
    $status=Complete-FactoryAttempt 'HOLD' 'SYNTHETIC_FAILURE'
    Assert ($status -eq 'HOLD') 'Terminal state lost'
    $files=@(Get-ChildItem -LiteralPath (Join-Path $script:FactoryRoot 'OUTBOX') -Recurse -File)
    Assert (@($files|Where-Object {$_.Name -eq 'FACTORY_RESULT.json'}).Count -eq 1) 'Terminal JSON missing'
    Assert (@($files|Where-Object {$_.Extension -eq '.zip'}).Count -eq 1) 'Terminal ZIP missing'
    MustThrow {Start-FactoryAttempt '..\escape'} 'Traversal job accepted'
    Assert (-not (Test-TanukiSafeRelativePath '..\escape.cmd')) 'Traversal entrypoint accepted'
    $empty=Join-Path $script:FactoryRoot 'empty';New-Item -ItemType Directory -Path $empty|Out-Null
    Assert (-not (Test-FactoryCockpitResult $empty ([DateTime]::UtcNow))) 'No build result produced PASS'
    # Product acceptance must reject a missing gate, stale result and altered final ZIP.
    $zip=Join-Path $empty 'candidate.zip';[IO.File]::WriteAllText($zip,'synthetic artifact')
    $names=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
    $build=[ordered]@{schema='clinic-cockpit-no-github-windows-release-gate-v1';candidate='v0.8.0 RC3';frozen_commit='70ec03be3de89548bf61ceea2661bffb03dab18a';status='PASS';windows_candidate_pass=$true;steps=@($names|ForEach-Object {@{name=$_;status='PASS'}});output_zip='candidate.zip';output_zip_sha256=(Get-TanukiSha256Hex $zip)}
    $buildPath=Join-Path $empty 'BUILD_RESULT.json'
    Write-FactoryJson $buildPath $build
    Assert (Test-FactoryCockpitResult $empty ([DateTime]::UtcNow.AddMinutes(-1))) 'Complete synthetic gate rejected'
    foreach($name in $names){
        $build.steps=@($names|Where-Object {$_ -ne $name}|ForEach-Object {@{name=$_;status='PASS'}})
        Write-FactoryJson $buildPath $build
        Assert (-not (Test-FactoryCockpitResult $empty ([DateTime]::UtcNow.AddMinutes(-1)))) ('Missing gate accepted: '+$name)
    }
    $build.steps=@($names|ForEach-Object {@{name=$_;status='PASS'}})
    Write-FactoryJson $buildPath $build
    Assert (-not (Test-FactoryCockpitResult $empty ([DateTime]::UtcNow.AddMinutes(1)))) 'Stale result accepted'
    [IO.File]::WriteAllText($zip,'tampered')
    Assert (-not (Test-FactoryCockpitResult $empty ([DateTime]::UtcNow.AddMinutes(-1)))) 'Tampered final artifact accepted'
    # Compression failure must still leave a terminal JSON and HOLD.
    function Compress-Archive {throw 'injected disk/archive failure'}
    Start-FactoryAttempt 'archive-failure'
    $status=Complete-FactoryAttempt 'FAIL' 'TEST'
    Assert ($status -eq 'HOLD') 'Bundle failure not fail-closed'
    $active=Get-Content (Join-Path $script:FactoryRoot 'STATE\active-attempt.json') -Raw|ConvertFrom-Json
    Assert ($active.error_code -eq 'RESULT_BUNDLE_FAILED') 'Bundle failure unreported'
    Write-Output ('SMOKE_PASS='+$script:Passed)
} finally {
    if($rsa){$rsa.Dispose()};if($aes){$aes.Dispose()}
    Remove-Item -LiteralPath $script:FactoryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
