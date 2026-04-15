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
$bgMain      = [System.Drawing.Color]::FromArgb(12,12,12)
$bgPanel     = [System.Drawing.Color]::FromArgb(22,22,22)
$bgButton    = [System.Drawing.Color]::FromArgb(35,35,35)
$bgButton2   = [System.Drawing.Color]::FromArgb(55,55,55)
$fgMain      = [System.Drawing.Color]::FromArgb(235,235,235)
$fgSoft      = [System.Drawing.Color]::FromArgb(160,160,160)
$okColor     = [System.Drawing.Color]::FromArgb(110,220,140)
$errColor    = [System.Drawing.Color]::FromArgb(255,110,110)
$runColor    = [System.Drawing.Color]::FromArgb(255,190,80)
$manualColor = [System.Drawing.Color]::FromArgb(90,180,255)
$borderColor = [System.Drawing.Color]::FromArgb(60,60,60)

# =========================
# FUNCOES
# =========================
function Garantir-Pasta {
    param([string]$Pasta)

    if (!(Test-Path $Pasta)) {
        New-Item -ItemType Directory -Path $Pasta -Force | Out-Null
    }
}

function Criar-Label {
    param(
        [string]$Texto,
        [int]$X,
        [int]$Y,
        [int]$Tamanho = 10,
        [bool]$Negrito = $false,
        $Cor = $null
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Texto
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.BackColor = [System.Drawing.Color]::Transparent

    if ($Negrito) {
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", $Tamanho, [System.Drawing.FontStyle]::Bold)
    }
    else {
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", $Tamanho)
    }

    if ($null -ne $Cor) {
        $lbl.ForeColor = $Cor
    }
    else {
        $lbl.ForeColor = $fgMain
    }

    return $lbl
}

function Criar-Botao {
    param(
        [string]$Texto,
        [int]$X,
        [int]$Y,
        [int]$Largura = 120,
        [int]$Altura = 32
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Texto
    $btn.Size = New-Object System.Drawing.Size($Largura, $Altura)
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.UseVisualStyleBackColor = $false
    $btn.BackColor = $bgButton
    $btn.ForeColor = $fgMain
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = $borderColor
    $btn.FlatAppearance.MouseOverBackColor = $bgButton2
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(70,70,70)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function Criar-Painel {
    param(
        [int]$X,
        [int]$Y,
        [int]$Largura,
        [int]$Altura
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Largura, $Altura)
    $panel.BackColor = $bgPanel
    return $panel
}

function Set-Status {
    param(
        [System.Windows.Forms.Label]$Label,
        [string]$Texto,
        [string]$Tipo = "normal"
    )

    $Label.Text = $Texto

    switch ($Tipo) {
        "ok"      { $Label.ForeColor = $okColor }
        "erro"    { $Label.ForeColor = $errColor }
        "andando" { $Label.ForeColor = $runColor }
        "manual"  { $Label.ForeColor = $manualColor }
        default   { $Label.ForeColor = $fgSoft }
    }
}

function Iniciar-DownloadExterno {
    param(
        [string]$Nome,
        [string]$Url,
        [string]$Arquivo,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Label]$GeralLabel,
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
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command $script" `
            -WindowStyle Hidden `
            -PassThru

        $downloadsAtivos[$Nome] = [PSCustomObject]@{
            ProcessoId = $proc.Id
            Arquivo    = $saida
            Status     = $StatusLabel
            Finalizado = $false
        }

        Set-Status $StatusLabel "Baixando..." "andando"
        $GeralLabel.Text = "Baixando $Nome..."
        $Barra.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    }
    catch {
        Set-Status $StatusLabel "Erro [X]" "erro"
        $GeralLabel.Text = "Falha ao iniciar $Nome."
        $Barra.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    }
}

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.Size = New-Object System.Drawing.Size(700, 470)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Topmost = $true
$form.BackColor = $bgMain
$form.ForeColor = $fgMain

$titulo = Criar-Label "Central de Downloads" 225 18 16 $true
$form.Controls.Add($titulo)

$subtitulo = Criar-Label "Created by RyanGXD" 265 48 9 $false $fgSoft
$form.Controls.Add($subtitulo)

# =========================
# PAINEL AUTOMATICO
# =========================
$panelAuto = Criar-Painel 28 90 630 140
$form.Controls.Add($panelAuto)

$autoTitulo = Criar-Label "AUTOMATICO" 18 14 11 $true
$panelAuto.Controls.Add($autoTitulo)

$autoSub = Criar-Label "Baixa direto para Downloads\Instaladores" 18 38 9 $false $fgSoft
$panelAuto.Controls.Add($autoSub)

$chromeNome = Criar-Label "Chrome" 18 78 10 $false
$panelAuto.Controls.Add($chromeNome)

$chromeStatus = Criar-Label "Aguardando" 280 78 10 $false $fgSoft
$panelAuto.Controls.Add($chromeStatus)

$btnChrome = Criar-Botao "Baixar" 485 72 110 32
$panelAuto.Controls.Add($btnChrome)

$anydeskNome = Criar-Label "AnyDesk" 18 108 10 $false
$panelAuto.Controls.Add($anydeskNome)

$anydeskStatus = Criar-Label "Aguardando" 280 108 10 $false $fgSoft
$panelAuto.Controls.Add($anydeskStatus)

$btnAnyDesk = Criar-Botao "Baixar" 485 102 110 32
$panelAuto.Controls.Add($btnAnyDesk)

# =========================
# PAINEL MANUAL
# =========================
$panelManual = Criar-Painel 28 245 630 140
$form.Controls.Add($panelManual)

$manualTitulo = Criar-Label "MANUAL" 18 14 11 $true
$panelManual.Controls.Add($manualTitulo)

$manualSub = Criar-Label "Abre a pagina oficial para baixar manualmente" 18 38 9 $false $fgSoft
$panelManual.Controls.Add($manualSub)

$javaNome = Criar-Label "Java" 18 78 10 $false
$panelManual.Controls.Add($javaNome)

$javaStatus = Criar-Label "Aguardando" 280 78 10 $false $fgSoft
$panelManual.Controls.Add($javaStatus)

$btnJava = Criar-Botao "Abrir pagina" 455 72 140 32
$panelManual.Controls.Add($btnJava)

$adobeNome = Criar-Label "Adobe Reader" 18 108 10 $false
$panelManual.Controls.Add($adobeNome)

$adobeStatus = Criar-Label "Aguardando" 280 108 10 $false $fgSoft
$panelManual.Controls.Add($adobeStatus)

$btnAdobe = Criar-Botao "Abrir pagina" 455 102 140 32
$panelManual.Controls.Add($btnAdobe)

# =========================
# RODAPE
# =========================
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28, 395)
$progress.Size = New-Object System.Drawing.Size(420, 18)
$progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$geral = Criar-Label "Pronto para iniciar." 28 418 9 $false $fgSoft
$form.Controls.Add($geral)

$btnTudo = Criar-Botao "Baixar automaticos" 468 390 130 32
$form.Controls.Add($btnTudo)

$btnFechar = Criar-Botao "Fechar" 608 390 50 32
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
                        $geral.Text = "$nome concluido."
                    }
                    else {
                        Set-Status $info.Status "Erro [X]" "erro"
                        $geral.Text = "Falha em $nome."
                    }
                }
            }

            if ($info.Finalizado -and (Test-Path $info.Arquivo) -and ((Get-Item $info.Arquivo).Length -gt 0)) {
                $concluidos++
            }
        }
    }

    $total = 2
    if ($ativos -gt 0) {
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    }
    else {
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $progress.Value = [math]::Min([int](($concluidos / $total) * 100), 100)
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
        -StatusLabel $chromeStatus `
        -GeralLabel $geral `
        -Barra $progress
})

$btnAnyDesk.Add_Click({
    Iniciar-DownloadExterno `
        -Nome "AnyDesk" `
        -Url "https://download.anydesk.com/AnyDesk.exe" `
        -Arquivo "AnyDesk.exe" `
        -StatusLabel $anydeskStatus `
        -GeralLabel $geral `
        -Barra $progress
})

$btnJava.Add_Click({
    try {
        Start-Process "https://www.java.com/pt-br/download/"
        Set-Status $javaStatus "Pagina aberta [OK]" "manual"
        $geral.Text = "Pagina do Java aberta."
    }
    catch {
        Set-Status $javaStatus "Erro [X]" "erro"
        $geral.Text = "Falha ao abrir pagina do Java."
    }
})

$btnAdobe.Add_Click({
    try {
        Start-Process "https://get.adobe.com/br/reader/"
        Set-Status $adobeStatus "Pagina aberta [OK]" "manual"
        $geral.Text = "Pagina do Adobe Reader aberta."
    }
    catch {
        Set-Status $adobeStatus "Erro [X]" "erro"
        $geral.Text = "Falha ao abrir pagina do Adobe Reader."
    }
})

$btnTudo.Add_Click({
    $btnChrome.PerformClick()
    Start-Sleep -Milliseconds 250
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
