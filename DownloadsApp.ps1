Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.Size = New-Object System.Drawing.Size(400,330)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Topmost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text = "Central de Downloads"
$titulo.Font = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)
$titulo.AutoSize = $true
$titulo.Location = New-Object System.Drawing.Point(105,20)
$form.Controls.Add($titulo)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Aguardando..."
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(20,250)
$status.Font = New-Object System.Drawing.Font("Segoe UI",9)
$form.Controls.Add($status)

$destinoLabel = New-Object System.Windows.Forms.Label
$destinoLabel.Text = "Destino: Downloads\Instaladores"
$destinoLabel.AutoSize = $true
$destinoLabel.Location = New-Object System.Drawing.Point(20,275)
$destinoLabel.Font = New-Object System.Drawing.Font("Segoe UI",9)
$form.Controls.Add($destinoLabel)

function Baixar-Arquivo {
    param(
        [string]$Nome,
        [string]$Url,
        [string]$Arquivo
    )

    try {
        $status.Text = "Baixando $Nome..."
        $form.Refresh()

        $destino = Join-Path $env:USERPROFILE "Downloads\Instaladores"
        if (!(Test-Path $destino)) {
            New-Item -ItemType Directory -Path $destino -Force | Out-Null
        }

        $saida = Join-Path $destino $Arquivo

        Invoke-WebRequest -Uri $Url -OutFile $saida -UseBasicParsing

        $status.Text = "$Nome baixado com sucesso!"
        [System.Windows.Forms.MessageBox]::Show(
            "$Nome foi baixado com sucesso.`n`nArquivo:`n$saida",
            "Lynext",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        $status.Text = "Erro ao baixar $Nome"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao baixar $Nome.`n`nDetalhe:`n$($_.Exception.Message)",
            "Lynext",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

$btnChrome = New-Object System.Windows.Forms.Button
$btnChrome.Text = "Chrome"
$btnChrome.Size = New-Object System.Drawing.Size(150,40)
$btnChrome.Location = New-Object System.Drawing.Point(20,70)
$btnChrome.Add_Click({
    Baixar-Arquivo `
        -Nome "Chrome" `
        -Url "https://www.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi" `
        -Arquivo "Chrome.msi"
})
$form.Controls.Add($btnChrome)

$btnJava = New-Object System.Windows.Forms.Button
$btnJava.Text = "Java"
$btnJava.Size = New-Object System.Drawing.Size(150,40)
$btnJava.Location = New-Object System.Drawing.Point(210,70)
$btnJava.Add_Click({
    Baixar-Arquivo `
        -Nome "Java" `
        -Url "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=248795" `
        -Arquivo "Java.exe"
})
$form.Controls.Add($btnJava)

$btnAdobe = New-Object System.Windows.Forms.Button
$btnAdobe.Text = "Adobe Reader"
$btnAdobe.Size = New-Object System.Drawing.Size(150,40)
$btnAdobe.Location = New-Object System.Drawing.Point(20,125)
$btnAdobe.Add_Click({
    Baixar-Arquivo `
        -Nome "Adobe Reader" `
        -Url "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2300320269/AcroRdrDCx64.exe" `
        -Arquivo "AdobeReader.exe"
})
$form.Controls.Add($btnAdobe)

$btnAnyDesk = New-Object System.Windows.Forms.Button
$btnAnyDesk.Text = "AnyDesk"
$btnAnyDesk.Size = New-Object System.Drawing.Size(150,40)
$btnAnyDesk.Location = New-Object System.Drawing.Point(210,125)
$btnAnyDesk.Add_Click({
    Baixar-Arquivo `
        -Nome "AnyDesk" `
        -Url "https://download.anydesk.com/AnyDesk.exe" `
        -Arquivo "AnyDesk.exe"
})
$form.Controls.Add($btnAnyDesk)

$btnTudo = New-Object System.Windows.Forms.Button
$btnTudo.Text = "Baixar Tudo"
$btnTudo.Size = New-Object System.Drawing.Size(340,45)
$btnTudo.Location = New-Object System.Drawing.Point(20,185)
$btnTudo.Add_Click({
    Baixar-Arquivo -Nome "Chrome" -Url "https://www.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi" -Arquivo "Chrome.msi"
    Baixar-Arquivo -Nome "Java" -Url "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=248795" -Arquivo "Java.exe"
    Baixar-Arquivo -Nome "Adobe Reader" -Url "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2300320269/AcroRdrDCx64.exe" -Arquivo "AdobeReader.exe"
    Baixar-Arquivo -Nome "AnyDesk" -Url "https://download.anydesk.com/AnyDesk.exe" -Arquivo "AnyDesk.exe"
})
$form.Controls.Add($btnTudo)

$btnFechar = New-Object System.Windows.Forms.Button
$btnFechar.Text = "Fechar"
$btnFechar.Size = New-Object System.Drawing.Size(340,30)
$btnFechar.Location = New-Object System.Drawing.Point(20,235)
$btnFechar.Add_Click({
    $form.Close()
})
$form.Controls.Add($btnFechar)

[void]$form.ShowDialog()
