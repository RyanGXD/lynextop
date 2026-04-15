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

function Garantir-PastaDestino {
    $destino = Join-Path $env:USERPROFILE "Downloads\Instaladores"
    if (!(Test-Path $destino)) {
        New-Item -ItemType Directory -Path $destino -Force | Out-Null
    }
    return $destino
}

function Abrir-Link {
    param(
        [string]$Nome,
        [string]$Url
    )

    try {
        Start-Process $Url
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao abrir a pagina de $Nome.`n`n$($_.Exception.Message)",
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

        $destino = Garantir-PastaDestino
        $saida = Join-Path $destino $Arquivo

        Invoke-WebRequest -Uri $Url -OutFile $saida -UseBasicParsing

        $status.Text = "$Nome baixado com sucesso!"
        return $true
    }
    catch {
        $status.Text = "Erro ao baixar $Nome"
        [System.Windows.Forms.MessageBox]::Show(
            "Falha ao baixar $Nome.`n`n$($_.Exception.Message)",
            "Lynext"
        ) | Out-Null
        return $false
    }
}

function Abrir-E-Baixar {
    param(
        [string]$Nome,
        [string]$PaginaUrl,
        [string]$DownloadUrl,
        [string]$Arquivo
    )

    Abrir-Link -Nome $Nome -Url $PaginaUrl
    Start-Sleep -Milliseconds 300

    if ($DownloadUrl -and $Arquivo) {
        [void](Baixar-Arquivo -Nome $Nome -Url $DownloadUrl -Arquivo $Arquivo)
    }
}

# Chrome
$btnChrome = New-Object System.Windows.Forms.Button
$btnChrome.Text = "Chrome"
$btnChrome.Size = New-Object System.Drawing.Size(150,40)
$btnChrome.Location = New-Object System.Drawing.Point(20,70)
$btnChrome.Add_Click({
    Abrir-E-Baixar `
        -Nome "Chrome" `
        -PaginaUrl "https://www.google.com/intl/pt-BR/chrome/" `
        -DownloadUrl "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" `
        -Arquivo "Chrome.msi"
})
$form.Controls.Add($btnChrome)

# Java
$btnJava = New-Object System.Windows.Forms.Button
$btnJava.Text = "Java"
$btnJava.Size = New-Object System.Drawing.Size(150,40)
$btnJava.Location = New-Object System.Drawing.Point(210,70)
$btnJava.Add_Click({
    Abrir-E-Baixar `
        -Nome "Java" `
        -PaginaUrl "https://www.java.com/pt-br/download/manual.jsp" `
        -DownloadUrl "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=252907_0d06828d282343ea81775b28020a7cd3" `
        -Arquivo "Java_x64.exe"
})
$form.Controls.Add($btnJava)

# Adobe Reader
$btnAdobe = New-Object System.Windows.Forms.Button
$btnAdobe.Text = "Adobe Reader"
$btnAdobe.Size = New-Object System.Drawing.Size(150,40)
$btnAdobe.Location = New-Object System.Drawing.Point(20,125)
$btnAdobe.Add_Click({
    Abrir-Link -Nome "Adobe Reader" -Url "https://get.adobe.com/br/reader/"
    $status.Text = "Pagina do Adobe Reader aberta."
})
$form.Controls.Add($btnAdobe)

# AnyDesk
$btnAnyDesk = New-Object System.Windows.Forms.Button
$btnAnyDesk.Text = "AnyDesk"
$btnAnyDesk.Size = New-Object System.Drawing.Size(150,40)
$btnAnyDesk.Location = New-Object System.Drawing.Point(210,125)
$btnAnyDesk.Add_Click({
    Abrir-E-Baixar `
        -Nome "AnyDesk" `
        -PaginaUrl "https://anydesk.com/pt/downloads/windows" `
        -DownloadUrl "https://download.anydesk.com/AnyDesk.exe" `
        -Arquivo "AnyDesk.exe"
})
$form.Controls.Add($btnAnyDesk)

# Baixar Todos
$btnTudo = New-Object System.Windows.Forms.Button
$btnTudo.Text = "Baixar Todos"
$btnTudo.Size = New-Object System.Drawing.Size(340,45)
$btnTudo.Location = New-Object System.Drawing.Point(20,185)
$btnTudo.Add_Click({
    Abrir-E-Baixar `
        -Nome "Chrome" `
        -PaginaUrl "https://www.google.com/intl/pt-BR/chrome/" `
        -DownloadUrl "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" `
        -Arquivo "Chrome.msi"

    Abrir-E-Baixar `
        -Nome "Java" `
        -PaginaUrl "https://www.java.com/pt-br/download/manual.jsp" `
        -DownloadUrl "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=252907_0d06828d282343ea81775b28020a7cd3" `
        -Arquivo "Java_x64.exe"

    Abrir-Link -Nome "Adobe Reader" -Url "https://get.adobe.com/br/reader/"

    Abrir-E-Baixar `
        -Nome "AnyDesk" `
        -PaginaUrl "https://anydesk.com/pt/downloads/windows" `
        -DownloadUrl "https://download.anydesk.com/AnyDesk.exe" `
        -Arquivo "AnyDesk.exe"

    $status.Text = "Processo concluido."
})
$form.Controls.Add($btnTudo)

[void]$form.ShowDialog()
