# Synthetic receipt for a disposable installer copy only. Never targets real Factory.
function New-QualificationFixtureReceipt([string]$FixtureDirectory){
    $manifest=Join-Path $FixtureDirectory 'PACKAGE_MANIFEST.json'
    [IO.File]::WriteAllText($manifest,'{"schema":"synthetic-fixture-only","files":[]}')
    $nonce=[Guid]::NewGuid().ToString('N')
    $receipt=Join-Path $FixtureDirectory 'QUALIFICATION_FIXTURE.json'
    @{schema='factory-windows-qualification-v2';status='PASS';qualification='WINDOWS_PS51_SHADOW_QUALIFICATION_PASS';nonce=$nonce;ps51=$true;windows11=$true;fixture_tests='PASS';native_task='PASS';identity='PASS';cleanup='PASS';package_manifest_sha256=(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant();finished_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $receipt -Encoding UTF8
    return @{QualificationReceipt=$receipt;QualificationNonce=$nonce}
}
