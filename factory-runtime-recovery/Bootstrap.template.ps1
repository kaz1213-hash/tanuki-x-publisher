$ErrorActionPreference='Stop'
function Expand-EmbeddedFactoryPackage([string]$Source,[string]$Destination) {
    $text=[IO.File]::ReadAllText($Source,[Text.Encoding]::ASCII)
    $parts=$text -split ':__TANUKI_FACTORY_PAYLOAD__',2
    if($parts.Count -ne 2){throw 'PACKAGE_MARKER_MISSING'}
    $bytes=[Convert]::FromBase64String($parts[1].Trim())
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    if($hash -ne '__ZIP_SHA__'){throw 'EMBEDDED_HASH_MISMATCH'}
    New-Item -ItemType Directory -Path $Destination -Force|Out-Null
    $zip=Join-Path $Destination 'package.zip'
    [IO.File]::WriteAllBytes($zip,$bytes)
    Expand-Archive -LiteralPath $zip -DestinationPath $Destination -Force
    Remove-Item -LiteralPath $zip -Force
}
try {
    $source=$env:TANUKI_RECOVERY_SOURCE
    $destination=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('TanukiFactoryRecovery\packages\'+[Guid]::NewGuid().ToString('N'))
    Expand-EmbeddedFactoryPackage $source $destination
    $exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args='-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $destination 'RunRecovery.ps1')+'"'
    Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden -ErrorAction Stop|Out-Null
} catch {
    $result='{"schema":"factory-bootstrap-result-v1","status":"HOLD","code":"BOOTSTRAP_FAILURE","factory_completion_pass":false}'
    try {
        $dir=Join-Path ([Environment]::GetFolderPath('Desktop')) 'TanukiFactory_Result'
        New-Item -ItemType Directory -Path $dir -Force|Out-Null
        $receipt=Join-Path $dir 'FACTORY_RESULT.json'
        [IO.File]::WriteAllText($receipt,$result,[Text.Encoding]::UTF8)
        $returnFile=$receipt
        try{Compress-Archive -LiteralPath $receipt -DestinationPath (Join-Path $dir 'RESULT.zip') -Force;$returnFile=Join-Path $dir 'RESULT.zip'}catch{}
        Start-Process explorer.exe -ArgumentList ('/select,"'+$returnFile+'"')|Out-Null
    } catch {
        try{[IO.File]::WriteAllText((Join-Path ([IO.Path]::GetTempPath()) 'TANUKI_FACTORY_BOOTSTRAP_RESULT.json'),$result)}catch{}
    }
    try{$w=New-Object -ComObject WScript.Shell;[void]$w.Popup('Tanuki Factory HOLD. A safe result was saved. No log inspection or repeat run is needed.',15,'Tanuki Factory',48)}catch{}
    exit 1
}
