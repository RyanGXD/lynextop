Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# CONFIG
# =========================
$destinoBase = Join-Path $env:USERPROFILE "Downloads\Instaladores"

$apps = @(
    [PSCustomObject]@{
        Nome       = "Chrome"
        Tipo       = "download"
        Arquivo    = "Chrome.msi"
        Url        = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
        Pagina     = "https://www.google.com/intl/pt-BR/chrome/"
    },
    [PSCustomObject]@{
        Nome       = "Java"
        Tipo       = "pagina"
        Arquivo    = ""
        Url        = ""
        Pagina     = "https://www.java.com/pt-br/download/manual.jsp"
    },
    [PSCustomObject]@{
        Nome       = "Adobe Reader"
        Tipo       = "pagina"
        Arquivo    = ""
        Url        = ""
        Pagina     = "https://get.adobe.com/br/reader/"
    },
    [PSCustomObject]@{
        Nome       = "AnyDesk"
        Tipo       = "download"
        Arquivo    = "AnyDesk.exe"
        Url        = "https://download.anydesk.com/AnyDesk.exe"
        Pagina     = "https://anydesk.com/pt/downloads/windows"
    }
)

# Estado por app
$estado = @{}

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.Size = New-Object System.Drawing.Size(560, 390)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Topmost = $true
$form.BackColor = [System.Drawing.Color]::White

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text = "Central de Downloads"
$titulo.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$titulo.AutoSize = $true
$titulo.Location = New-Object System.Drawing.Point(170, 18)
$form.Controls.Add($titulo)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Janela leve, downloads em processo separado e status ao vivo"
$sub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$sub.AutoSize = $true
$sub.ForeColor = [System.Drawing.Color]::DimGray
$sub.Location = New-Object System.Drawing.Point(105, 48)
$form.Controls.Add($sub)

$labelsStatus = @{}
$y = 95

foreach ($app in $apps) {
    $lblNome = New-Object System.Windows.Forms.Label
    $lblNome.Text = $app.Nome
    $lblNome.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblNome.AutoSize = $true
    $lblNome.Location = New-Object System.Drawing.Point(35, $y)
    $form.Controls.Add($lblNome)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Aguardando"
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblStatus.AutoSize = $true
    $lblStatus.Location = New-Object System.Drawing.Point(385, $y)
    $lblStatus.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($lblStatus)

    $labelsStatus[$app.Nome] = $lblStatus
    $y += 38
}

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size = New-Object System.Drawing.Size(470, 20)
$progress.Location = New-Object System.Drawing.Point(35, 255)
$progress.Style = "Blocks"
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$lblGeral = New-Object System.Windows.Forms.Label
$lblGeral.Text = "Pronto para iniciar."
$lblGeral.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblGeral.AutoSize = $true
$lblGeral.Location = New-Object System.Drawing.Point(35, 285)
$lblGeral.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblGeral)

$chkAbrirPaginas = New-Object System.Windows.Forms.CheckBox
$chkAbrirPaginas.Text = "Abrir paginas oficiais junto"
$chkAbrirPaginas.AutoSize = $true
$chkAbrirPaginas.Location = New-Object System.Drawing.Point(35, 312)
$chkAbrirPaginas.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkAbrirPaginas.Checked = $true
$form.Controls.Add($chkAbrirPaginas)

$btnBaixarTodos = New-Object System.Windows.Forms.Button
$btnBaixarTodos.Text = "Baixar Todos"
$btnBaixarTodos.Size = New-Object System.Drawing.Size(140, 34)
$btnBaixarTodos.Location = New-Object System.Drawing.Point(235, 307)
$form.Controls.Add($btnBaixarTodos)

$btnFechar = New-Object System.Windows.Forms.Button
$btnFechar.Text = "Fechar"
$btnFechar.Size = New-Object System.Drawing.Size(100, 34)
$btnFechar.Location = New-Object System.Drawing.Point(390, 307)
$form.Controls.Add($btnFechar)

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
        [string]$Nome,
        [string]$Texto,
        [string]$Cor = "Gray"
    )

    if ($labelsStatus.ContainsKey($Nome)) {
        $labelsStatus[$Nome].Text = $Texto
        switch ($Cor) {
            "Orange" { $labelsStatus[$Nome].ForeColor = [System.Drawing.Color]::DarkOrange }
            "Green"  { $labelsStatus[$Nome].ForeColor = [System.Drawing.Color]::ForestGreen }
            "Red"    { $labelsStatus[$Nome].ForeColor = [System.Drawing.Color]::Crimson }
            "Blue"   { $labelsStatus[$Nome].ForeColor = [System.Drawing.Color]::SteelBlue }
            default  { $labelsStatus[$Nome].ForeColor = [System.Drawing.Color]::Gray }
        }
    }
}

