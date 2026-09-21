Set-StrictMode -Version 2.0
function Assert-FactoryQualification([string]$ReceiptPath,[string]$ExpectedNonce,[string]$ManifestPath){
    if($ExpectedNonce -notmatch '^[0-9a-f]{32}$' -or -not $ReceiptPath -or -not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){throw 'SHADOW_QUALIFICATION_REQUIRED'}
    $file=Get-Item -LiteralPath $ReceiptPath
    if($file.Length -gt 64KB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'SHADOW_QUALIFICATION_INVALID'}
    $r=Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($field in @('schema','status','qualification','nonce','ps51','windows11','fixture_tests','native_task','identity','cleanup','package_manifest_sha256','finished_utc')){
        if(-not $r.PSObject.Properties[$field]){throw 'SHADOW_QUALIFICATION_INVALID'}
    }
    if($r.schema -ne 'factory-windows-qualification-v2' -or $r.nonce -cne $ExpectedNonce -or $r.status -cne 'PASS' -or $r.qualification -cne 'WINDOWS_PS51_SHADOW_QUALIFICATION_PASS'){throw 'SHADOW_QUALIFICATION_NOT_PASS'}
    if($r.ps51 -isnot [bool] -or -not $r.ps51 -or $r.windows11 -isnot [bool] -or -not $r.windows11){throw 'SHADOW_QUALIFICATION_INVALID'}
    foreach($field in @('fixture_tests','native_task','identity','cleanup')){if($r.$field -cne 'PASS'){throw 'SHADOW_QUALIFICATION_NOT_PASS'}}
    $hash=(Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($r.package_manifest_sha256 -cne $hash){throw 'SHADOW_QUALIFICATION_SOURCE_MISMATCH'}
    $finished=if($r.finished_utc -is [DateTime]){$r.finished_utc.ToUniversalTime()}else{[DateTimeOffset]::Parse([string]$r.finished_utc).UtcDateTime}
    $age=([DateTime]::UtcNow-$finished).TotalMinutes
    if($age -lt -1 -or $age -gt 30){throw 'SHADOW_QUALIFICATION_STALE'}
    return $r
}
