Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
# Load ONLY the result writer AST, never run the Windows installer/controller.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\RunRecovery.ps1'),[ref]$tokens,[ref]$errors)
$function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-RunResult'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$script:ExportResultsToDesktop=$false
$script:RunDirectory=Join-Path ([IO.Path]::GetTempPath()) ('delivery-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:RunDirectory|Out-Null
$script:RunState=[ordered]@{status='RUNNING';code='TEST';started_utc=[DateTime]::UtcNow.ToString('o');finished_utc=$null;factory_completion_pass=$false;automatic_result_return=$false}
try {
    Save-RunResult 'HOLD' 'SYNTHETIC_DIAGNOSTIC_HOLD'
    $json=Join-Path $script:RunDirectory 'FACTORY_RESULT.json';$zip=Join-Path $script:RunDirectory 'RESULT.zip'
    if(-not (Test-Path $json) -or -not (Test-Path $zip)){throw 'Missing delivery output'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($zip)
    try{if($archive.Entries.Count -ne 1 -or $archive.Entries[0].FullName -ne 'FACTORY_RESULT.json'){throw 'Nonallowlisted return file'}}finally{$archive.Dispose()}
    function Compress-Archive {throw 'injected compression failure'}
    Save-RunResult 'FAIL' 'SYNTHETIC_FAILURE'
    $r=Get-Content $json -Raw|ConvertFrom-Json
    if($r.status -ne 'HOLD' -or $r.code -ne 'RESULT_COMPRESSION_FAILED_JSON_RETAINED'){throw 'Compression failure lost JSON'}
    if(Test-Path $zip){throw 'Stale ZIP survived compression failure'}
    Write-Output 'DELIVERY_PASS=4'
} finally {Remove-Item -LiteralPath $script:RunDirectory -Recurse -Force -ErrorAction SilentlyContinue}
