# Read-only collector: no key access, no process/task mutation, no raw log export.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='C:\TanukiFactory'
$job='clinic-cockpit-rc3-r2-20260921-001'
$result=[ordered]@{schema='tanuki-factory-safe-diagnostic-v1';utc=[DateTime]::UtcNow.ToString('o');job_id=$job;status='HOLD';phase='UNKNOWN_AFTER_PAYLOAD_REQUEST';keys_collected=$false;medical_data_collected=$false;outbound_return_connected=$false;facts=@();error_codes=@()}
$dest=Join-Path $root ('OUTBOX\FactoryRecoveryEvidence_'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
function Fact([string]$Name,$Value){$result.facts+=@{name=$Name;value=$Value}}
try {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $remote=Join-Path $root ('WORK\remote_'+$job)
    $cipher=Join-Path $remote 'payload.bin';$plain=Join-Path $remote ($job+'.job.zip')
    Fact 'cipher_exists' (Test-Path -LiteralPath $cipher -PathType Leaf)
    if(Test-Path -LiteralPath $cipher -PathType Leaf){
        $hash=(Get-FileHash -LiteralPath $cipher -Algorithm SHA256).Hash.ToLowerInvariant()
        Fact 'cipher_sha_matches' ($hash -eq '5066f4b6ebcd3f80031438b1d096f87120c9a4cbdd913c95b7295bde89bfe3f1')
        if($hash -eq '5066f4b6ebcd3f80031438b1d096f87120c9a4cbdd913c95b7295bde89bfe3f1'){$result.phase='CIPHERTEXT_PRESENT_DECRYPT_UNCONFIRMED'}
    }
    if(Test-Path -LiteralPath $plain -PathType Leaf){
        $hash=(Get-FileHash -LiteralPath $plain -Algorithm SHA256).Hash.ToLowerInvariant()
        Fact 'plaintext_sha_matches' ($hash -eq '433b720dcf485cd90202ed1269e900fe5272ba555be8d51ce6f0cbec4b3cf764')
        if($hash -eq '433b720dcf485cd90202ed1269e900fe5272ba555be8d51ce6f0cbec4b3cf764'){$result.phase='PLAINTEXT_VERIFIED'}
    }
    $source=Join-Path $root ('WORK\'+$job+'\source')
    Fact 'source_directory_exists' (Test-Path -LiteralPath $source -PathType Container)
    Fact 'job_manifest_exists' (Test-Path -LiteralPath (Join-Path $source 'job.json') -PathType Leaf)
    $processed=Join-Path $root 'STATE\processed.json'
    if(Test-Path -LiteralPath $processed){
        $state=Get-Content -LiteralPath $processed -Raw -Encoding UTF8 | ConvertFrom-Json
        $p=$state.PSObject.Properties[$job]
        if($p){Fact 'legacy_processed_state' $(if($p.Value -in @('PASS','FAIL','HOLD')){[string]$p.Value}else{'OTHER'})}
    }
    $legacy=Join-Path $root ('OUTBOX\'+$job+'\FACTORY_RESULT.json')
    if(Test-Path -LiteralPath $legacy){
        $r=Get-Content -LiteralPath $legacy -Raw -Encoding UTF8 | ConvertFrom-Json
        Fact 'legacy_result_present' $true
        Fact 'legacy_result_status' $(if($r.status -in @('PASS','FAIL','HOLD')){[string]$r.status}else{'OTHER'})
        $result.phase='LEGACY_TERMINAL_PRESENT_PRODUCT_UNVERIFIED'
        # Never export exception text. Only classify known fixed strings locally.
        if($r.PSObject.Properties['detail']){
            $detail=[string]$r.detail
            foreach($pair in @(
                @('HMACSHA256','HMAC_CONSTRUCTOR_OR_VERIFY'),
                @('Ciphertext SHA256 mismatch','CIPHER_SHA_MISMATCH'),
                @('HMAC verification failed','HMAC_MISMATCH'),
                @('Decrypted job ZIP SHA256 mismatch','PLAIN_SHA_MISMATCH'),
                @('Key not valid','DPAPI_CONTEXT_FAILURE'),
                @('job.json is missing','JOB_MANIFEST_MISSING'),
                @('entrypoint is missing','ENTRYPOINT_MISSING'),
                @('timeout','JOB_TIMEOUT')
            )){if($detail -match [regex]::Escape($pair[0])){$result.error_codes+=$pair[1]}}
        }
    }
    $logs=Join-Path $root 'LOGS'
    $startFound=$false;$endFound=$false;$failFound=$false
    foreach($f in @(Get-ChildItem -LiteralPath $logs -Filter 'factory-*.log' -File -ErrorAction SilentlyContinue)){
        foreach($line in @(Get-Content -LiteralPath $f.FullName -Tail 2000 -Encoding UTF8)){
            if($line -like ('*START job='+$job+' *')){$startFound=$true}
            if($line -like ('*END job='+$job+' *')){$endFound=$true}
            if($line -like ('*REMOTE JOB FAIL job='+$job+' *')){$failFound=$true}
        }
    }
    Fact 'legacy_process_start_logged' $startFound
    Fact 'legacy_process_end_logged' $endFound
    Fact 'legacy_remote_failure_logged' $failFound
    try {
        $task=Get-ScheduledTask -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
        Fact 'task_state' ([string]$task.State)
        $info=Get-ScheduledTaskInfo -TaskName 'TanukiWindowsFactory' -ErrorAction Stop
        Fact 'task_last_result' ([long]$info.LastTaskResult)
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $owner=New-Object Security.Principal.NTAccount([string]$task.Principal.UserId)
        Fact 'task_user_matches_current_user' ($owner.Translate([Security.Principal.SecurityIdentifier]).Value -eq $sid)
    } catch {$result.error_codes+='TASK_STATE_UNAVAILABLE'}
    try {
        $processes=@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {$_.Name -in @('powershell.exe','cmd.exe','cscript.exe','python.exe') -and $_.CommandLine -like '*TanukiFactory*'})
        # Command lines are examined locally but never exported.
        Fact 'factory_process_count' $processes.Count
    } catch {$result.error_codes+='PROCESS_STATE_UNAVAILABLE'}
    Fact 'legacy_result_zip_exists' (Test-Path -LiteralPath (Join-Path $root ('OUTBOX\'+$job+'_RESULT.zip')) -PathType Leaf)
} catch {$result.error_codes+='COLLECTOR_INCOMPLETE'}
finally {
    # No PASS claim: this captures infrastructure evidence, not product acceptance.
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $path=Join-Path $dest 'FACTORY_DIAGNOSTIC.json'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    try {Compress-Archive -LiteralPath $path -DestinationPath ($dest+'.zip') -Force} catch {}
}