function Iniciar-DownloadExterno {
    param(
        [string]$Nome,
        [string]$Url,
        [string]$Arquivo
    )

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

    $estado[$Nome] = [PSCustomObject]@{
        Tipo       = "download"
        ProcessoId = $proc.Id
        Arquivo    = $saida
        Iniciado   = Get-Date
        Finalizado = $false
    }

    Set-Status $Nome "Baixando..." "Orange"
    $lblGeral.Text = "Baixando $Nome..."
    $progress.Style = "Marquee"
}

function Abrir-Pagina {
    param(
        [string]$Nome,
        [string]$Pagina
    )

    try {
        Start-Process $Pagina | Out-Null
        $estado[$Nome] = [PSCustomObject]@{
            Tipo       = "pagina"
            ProcessoId = $null
            Arquivo    = ""
            Iniciado   = Get-Date
            Finalizado = $true
        }

        Set-Status $Nome "Pagina aberta  [OK]" "Blue"
        $lblGeral.Text = "Pagina de $Nome aberta."
    }
    catch {
        Set-Status $Nome "Erro  [X]" "Red"
        $lblGeral.Text = "Falha ao abrir $Nome."
    }
}

function Atualizar-ProgressoGeral {
    $total = $apps.Count
    $ok = 0

    foreach ($app in $apps) {
        $txt = $labelsStatus[$app.Nome].Text
        if ($txt -like "Concluido*" -or $txt -like "Pagina aberta*") {
            $ok++
        }
    }

    $valor = [int](($ok / $total) * 100)
    $progress.Style = "Blocks"
    $progress.Value = [Math]::Min($valor, 100)
}

# =========================
# TIMER DE MONITORAMENTO
# =========================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 600

$timer.Add_Tick({
    $algumDownloadAtivo = $false

    foreach ($app in $apps) {
        if ($estado.ContainsKey($app.Nome)) {
            $info = $estado[$app.Nome]

            if ($info.Tipo -eq "download" -and -not $info.Finalizado) {
                $algumDownloadAtivo = $true

                $proc = Get-Process -Id $info.ProcessoId -ErrorAction SilentlyContinue
                $arquivoExiste = Test-Path $info.Arquivo

                if ($proc) {
                    if ($arquivoExiste) {
                        try {
                            $tamanho = (Get-Item $info.Arquivo).Length
                            if ($tamanho -gt 0) {
                                $kb = [math]::Round($tamanho / 1KB, 0)
                                Set-Status $app.Nome "Baixando... $kb KB" "Orange"
                            }
                        }
                        catch {}
                    }
                }
                else {
                    $info.Finalizado = $true
                    $estado[$app.Nome] = $info

                    if ($arquivoExiste -and ((Get-Item $info.Arquivo).Length -gt 0)) {
                        Set-Status $app.Nome "Concluido  [OK]" "Green"
                        $lblGeral.Text = "$($app.Nome) concluido."
                    }
                    else {
                        Set-Status $app.Nome "Erro  [X]" "Red"
                        $lblGeral.Text = "Falha em $($app.Nome)."
                    }

                    Atualizar-ProgressoGeral
                }
            }
        }
    }

    if (-not $algumDownloadAtivo) {
        Atualizar-ProgressoGeral

        if ($progress.Value -ge 100) {
            $lblGeral.Text = "Processo finalizado."
            $btnBaixarTodos.Enabled = $true
            $chkAbrirPaginas.Enabled = $true
        }
    }
})

# =========================
# EVENTOS
# =========================
$btnBaixarTodos.Add_Click({
    Garantir-Pasta $destinoBase

    foreach ($app in $apps) {
        Set-Status $app.Nome "Na fila..." "Gray"
    }

    $lblGeral.Text = "Iniciando..."
    $progress.Value = 0
    $progress.Style = "Blocks"
    $btnBaixarTodos.Enabled = $false
    $chkAbrirPaginas.Enabled = $false
    $estado.Clear()

    foreach ($app in $apps) {
        if ($app.Tipo -eq "download") {
            if ($chkAbrirPaginas.Checked -and $app.Pagina) {
                try { Start-Process $app.Pagina | Out-Null } catch {}
            }

            Iniciar-DownloadExterno -Nome $app.Nome -Url $app.Url -Arquivo $app.Arquivo
        }
        elseif ($app.Tipo -eq "pagina") {
            Abrir-Pagina -Nome $app.Nome -Pagina $app.Pagina
        }
    }

    $timer.Start()
})

$btnFechar.Add_Click({
    $downloadsAtivos = $false

    foreach ($item in $estado.GetEnumerator()) {
        if ($item.Value.Tipo -eq "download" -and -not $item.Value.Finalizado) {
            $downloadsAtivos = $true
            break
        }
    }

    if ($downloadsAtivos) {
        [System.Windows.Forms.MessageBox]::Show(
            "Ainda existem downloads em andamento.",
            "Lynext"
        ) | Out-Null
        return
    }

    $form.Close()
})

[void]$form.ShowDialog()
