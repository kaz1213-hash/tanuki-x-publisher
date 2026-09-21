Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
. 'C:\TanukiFactory\bin\TanukiFactoryCommon.ps1'
. 'C:\TanukiFactory\bin\FactoryRuntime.ps1'
. 'C:\TanukiFactory\bin\RecoveryPolicy.ps1'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$state=Join-Path $script:FactoryRoot 'STATE'
New-Item -ItemType Directory -Path $state -Force | Out-Null
try {$lock=[IO.File]::Open((Join-Path $state 'watcher.lock'),'OpenOrCreate','ReadWrite','None')} catch {exit 0}
try {
    while($true){
        try {
            Write-FactoryHeartbeat 'POLLING'
            # Previous terminal or interrupted attempt blocks automatic repeats/queue advancement.
            $active=Join-Path $state 'active-attempt.json'
            if(Test-Path -LiteralPath $active){
                $prior=Get-Content -LiteralPath $active -Raw -Encoding UTF8 | ConvertFrom-Json
                if($prior.status -eq 'RUNNING'){
                    $script:Attempt=[ordered]@{}
                    foreach($prop in $prior.PSObject.Properties){$script:Attempt[$prop.Name]=$prop.Value}
                    [void](Complete-FactoryAttempt 'HOLD' 'PREVIOUS_ATTEMPT_INTERRUPTED_RECONCILIATION_REQUIRED')
                }
                $script:Attempt=[ordered]@{}
                foreach($prop in $prior.PSObject.Properties){$script:Attempt[$prop.Name]=$prop.Value}
                if($script:Attempt.status -eq 'RUNNING'){$script:Attempt.status='HOLD'}
                Write-FactoryHeartbeat $script:Attempt.status
                Start-Sleep -Seconds 30
                continue
            }
            $config=Get-TanukiFactoryConfig
            if(-not [bool]$config.allow_remote_jobs){Start-Sleep -Seconds 30;continue}
            $script:LastPollUtc=[DateTime]::UtcNow.ToString('o')
            $feed=Invoke-RestMethod -UseBasicParsing -Uri ([string]$config.feed_url) -TimeoutSec 20
            if($feed.schema -ne 'tanuki-windows-factory-feed-v1'){throw 'Invalid feed.'}
            foreach($item in @($feed.jobs)){
                # Acceptance canary only. Never dispatch Comic/FX until completion gate is proven.
                if($item.job_id -ne 'clinic-cockpit-rc3-r2-20260921-001'){continue}
                if($item.target_factory_id -ne $config.factory_id){continue}
                if($item.PSObject.Properties['enabled'] -and -not $item.enabled){continue}
                $processed=Join-Path $state 'processed.json'
                if(Test-Path -LiteralPath $processed){
                    $old=Get-Content -LiteralPath $processed -Raw -Encoding UTF8 | ConvertFrom-Json
                    $legacy=$old.PSObject.Properties[[string]$item.job_id]
                    if($legacy){
                        Start-FactoryAttempt ([string]$item.job_id)
                        [void](Complete-FactoryAttempt 'HOLD' 'LEGACY_RESULT_REQUIRES_RECONCILIATION')
                        break
                    }
                }
                Start-FactoryAttempt ([string]$item.job_id)
                try {
                    Set-FactoryPhase 'descriptor-download'
                    $d=Invoke-RestMethod -UseBasicParsing -Uri ([string]$item.descriptor_url) -TimeoutSec 20
                    if($d.schema -ne 'tanuki-windows-factory-encrypted-job-v1' -or $d.job_id -ne $item.job_id -or $d.target_factory_id -ne $config.factory_id){throw 'Descriptor identity mismatch.'}
                    if($d.target_r2_head -ne '203a2a3775dc06671de4733ec01cb9d4f503ce87'){throw 'R2 identity mismatch.'}
                    if($d.cipher_sha256 -ne '5066f4b6ebcd3f80031438b1d096f87120c9a4cbdd913c95b7295bde89bfe3f1' -or $d.plain_sha256 -ne '433b720dcf485cd90202ed1269e900fe5272ba555be8d51ce6f0cbec4b3cf764'){throw 'Canary hash identity mismatch.'}
                    $dir=Join-Path $script:FactoryRoot ('WORK\remote_'+$item.job_id+'_'+$script:Attempt.attempt_id)
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    $cipher=Join-Path $dir 'payload.bin';$zip=Join-Path $dir 'payload.job.zip'
                    Set-FactoryPhase 'payload-download'
                    Invoke-WebRequest -UseBasicParsing -Uri ([string]$d.payload_url) -OutFile $cipher -TimeoutSec 120
                    Set-FactoryPhase 'payload-download-complete'
                    Expand-TanukiEncryptedJob $d $cipher $zip
                    $status=Invoke-TanukiJobPackage $zip ([string]$item.job_id)
                    [void](Complete-FactoryAttempt $status $(if($status -eq 'PASS'){'NONE'}else{'PRODUCT_GATE_NOT_PASS'}))
                } catch {
                    # Exception text may contain sensitive paths/data; keep it local to LOGS.
                    $failure=$_
                    $code='PHASE_EXCEPTION'
                    if($script:Attempt.error_code){$code=$script:Attempt.error_code}
                    [void](Complete-FactoryAttempt 'HOLD' $code)
                    try {Write-TanukiLog ('Attempt failure phase='+$script:Attempt.phase+' '+$failure.Exception.Message) 'ERROR'} catch {}
                }
                break
            }
        } catch {
            # Poll failures remain observable even without an accepted job.
            Write-FactoryJson (Join-Path $state 'watcher-heartbeat.json') @{schema='factory-liveness-v2';pid=$PID;utc=[DateTime]::UtcNow.ToString('o');state='HOLD';error_code='POLL_OR_STATE_FAILURE';remote_return_connected=$false}
        }
        Start-Sleep -Seconds 30
    }
} finally {$lock.Dispose()}
