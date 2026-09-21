Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\RunRecovery.ps1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-RunResult'},$true)
$base=Join-Path ([IO.Path]::GetTempPath()) ('結 '+[Guid]::NewGuid().ToString('N').Substring(0,12))
$desktop=Join-Path $base 'Desktop 投影'
$source=$fn.Extent.Text.Replace("[Environment]::GetFolderPath('Desktop')",("'"+$desktop.Replace("'","''")+"'"))
. ([scriptblock]::Create($source))
$script:ExportResultsToDesktop=$true
$script:RunDirectory=Join-Path $base 'Run';[void][IO.Directory]::CreateDirectory($script:RunDirectory)
$script:RunState=[ordered]@{status='RUNNING';code='TEST';started_utc=[DateTime]::UtcNow.ToString('o');finished_utc=$null;factory_completion_pass=$false}
try {
    Save-RunResult 'HOLD' 'SHADOW_TEST_HOLD'
    $zip=Join-Path $script:RunDirectory 'RESULT.zip';$export=Join-Path $desktop 'TanukiFactory_Result/RESULT.zip'
    if($script:ReadyResultPath -ne $export -or (Get-FileHash $zip).Hash -ne (Get-FileHash $export).Hash){throw 'Desktop result identity mismatch'}
    $pointer=Get-Content (Join-Path $script:RunDirectory 'DELIVERY_LOCATION.json') -Raw|ConvertFrom-Json
    if($pointer.path -ne $export){throw 'UI pointer did not select returned ZIP'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z=[IO.Compression.ZipFile]::OpenRead($export)
    try{if($z.Entries.Count -ne 1 -or $z.Entries[0].FullName -ne 'FACTORY_RESULT.json'){throw 'Local paths or files leaked into ZIP'}}finally{$z.Dispose()}
    function Copy-Item {throw 'injected desktop write denial'}
    Save-RunResult 'HOLD' 'DESKTOP_COPY_FAILURE_FIXTURE'
    $pointer=Get-Content (Join-Path $script:RunDirectory 'DELIVERY_LOCATION.json') -Raw|ConvertFrom-Json
    if($script:ReadyResultPath -ne $zip -or $pointer.path -ne $zip){throw 'Desktop failure lost actual result selection'}
    function Compress-Archive {throw 'injected compression failure'}
    Save-RunResult 'HOLD' 'ARCHIVE_FAILURE_FIXTURE'
    if($script:ReadyResultPath -ne (Join-Path $script:RunDirectory 'FACTORY_RESULT.json') -or -not (Test-Path $script:ReadyResultPath)){throw 'Archive failure selected stale ZIP'}
    'DELIVERY_PATH_PASS=5'
} finally {Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue}
