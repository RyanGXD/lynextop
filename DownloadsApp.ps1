Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# CONFIG
# =========================
$destinoBase = Join-Path $env:USERPROFILE "Downloads\Instaladores"

$downloadsAtivos = @{}

# =========================
# CORES
# =========================
$corFundo      = [System.Drawing.Color]::FromArgb(18,18,18)
$corPainel     = [System.Drawing.Color]::FromArgb(28,28,28)
$corTexto      = [System.Drawing.Color]::FromArgb(230,230,230)
$corTextoSoft  = [System.Drawing.Color]::FromArgb(170,170,170)
$corBotao      = [System.Drawing.Color]::FromArgb(40,40,40)
$corBorda      = [System.Drawing.Color]::FromArgb(55,55,55)

# =========================
# FUNCOES
# =========================
function Garantir-Pasta {
    param([string]$Pasta)

    if (!(Test-Path $Pasta)) {
        New-Item -ItemType Directory -Path $Pasta -Force | Out-Null
    }
}

function Set-Status {
    param(
        [System.Windows.Forms.Label]$Label,
        [string]$Texto,
        [string]$Tipo = "normal"
    )

    $Label.Text = $Texto

    switch ($Tipo) {
        "ok"      { $Label.ForeColor = [System.Drawing.Color]::LightGreen }
        "erro"    { $Label.ForeColor = [System.Drawing.Color]::Tomato }
        "andando" { $Label.ForeColor = [System.Drawing.Color]::Orange }
        "manual"  { $Label.ForeColor = [System.Drawing.Color]::DeepSkyBlue }
        default   { $Label.ForeColor = $corTextoSoft }
    }
}

