Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext"
$form.Size = New-Object System.Drawing.Size(400,320)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Topmost = $true

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text = "Central de Downloads"
$titulo.Font = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)
$titulo.AutoSize = $true
$titulo.Location = New-Object System.Drawing.Point(100,20)
$form.Controls.Add($titulo)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Aguardando..."
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(20,245)
$form.Controls.Add($status)

function Abrir-Link {
    param(
        [string]$Nome,
        [string]$Url
    )

    try {
        $status.Text = "Abrindo $Nome..."
        $form.Refresh()
        Start-Process $Url
        $status.Text = "$Nome aberto com sucesso!"
    }
    catch {
        $status.Text = "Erro ao abrir $Nome"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao abrir $Nome.`n`n$($_.Exception.Message)",
            "Lynext"
        ) | Out-Null
    }
}

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
            "$Nome baixado com sucesso.`n`n$saida",
            "Lynext"
        ) | Out-Null
    }
    catch {
        $status.Text = "Erro ao baixar $Nome"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao baixar $Nome.`n`n$($_.Exception.Message)",
            "Lynext"
        ) | Out-Null
    }
}

# Chrome -> abre pagina oficial PT-BR
$btnChrome = New-Object System.Windows.Forms.Button
$btnChrome.Text = "Chrome"
$btnChrome.Size = New-Object System.Drawing.Size(150,40)
$btnChrome.Location = New-Object System.Drawing.Point(20,70)
$btnChrome.Add_Click({
    Abrir-Link -Nome "Chrome" -Url "https://www.google.com/intl/pt-BR/chrome/"
})
$form.Controls.Add($btnChrome)

# Java -> abre pagina oficial PT-BR de download manual
$btnJava = New-Object System.Windows.Forms.Button
$btnJava.Text = "Java"
$btnJava.Size = New-Object System.Drawing.Size(150,40)
$btnJava.Location = New-Object System.Drawing.Point(210,70)
$btnJava.Add_Click({
    Abrir-Link -Nome "Java" -Url "https://www.java.com/pt-br/download/manual.jsp"
})
$form.Controls.Add($btnJava)

# Adobe -> abre pagina oficial Reader
$btnAdobe = New-Object System.Windows.Forms.Button
$btnAdobe.Text = "Adobe Reader"
$btnAdobe.Size = New-Object System.Drawing.Size(150,40)
$btnAdobe.Location = New-Object System.Drawing.Point(20,125)
$btnAdobe.Add_Click({
    Abrir-Link -Nome "Adobe Reader" -Url "https://get.adobe.com/br/reader/"
})
$form.Controls.Add($btnAdobe)

# AnyDesk -> esse continua em download direto
$btnAnyDesk = New-Object System.Windows.Forms.Button
$btnAnyDesk.Text = "AnyDesk"
$btnAnyDesk.Size = New-Object System.Drawing.Size(150,40)
$btnAnyDesk.Location = New-Object System.Drawing.Point(210,125)
$btnAnyDesk.Add_Click({
    Baixar-Arquivo -Nome "AnyDesk" -Url "https://download.anydesk.com/AnyDesk.exe" -Arquivo "AnyDesk.exe"
})
$form.Controls.Add($btnAnyDesk)

# Baixar Tudo -> abre as paginas oficiais + baixa AnyDesk
$btnTudo = New-Object System.Windows.Forms.Button
$btnTudo.Text = "Abrir Tudo"
$btnTudo.Size = New-Object System.Drawing.Size(340,45)
$btnTudo.Location = New-Object System.Drawing.Point(20,185)
$btnTudo.Add_Click({
    Abrir-Link -Nome "Chrome" -Url "https://www.google.com/intl/pt-BR/chrome/"
    Abrir-Link -Nome "Java" -Url "https://www.java.com/pt-br/download/manual.jsp"
    Abrir-Link -Nome "Adobe Reader" -Url "https://get.adobe.com/br/reader/"
    Baixar-Arquivo -Nome "AnyDesk" -Url "https://download.anydesk.com/AnyDesk.exe" -Arquivo "AnyDesk.exe"
})
$form.Controls.Add($btnTudo)

[void]$form.ShowDialog()
