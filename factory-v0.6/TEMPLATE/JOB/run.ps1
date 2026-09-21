Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$out=$env:TANUKI_RUNNER_OUT
if([string]::IsNullOrWhiteSpace($out)){ exit 10 }
New-Item -ItemType Directory -Path $out -Force | Out-Null

$result=[ordered]@{
    schema='tanuki-product-factory-result-v1'
    status='PASS'
    mutation_performed=$false
}
$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'PRODUCT_RESULT.json') -Encoding UTF8
exit 0
