Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.Size = New-Object System.Drawing.Size(520,360)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Topmost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(245,245,245)

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text = "Central de Downloads"
$titulo.Font = New-Object System.Drawing.Font("Segoe UI",13,[System.Drawing.FontStyle]::Bold)
$titulo.AutoSize = $true
$titulo.Location = New-Object System.Drawing.Point(160,20)
$form.Controls.Add($titulo)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Baixe os programas e acompanhe o status em tempo real"
$sub.Font = New-Object System.Drawing.Font("Segoe UI",9)
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(95,50)
$form.Controls.Add($sub)

function Novo-StatusLabel {
    param(
        [int]$x,
        [int]$y,
        [string]$texto
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $texto
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",10)
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point($x,$y)
    return $lbl
}

function Novo-Botao {
    param(
        [string]$texto,
        [int]$x,
        [int]$y
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $texto
    $btn.Size = New-Object System.Drawing.Size(120,35)
    $btn.Location = New-Object System.Drawing.Point($x,$y)
    return $btn
}

$lblChrome = Novo-StatusLabel 30 95 "Chrome"
$stChrome  = Novo-StatusLabel 360 95 "Aguardando"
$form.Controls.Add($lblChrome)
$form.Controls.Add($stChrome)

$lblJava = Novo-StatusLabel 30 130 "Java"
$stJava  = Novo-StatusLabel 360 130 "Aguardando"
$form.Controls.Add($lblJava)
$form.Controls.Add($stJava)

$lblAdobe = Novo-StatusLabel 30 165 "Adobe Reader"
$stAdobe  = Novo-StatusLabel 360 165 "Aguardando"
$form.Controls.Add($lblAdobe)
$form.Controls.Add($stAdobe)

$lblAnyDesk = Novo-StatusLabel 30 200 "AnyDesk"
$stAnyDesk  = Novo-StatusLabel 360 200 "Aguardando"
$form.Controls.Add($lblAnyDesk)
$form.Controls.Add($stAnyDesk)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size = New-Object System.Drawing.Size(440,22)
$progress.Location = New-Object System.Drawing.Point(30,240)
$progress.Style = "Continuous"
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$lblGeral = New-Object System.Windows.Forms.Label
$lblGeral.Text = "Pronto para iniciar."
$lblGeral.AutoSize = $true
$lblGeral.Font = New-Object System.Drawing.Font("Segoe UI",9)
$lblGeral.Location = New-Object System.Drawing.Point(30,270)
$form.Controls.Add($lblGeral)

$btnBaixarTudo = Novo-Botao "Baixar Todos" 110 295
$btnFechar = Novo-Botao "Fechar" 260 295
$form.Controls.Add($btnBaixarTudo)
$form.Controls.Add($btnFechar)

function Garantir-PastaDestino {
    $destino = Join-Path $env:USERPROFILE "Downloads\Instaladores"
    if (!(Test-Path $destino)) {
        New-Item -ItemType Directory -Path $destino -Force | Out-Null
    }
    return $destino
}

function Atualizar-Status {
    param(
        [System.Windows.Forms.Label]$Label,
        [string]$Texto
    )
    $Label.Text = $Texto
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Baixar-Arquivo {
    param(
        [string]$Nome,
        [string]$Url,
        [string]$Arquivo,
        [System.Windows.Forms.Label]$StatusLabel,
        [int]$ProgressValue,
        [string]$PaginaUrl = $null
    )

    try {
        Atualizar-Status $StatusLabel "Baixando..."
        $lblGeral.Text = "Baixando $Nome..."
        $progress.Value = [Math]::Min($ProgressValue - 15, 95)
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        if ($PaginaUrl) {
            Start-Process $PaginaUrl
        }

        $destino = Garantir-PastaDestino
        $saida = Join-Path $destino $Arquivo

        Invoke-WebRequest -Uri $Url -OutFile $saida -UseBasicParsing

        Atualizar-Status $StatusLabel "Concluido  [OK]"
        $progress.Value = $ProgressValue
        $lblGeral.Text = "$Nome concluido."
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        return $true
    }
    catch {
        Atualizar-Status $StatusLabel "Erro  [X]"
        $lblGeral.Text = "Falha em $Nome."
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        return $false
    }
}

function Abrir-Somente-Link {
    param(
        [string]$Nome,
        [string]$Url,
        [System.Windows.Forms.Label]$StatusLabel,
        [int]$ProgressValue
    )

    try {
        Atualizar-Status $StatusLabel "Abrindo pagina..."
        $lblGeral.Text = "Abrindo pagina de $Nome..."
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()

        Start-Process $Url

        Atualizar-Status $StatusLabel "Pagina aberta  [OK]"
        $progress.Value = $ProgressValue
        $lblGeral.Text = "Pagina de $Nome aberta."
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        return $true
    }
    catch {
        Atualizar-Status $StatusLabel "Erro  [X]"
        $lblGeral.Text = "Falha ao abrir pagina de $Nome."
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        return $false
    }
}

$btnBaixarTudo.Add_Click({
    $btnBaixarTudo.Enabled = $false
    $progress.Value = 0

    Atualizar-Status $stChrome "Na fila..."
    Atualizar-Status $stJava "Na fila..."
    Atualizar-Status $stAdobe "Na fila..."
    Atualizar-Status $stAnyDesk "Na fila..."
    $lblGeral.Text = "Iniciando downloads..."
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    Baixar-Arquivo `
        -Nome "Chrome" `
        -Url "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" `
        -Arquivo "Chrome.msi" `
        -StatusLabel $stChrome `
        -ProgressValue 25 `
        -PaginaUrl "https://www.google.com/intl/pt-BR/chrome/" | Out-Null

    Baixar-Arquivo `
        -Nome "Java" `
        -Url "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=252907_0d06828d282343ea81775b28020a7cd3" `
        -Arquivo "Java_x64.exe" `
        -StatusLabel $stJava `
        -ProgressValue 50 `
        -PaginaUrl "https://www.java.com/pt-br/download/manual.jsp" | Out-Null

    Abrir-Somente-Link `
        -Nome "Adobe Reader" `
        -Url "https://get.adobe.com/br/reader/" `
        -StatusLabel $stAdobe `
        -ProgressValue 75 | Out-Null

    Baixar-Arquivo `
        -Nome "AnyDesk" `
        -Url "https://download.anydesk.com/AnyDesk.exe" `
        -Arquivo "AnyDesk.exe" `
        -StatusLabel $stAnyDesk `
        -ProgressValue 100 `
        -PaginaUrl "https://anydesk.com/pt/downloads/windows" | Out-Null

    $lblGeral.Text = "Processo finalizado."
    $btnBaixarTudo.Enabled = $true
})

$btnFechar.Add_Click({
    $form.Close()
})

[void]$form.ShowDialog()