function Novo-Label {
    param(
        [string]$Texto,
        [int]$X,
        [int]$Y,
        [int]$Tamanho = 10,
        [bool]$Negrito = $false,
        [System.Drawing.Color]$Cor = $null
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Texto
    if ($Negrito) {
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI",$Tamanho,[System.Drawing.FontStyle]::Bold)
    }
    else {
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI",$Tamanho)
    }
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point($X,$Y)
    if ($Cor -ne $null) {
        $lbl.ForeColor = $Cor
    }
    else {
        $lbl.ForeColor = $corTexto
    }
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    return $lbl
}

function Novo-Botao {
    param(
        [string]$Texto,
        [int]$X,
        [int]$Y,
        [int]$Largura = 110,
        [int]$Altura = 30
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Texto
    $btn.Size = New-Object System.Drawing.Size($Largura,$Altura)
    $btn.Location = New-Object System.Drawing.Point($X,$Y)
    $btn.FlatStyle = "Flat"
    $btn.BackColor = $corBotao
    $btn.ForeColor = $corTexto
    $btn.FlatAppearance.BorderColor = $corBorda
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55,55,55)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(70,70,70)
    return $btn
}

function Iniciar-DownloadExterno {
    param(
        [string]$Nome,
        [string]$Url,
        [string]$Arquivo,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Label]$LabelGeral,
        [System.Windows.Forms.ProgressBar]$Barra
    )

    try {
        Garantir-Pasta $destinoBase
        $saida = Join-Path $destinoBase $Arquivo

        if (Test-Path $saida) {
            Remove-Item $saida -Force -ErrorAction SilentlyContinue
        }

        $script = @"
`$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri '$Url' -OutFile '$saida' -UseBasicParsing
    exit 0
}
catch {
    exit 1
}
"@

        $proc = Start-Process powershell.exe `
            -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command $script" `
            -PassThru `
            -WindowStyle Hidden

        $downloadsAtivos[$Nome] = [PSCustomObject]@{
            ProcessoId = $proc.Id
            Arquivo    = $saida
            Status     = $StatusLabel
            Finalizado = $false
        }

        Set-Status $StatusLabel "Baixando..." "andando"
        $LabelGeral.Text = "Baixando $Nome..."
        $Barra.Style = "Marquee"
    }
    catch {
        Set-Status $StatusLabel "Erro [X]" "erro"
        $LabelGeral.Text = "Falha ao iniciar download de $Nome."
        $Barra.Style = "Blocks"
    }
}

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.Size = New-Object System.Drawing.Size(620,430)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Topmost = $true
$form.BackColor = $corFundo

$titulo = Novo-Label "Central de Downloads" 185 18 15 $true
$form.Controls.Add($titulo)

$sub = Novo-Label "Automático separado do manual, do jeito mais estável" 145 48 9 $false $corTextoSoft
$form.Controls.Add($sub)

# =========================
# SECAO AUTOMATICA
# =========================
$autoTitulo = Novo-Label "AUTOMATICO" 35 90 11 $true
$form.Controls.Add($autoTitulo)

$autoInfo = Novo-Label "Baixa direto para Downloads\Instaladores" 35 112 9 $false $corTextoSoft
$form.Controls.Add($autoInfo)

$lblChrome = Novo-Label "Chrome" 35 145
$stChrome = Novo-Label "Aguardando" 360 145 10 $false $corTextoSoft
$form.Controls.Add($lblChrome)
$form.Controls.Add($stChrome)

$btnChrome = Novo-Botao "Baixar" 470 140
$form.Controls.Add($btnChrome)

$lblAnyDesk = Novo-Label "AnyDesk" 35 180
$stAnyDesk = Novo-Label "Aguardando" 360 180 10 $false $corTextoSoft
$form.Controls.Add($lblAnyDesk)
$form.Controls.Add($stAnyDesk)

$btnAnyDesk = Novo-Botao "Baixar" 470 175
$form.Controls.Add($btnAnyDesk)

# =========================
# SECAO MANUAL
# =========================
$manualTitulo = Novo-Label "MANUAL" 35 230 11 $true
$form.Controls.Add($manualTitulo)

$manualInfo = Novo-Label "Abre a pagina oficial para voce baixar manualmente" 35 252 9 $false $corTextoSoft
$form.Controls.Add($manualInfo)

$lblJava = Novo-Label "Java" 35 285
$stJava = Novo-Label "Aguardando" 360 285 10 $false $corTextoSoft
$form.Controls.Add($lblJava)
$form.Controls.Add($stJava)

$btnJava = Novo-Botao "Abrir Pagina" 440 280 140 30
$form.Controls.Add($btnJava)

$lblAdobe = Novo-Label "Adobe Reader" 35 320
$stAdobe = Novo-Label "Aguardando" 360 320 10 $false $corTextoSoft
$form.Controls.Add($lblAdobe)
$form.Controls.Add($stAdobe)

$btnAdobe = Novo-Botao "Abrir Pagina" 440 315 140 30
$form.Controls.Add($btnAdobe)

# =========================
# RODAPE
# =========================
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size = New-Object System.Drawing.Size(545,18)
$progress.Location = New-Object System.Drawing.Point(35,360)
$progress.Style = "Blocks"
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$lblGeral = Novo-Label "Pronto para iniciar." 35 385 9 $false $corTextoSoft
$form.Controls.Add($lblGeral)

$btnTudo = Novo-Botao "Baixar Todos Automaticos" 310 380 180 30
$form.Controls.Add($btnTudo)

$btnFechar = Novo-Botao "Fechar" 500 380 80 30
$form.Controls.Add($btnFechar)

# =========================
# TIMER
# =========================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700

$timer.Add_Tick({
    $ativos = 0
    $concluidos = 0

    foreach ($nome in @("Chrome","AnyDesk")) {
        if ($downloadsAtivos.ContainsKey($nome)) {
            $info = $downloadsAtivos[$nome]

            if (-not $info.Finalizado) {
                $proc = Get-Process -Id $info.ProcessoId -ErrorAction SilentlyContinue

                if ($proc) {
                    $ativos++
                    if (Test-Path $info.Arquivo) {
                        try {
                            $tam = (Get-Item $info.Arquivo).Length
                            if ($tam -gt 0) {
                                $mb = [math]::Round($tam / 1MB, 2)
                                Set-Status $info.Status "Baixando... $mb MB" "andando"
                            }
                        }
                        catch {}
                    }
                }
                else {
                    $info.Finalizado = $true
                    $downloadsAtivos[$nome] = $info

                    if ((Test-Path $info.Arquivo) -and ((Get-Item $info.Arquivo).Length -gt 0)) {
                        Set-Status $info.Status "Concluido [OK]" "ok"
                        $lblGeral.Text = "$nome concluido."
                    }
                    else {
                        Set-Status $info.Status "Erro [X]" "erro"
                        $lblGeral.Text = "Falha em $nome."
                    }
                }
            }

            if ($info.Finalizado -and (Test-Path $info.Arquivo) -and ((Get-Item $info.Arquivo).Length -gt 0)) {
                $concluidos++
            }
        }
    }

    $total = 2
    $progress.Style = "Blocks"
    $progress.Value = [math]::Min([int](($concluidos / $total) * 100),100)

    if ($ativos -gt 0) {
        $progress.Style = "Marquee"
    }
    elseif ($concluidos -eq $total -or $downloadsAtivos.Count -gt 0) {
        $progress.Style = "Blocks"
    }
})

$timer.Start()

# =========================
# EVENTOS
# =========================
$btnChrome.Add_Click({
    Iniciar-DownloadExterno `
        -Nome "Chrome" `
        -Url "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" `
        -Arquivo "Chrome.msi" `
        -StatusLabel $stChrome `
        -LabelGeral $lblGeral `
        -Barra $progress
})

$btnAnyDesk.Add_Click({
    Iniciar-DownloadExterno `
        -Nome "AnyDesk" `
        -Url "https://download.anydesk.com/AnyDesk.exe" `
        -Arquivo "AnyDesk.exe" `
        -StatusLabel $stAnyDesk `
        -LabelGeral $lblGeral `
        -Barra $progress
})

$btnJava.Add_Click({
    try {
        Start-Process "https://www.java.com/pt-br/download/"
        Set-Status $stJava "Pagina aberta [OK]" "manual"
        $lblGeral.Text = "Pagina do Java aberta."
    }
    catch {
        Set-Status $stJava "Erro [X]" "erro"
        $lblGeral.Text = "Falha ao abrir pagina do Java."
    }
})

$btnAdobe.Add_Click({
    try {
        Start-Process "https://get.adobe.com/br/reader/"
        Set-Status $stAdobe "Pagina aberta [OK]" "manual"
        $lblGeral.Text = "Pagina do Adobe Reader aberta."
    }
    catch {
        Set-Status $stAdobe "Erro [X]" "erro"
        $lblGeral.Text = "Falha ao abrir pagina do Adobe Reader."
    }
})

$btnTudo.Add_Click({
    $btnChrome.PerformClick()
    Start-Sleep -Milliseconds 300
    $btnAnyDesk.PerformClick()
})

$btnFechar.Add_Click({
    $temAtivo = $false

    foreach ($item in $downloadsAtivos.Values) {
        if (-not $item.Finalizado) {
            $temAtivo = $true
            break
        }
    }

    if ($temAtivo) {
        [System.Windows.Forms.MessageBox]::Show(
            "Ainda existem downloads em andamento.",
            "Lynext"
        ) | Out-Null
        return
    }

    $form.Close()
})

[void]$form.ShowDialog()
