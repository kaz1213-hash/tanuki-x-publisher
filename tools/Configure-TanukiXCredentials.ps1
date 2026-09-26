param([string]$CredentialPath='')

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'TanukiX.Credentials.psm1') -Force

$form=New-Object Windows.Forms.Form
$form.Text='Tanuki X - API Setup'
$form.StartPosition='CenterScreen'
$form.Size=New-Object Drawing.Size(620,430)
$form.MinimumSize=New-Object Drawing.Size(620,430)
$form.Font=New-Object Drawing.Font('Segoe UI',10)

$title=New-Object Windows.Forms.Label
$title.Text='X APIをこのPCに安全に保存'
$title.Font=New-Object Drawing.Font('Segoe UI Semibold',18)
$title.AutoSize=$true
$title.Location=New-Object Drawing.Point(28,24)
$form.Controls.Add($title)

$note=New-Object Windows.Forms.Label
$note.Text='4項目はWindowsのユーザー暗号化(DPAPI)で保存します。GitHub Actions Secretsから値を読み出すことはできません。'
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
$save.Text='安全に保存'
$save.Size=New-Object Drawing.Size(150,42)
$save.Location=New-Object Drawing.Point(390,335)
$form.Controls.Add($save)

$save.Add_Click({
    try{
        $path=Save-TanukiXCredentialState -ApiKey $boxes[0].Text -ApiSecret $boxes[1].Text -AccessToken $boxes[2].Text -AccessTokenSecret $boxes[3].Text -Path $CredentialPath
        [Windows.Forms.MessageBox]::Show(('保存しました。'+[Environment]::NewLine+$path),'Tanuki X','OK','Information') | Out-Null
        $form.DialogResult=[Windows.Forms.DialogResult]::OK
        $form.Close()
    }catch{
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Tanuki X','OK','Error') | Out-Null
    }
})

[void]$form.ShowDialog()
