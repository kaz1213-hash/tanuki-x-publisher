param([string]$Root='C:\TanukiFactory',[string]$SessionDirectory='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$mutex=New-Object Threading.Mutex($false,'Local\TanukiFactoryStatusV2')
if(-not $mutex.WaitOne(0)){exit 0}
$form=New-Object Windows.Forms.Form
$form.Text='Tanuki Spectre Factory';$form.Width=650;$form.Height=400
$form.StartPosition='CenterScreen'
$label=New-Object Windows.Forms.Label
$label.Dock='Fill';$label.Padding=New-Object Windows.Forms.Padding(20)
$label.Font=New-Object Drawing.Font('Yu Gothic UI',11)
$form.Controls.Add($label)
$tray=New-Object Windows.Forms.NotifyIcon
$tray.Icon=[Drawing.SystemIcons]::Information;$tray.Text='Tanuki Factory';$tray.Visible=$true
$tray.add_DoubleClick({$form.Show();$form.WindowState='Normal'})
$form.add_Resize({if($form.WindowState -eq 'Minimized'){$form.Hide()}})
$script:lastTransition='';$script:firstTick=$true
$timer=New-Object Windows.Forms.Timer;$timer.Interval=2000
$timer.add_Tick({
    try {
        $state='WAITING';$phase='診断・適用準備';$job='Clinic Cockpit RC3';$lastPoll='未確認';$alive='未確認';$returnText='結果は返却用ZIPにまとめます（自動送信なし）'
        $path=Join-Path $Root 'STATE\watcher-heartbeat.json'
        if(Test-Path -LiteralPath $path){
            $h=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
            $age=([DateTime]::UtcNow-[DateTime]::Parse([string]$h.utc).ToUniversalTime()).TotalSeconds
            $alive=if($age -ge 0 -and $age -lt 90){'稼働確認'}else{'応答が古い／確認待ち'}
            if($h.state -in @('RUNNING','POLLING','PASS','FAIL','HOLD')){$state=[string]$h.state}
            if($h.PSObject.Properties['phase'] -and [string]$h.phase -match '^[a-z-]{1,64}$'){$phase=[string]$h.phase}
            if($h.PSObject.Properties['last_poll_utc'] -and $h.last_poll_utc){$lastPoll=([DateTime]::Parse([string]$h.last_poll_utc)).ToLocalTime().ToString('HH:mm:ss')}
        }
        if($SessionDirectory){$resultPath=Join-Path $SessionDirectory 'FACTORY_RESULT.json'}else{
            $pointer=Join-Path $Root 'STATE\recovery-session.json'
            $resultPath=''
            if(Test-Path -LiteralPath $pointer){$p=Get-Content $pointer -Raw -Encoding UTF8|ConvertFrom-Json;$resultPath=Join-Path ([string]$p.directory) 'FACTORY_RESULT.json'}
        }
        if($resultPath -and (Test-Path -LiteralPath $resultPath)){
            $r=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8|ConvertFrom-Json
            if($r.status -in @('PASS','FAIL','HOLD','RUNNING')){$state=[string]$r.status}
            if($state -ne 'RUNNING'){$returnText='処理結果を保存しました。返却用のRESULT.zipを1個アップロードしてください。'}
        }
        $label.Text="監視プロセス: $alive`r`n最終poll: $lastPoll`r`n現在: $job`r`n段階: $phase`r`n判定: $state`r`n次: Tanuki Comic Gate A（保留）`r`n`r`n$returnText`r`n`r`nFactory完成判定は実機証拠の確認後です。"
        $transition=$state
        if($transition -ne $script:lastTransition){
            $script:lastTransition=$transition
            if(-not $script:firstTick -or $state -in @('PASS','FAIL','HOLD')){
                $tray.BalloonTipTitle='Tanuki Factory: '+$state
                $tray.BalloonTipText=if($state -in @('PASS','FAIL','HOLD')){'結果を保存しました。画面で確認できます。'}else{'処理を開始しました。ログ操作は不要です。'}
                $tray.ShowBalloonTip(8000)
            }
        }
        $script:firstTick=$false
    } catch {$label.Text='状態の更新待ちです。ログ操作は不要です。'}
})
try {$timer.Start();[void]$form.ShowDialog()}finally{$timer.Stop();$tray.Dispose();$mutex.ReleaseMutex();$mutex.Dispose()}
