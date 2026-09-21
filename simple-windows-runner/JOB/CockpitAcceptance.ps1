function Test-CockpitAcceptance($Build,[string]$Release,[int]$ExitCode){
    $required=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
    if($ExitCode -ne 0){throw 'BUILDER_EXIT_NONZERO'}
    if((Get-SafeProperty $Build 'schema' '') -ne 'clinic-cockpit-no-github-windows-release-gate-v1'){throw 'BUILD_SCHEMA_MISMATCH'}
    if((Get-SafeProperty $Build 'candidate' '') -ne 'v0.8.0 RC3'){throw 'BUILD_CANDIDATE_MISMATCH'}
    if((Get-SafeProperty $Build 'frozen_commit' '') -ne 'bf640bc9a58c3810b2d8cadde46b142054a18f3f'){throw 'BUILD_FROZEN_MISMATCH'}
    $pass=Get-SafeProperty $Build 'windows_candidate_pass' $false
    if((Get-SafeProperty $Build 'status' '') -ne 'PASS' -or $pass -isnot [bool] -or -not $pass){throw 'WINDOWS_CANDIDATE_NOT_PASS'}
    foreach($name in $required){
        $matches=@(@(Get-SafeProperty $Build 'steps' @())|Where-Object {(Get-SafeProperty $_ 'name' '') -eq $name})
        if($matches.Count -ne 1 -or (Get-SafeProperty $matches[0] 'status' '') -ne 'PASS'){throw 'REQUIRED_GATE_NOT_PASS'}
    }
    $name=[string](Get-SafeProperty $Build 'output_zip' '')
    if(-not $name -or $name -match '[\\/:]' -or $name -in @('.','..') -or [IO.Path]::GetExtension($name) -ne '.zip'){throw 'FINAL_ZIP_NAME_INVALID'}
    $declared=[string](Get-SafeProperty $Build 'output_zip_sha256' '')
    if($declared -notmatch '^[0-9a-fA-F]{64}$'){throw 'FINAL_ZIP_SHA_REQUIRED'}
    $zip=Join-Path $Release $name
    if(-not (Test-Path -LiteralPath $zip -PathType Leaf)){throw 'FINAL_ZIP_MISSING'}
    $actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $declared.ToLowerInvariant()){throw 'FINAL_ZIP_SHA_MISMATCH'}
    return $zip
}

function Get-SafeBuildSummary($Build){
    $known=@('frozen-source-verification','integrated-source-completion-gate','windows-runtime-product-gate','portable-renamed-exe-runtime-gate','final-zip-extracted-runtime-gate','portable-privacy-scan')
    $steps=@(foreach($name in $known){
        $found=@(@(Get-SafeProperty $Build 'steps' @())|Where-Object {(Get-SafeProperty $_ 'name' '') -eq $name})
        $status='UNVERIFIED'
        if($found.Count -eq 1){$value=Get-SafeProperty $found[0] 'status' '';if($value -in @('PASS','FAIL','HOLD')){$status=$value}}
        @{name=$name;status=$status}
    })
    $status=Get-SafeProperty $Build 'status' ''
    if($status -notin @('PASS','FAIL','HOLD')){$status='UNVERIFIED'}
    $sha=[string](Get-SafeProperty $Build 'output_zip_sha256' '')
    if($sha -notmatch '^[0-9a-fA-F]{64}$'){$sha=$null}
    return @{schema='cockpit-safe-build-summary-v1';status=$status;steps=$steps;output_zip_sha256=$sha;release_pass=$false}
}
