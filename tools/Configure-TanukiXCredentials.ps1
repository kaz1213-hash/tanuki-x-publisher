param([string]$CredentialPath='')

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'TanukiX.Credentials.psm1') -Force

$resourcePath=Join-Path $PSScriptRoot 'resources\ja.json'
if(-not (Test-Path $resourcePath -PathType Leaf)){$resourcePath=Join-Path $PSScriptRoot 'resources\en.json'}
$strings=Get-Content -LiteralPath $resourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
function T([string]$Key){
    $p=$strings.PSObject.Properties[$Key]
    if($null -ne $p){return [string]$p.Value}
    return $Key
}

$form=New-Object Windows.Forms.Form
$form.Text=T 'window.title'
$form.StartPosition='CenterScreen'
$form.Size=New-Object Drawing.Size(620,430)
$form.MinimumSize=New-Object Drawing.Size(620,430)
$form.Font=New-Object Drawing.Font('Segoe UI',10)

$title=New-Object Windows.Forms.Label
$title.Text=T 'title'
$title.Font=New-Object Drawing.Font('Segoe UI Semibold',18)
$title.AutoSize=$true
$title.Location=New-Object Drawing.Point(28,24)
$form.Controls.Add($title)

$note=New-Object Windows.Forms.Label
$note.Text=T 'note'
$note.Size=New-Object Drawing.Size(545,45)
$note.Location=New-Object Drawing.Point(30,68)
$form.Controls.Add($note)

$labels=@('API Key','API Secret','Access Token','Access Token Secret')
$boxes=@()
for($i=0;$i -lt $labels.Count;$i++){
    $label=New-Object Windows.Forms.Label
    $label.Text=$labels[$i]
    $label.AutoSize=$true
    $label.Location=New-Object Drawing.Point(30,(125+$i*52))
    $form.Controls.Add($label)

    $box=New-Object Windows.Forms.TextBox
    $box.Size=New-Object Drawing.Size(350,28)
    $box.Location=New-Object Drawing.Point(190,(120+$i*52))
    $box.UseSystemPasswordChar=$true
    $form.Controls.Add($box)
    $boxes += $box
}

$save=New-Object Windows.Forms.Button
$save.Text=T 'button.save'
$save.Size=New-Object Drawing.Size(150,42)
$save.Location=New-Object Drawing.Point(390,335)
$form.Controls.Add($save)

$save.Add_Click({
    try{
        $path=Save-TanukiXCredentialState -ApiKey $boxes[0].Text -ApiSecret $boxes[1].Text -AccessToken $boxes[2].Text -AccessTokenSecret $boxes[3].Text -Path $CredentialPath
        $message=(T 'saved')+[Environment]::NewLine+$path
        [Windows.Forms.MessageBox]::Show($message,(T 'window.title'),'OK','Information') | Out-Null
        $form.DialogResult=[Windows.Forms.DialogResult]::OK
        $form.Close()
    }catch{
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,(T 'window.title'),'OK','Error') | Out-Null
    }
})

[void]$form.ShowDialog()
