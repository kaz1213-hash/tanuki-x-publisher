$ErrorActionPreference='Stop'
$base=Join-Path ([IO.Path]::GetTempPath()) ('worker-check-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
$worker=Join-Path $PSScriptRoot 'QualificationWorker.ps1'
$exe=(Get-Process -Id $PID).Path
$script=Join-Path $base 'Runtime.Smoke.ps1';$out=Join-Path $base 'result.json'
try{
    foreach($case in @('PASS','PATH_TOO_LONG','STDERR_FAIL','EXIT_FAIL')){
        $body=switch($case){'PASS' {"Write-Output 'fixture pass'"};'PATH_TOO_LONG' {"throw [IO.PathTooLongException]::new('PRIVATE_PATH_SENTINEL')"};'STDERR_FAIL' {"[Console]::Error.WriteLine('PRIVATE_STDERR_SENTINEL');throw 'PRIVATE_EXCEPTION_SENTINEL'"};'EXIT_FAIL' {'exit 7'}}
        $body|Set-Content -LiteralPath $script
        $options=@{FilePath=$exe;ArgumentList=('-NoProfile -File "'+$worker+'" -TestScript "'+$script+'" -ReceiptPath "'+$out+'"');RedirectStandardOutput=(Join-Path $base 'stdout.log');RedirectStandardError=(Join-Path $base 'stderr.log');PassThru=$true}
        if($PSVersionTable.PSEdition -eq 'Desktop'){$options.WindowStyle='Hidden'}
        $p=Start-Process @options;$handle=$p.Handle
        if(-not $p.WaitForExit(15000)){throw 'Worker fixture timeout'}
        $p.WaitForExit();$code=$p.ExitCode;$raw=Get-Content $out -Raw;$r=$raw|ConvertFrom-Json
        if($raw -match 'PRIVATE_'){throw 'Private data leaked'}
        if($case -eq 'PASS'){if($code -ne 0 -or $r.status -ne 'PASS'){throw 'Pass lost'}}else{if($code -eq 0 -or $r.status -ne 'HOLD' -or $r.exception_line -lt 1){throw 'Failure lost'}}
        if($case -eq 'PATH_TOO_LONG' -and $r.exception_class -ne 'PATH_TOO_LONG'){throw 'Path error not classified'}
    }
    'WORKER_RECEIPT_PASS=4'
}finally{Remove-Item $base -Recurse -Force}
