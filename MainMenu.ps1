Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# CONFIG
# =========================
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Arquivos dos modulos
$modules = @{
    "Rede"        = "NetworkApp.ps1"
    "Desempenho"  = "PerformanceApp.ps1"
    "Downloads"   = "DownloadsApp.ps1"
}

# =========================
# CORES
# =========================
$bgMain        = [System.Drawing.Color]::FromArgb(10,10,10)
$bgCard        = [System.Drawing.Color]::FromArgb(20,20,20)
$bgButton      = [System.Drawing.Color]::FromArgb(30,30,30)
$bgButtonHover = [System.Drawing.Color]::FromArgb(45,45,45)
$bgButtonDown  = [System.Drawing.Color]::FromArgb(60,60,60)
$fgMain        = [System.Drawing.Color]::FromArgb(235,235,235)
$fgSoft        = [System.Drawing.Color]::FromArgb(150,150,150)
$accent        = [System.Drawing.Color]::FromArgb(85,255,140)
$warnColor     = [System.Drawing.Color]::FromArgb(255,190,80)
$errorColor    = [System.Drawing.Color]::FromArgb(255,110,110)
$borderColor   = [System.Drawing.Color]::FromArgb(55,55,55)

# =========================
# FUNCOES
# =========================
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
        [int]$Largura = 180,
        [int]$Altura = 58
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Texto
    $btn.Size = New-Object System.Drawing.Size($Largura, $Altura)
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.UseVisualStyleBackColor = $false
    $btn.BackColor = $bgButton
    $btn.ForeColor = $fgMain
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = $borderColor
    $btn.FlatAppearance.MouseOverBackColor = $bgButtonHover
    $btn.FlatAppearance.MouseDownBackColor = $bgButtonDown
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function Criar-Painel {
    param(
        [int]$X,
        [int]$Y,
        [int]$Largura,
        [int]$Altura,
        $Cor = $null
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Largura, $Altura)

    if ($null -ne $Cor) {
        $panel.BackColor = $Cor
    }
    else {
        $panel.BackColor = $bgCard
    }

    return $panel
}

function Abrir-Modulo {
    param(
        [string]$NomeModulo
    )

    if (-not $modules.ContainsKey($NomeModulo)) {
        $script:statusLabel.Text = "Modulo invalido."
        $script:statusLabel.ForeColor = $errorColor
        return
    }

    $arquivo = $modules[$NomeModulo]
    $caminho = Join-Path $baseDir $arquivo

    if (!(Test-Path $caminho)) {
        $script:statusLabel.Text = "$arquivo nao foi encontrado."
        $script:statusLabel.ForeColor = $warnColor
        return
    }

    try {
        $script:statusLabel.Text = "Abrindo $NomeModulo..."
        $script:statusLabel.ForeColor = $accent
        $form.Refresh()

        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$caminho`""
        
        Start-Sleep -Milliseconds 200

        $script:statusLabel.Text = "Pronto."
        $script:statusLabel.ForeColor = $fgSoft
    }
    catch {
        $script:statusLabel.Text = "Falha ao abrir $NomeModulo."
        $script:statusLabel.ForeColor = $errorColor
    }
}

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext"
$form.Size = New-Object System.Drawing.Size(760, 520)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.BackColor = $bgMain
$form.ForeColor = $fgMain
$form.Topmost = $false

# =========================
# TOPO
# =========================
$titulo = Criar-Label "Lynext" 320 24 24 $true
$form.Controls.Add($titulo)

$linha = New-Object System.Windows.Forms.Panel
$linha.Location = New-Object System.Drawing.Point(245, 66)
$linha.Size = New-Object System.Drawing.Size(260, 2)
$linha.BackColor = $accent
$form.Controls.Add($linha)

$subtitulo = Criar-Label "Central principal de modulos" 273 78 10 $false $fgSoft
$form.Controls.Add($subtitulo)

# =========================
# CARD CENTRAL
# =========================
$card = Criar-Painel 45 120 650 280
$form.Controls.Add($card)

$cardTitulo = Criar-Label "MENU PRINCIPAL" 25 22 12 $true
$card.Controls.Add($cardTitulo)

$cardSub = Criar-Label "Escolha um modulo para abrir" 25 48 9 $false $fgSoft
$card.Controls.Add($cardSub)

# =========================
# BOTOES
# =========================
$btnRede = Criar-Botao "REDE" 25 90 180 56
$card.Controls.Add($btnRede)

$btnDesempenho = Criar-Botao "DESEMPENHO" 235 90 180 56
$card.Controls.Add($btnDesempenho)

$btnDownloads = Criar-Botao "DOWNLOADS" 445 90 180 56
$card.Controls.Add($btnDownloads)

$btnSair = Criar-Botao "SAIR" 235 170 180 56
$card.Controls.Add($btnSair)

# =========================
# RODAPE
# =========================
$statusBox = Criar-Painel 45 420 650 48 ([System.Drawing.Color]::FromArgb(16,16,16))
$form.Controls.Add($statusBox)

$statusTitulo = Criar-Label "STATUS" 18 15 9 $true
$statusBox.Controls.Add($statusTitulo)

$statusLabel = Criar-Label "Pronto." 80 15 9 $false $fgSoft
$statusBox.Controls.Add($statusLabel)

$creditos = Criar-Label "Created by Ryan" 323 478 9 $false $fgSoft
$form.Controls.Add($creditos)

# =========================
# EVENTOS
# =========================
$btnRede.Add_Click({
    Abrir-Modulo -NomeModulo "Rede"
})

$btnDesempenho.Add_Click({
    Abrir-Modulo -NomeModulo "Desempenho"
})

$btnDownloads.Add_Click({
    Abrir-Modulo -NomeModulo "Downloads"
})

$btnSair.Add_Click({
    $form.Close()
})

foreach ($btn in @($btnRede, $btnDesempenho, $btnDownloads, $btnSair)) {
    $btn.Add_MouseEnter({
        $statusLabel.Text = "Selecionado: $($this.Text)"
        $statusLabel.ForeColor = $accent
    })

    $btn.Add_MouseLeave({
        $statusLabel.Text = "Pronto."
        $statusLabel.ForeColor = $fgSoft
    })
}

[void]$form.ShowDialog()
