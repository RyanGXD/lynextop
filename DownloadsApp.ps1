Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# CONFIG
# =========================
$destinoBase = Join-Path $env:USERPROFILE "Downloads\Instaladores"

$apps = @(
    [PSCustomObject]@{
        Nome    = "Chrome"
        Arquivo = "Chrome.msi"
        Url     = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
        Tipo    = "download"
    },
    [PSCustomObject]@{
        Nome    = "Java"
        Arquivo = "Java_x64.exe"
        Url     = "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=252907_0d06828d282343ea81775b28020a7cd3"
        Tipo    = "download"
    },
    [PSCustomObject]@{
        Nome    = "Adobe Reader"
        Arquivo = ""
        Url     = "https://get.adobe.com/br/reader/"
        Tipo    = "pagina"
    },
    [PSCustomObject]@{
        Nome    = "AnyDesk"
        Arquivo = "AnyDesk.exe"
        Url     = "https://download.anydesk.com/AnyDesk.exe"
        Tipo    = "download"
    }
)

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.Size = New-Object System.Drawing.Size(560,380)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Topmost = $true
$form.BackColor = [System.Drawing.Color]::White

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text = "Central de Downloads"
$titulo.Font = New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold)
$titulo.AutoSize = $true
$titulo.Location = New-Object System.Drawing.Point(170,18)
$form.Controls.Add($titulo)

$subtitulo = New-Object System.Windows.Forms.Label
$subtitulo.Text = "Downloads em segundo plano com status em tempo real"
$subtitulo.Font = New-Object System.Drawing.Font("Segoe UI",9)
$subtitulo.AutoSize = $true
$subtitulo.ForeColor = [System.Drawing.Color]::DimGray
$subtitulo.Location = New-Object System.Drawing.Point(120,48)
$form.Controls.Add($subtitulo)

$labelsStatus = @{}
$y = 95

foreach ($app in $apps) {
    $lblNome = New-Object System.Windows.Forms.Label
    $lblNome.Text = $app.Nome
    $lblNome.Font = New-Object System.Drawing.Font("Segoe UI",10)
    $lblNome.AutoSize = $true
    $lblNome.Location = New-Object System.Drawing.Point(35,$y)
    $form.Controls.Add($lblNome)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Aguardando"
    $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI",10)
    $lblStatus.AutoSize = $true
    $lblStatus.Location = New-Object System.Drawing.Point(390,$y)
    $lblStatus.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($lblStatus)

    $labelsStatus[$app.Nome] = $lblStatus
    $y += 38
}

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Size = New-Object System.Drawing.Size(470,20)
$progress.Location = New-Object System.Drawing.Point(35,255)
$progress.Style = "Blocks"
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$lblGeral = New-Object System.Windows.Forms.Label
$lblGeral.Text = "Pronto para iniciar."
$lblGeral.Font = New-Object System.Drawing.Font("Segoe UI",9)
$lblGeral.AutoSize = $true
$lblGeral.Location = New-Object System.Drawing.Point(35,285)
$lblGeral.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblGeral)

$chkAbrirPaginas = New-Object System.Windows.Forms.CheckBox
$chkAbrirPaginas.Text = "Abrir pagina oficial junto"
$chkAbrirPaginas.AutoSize = $true
$chkAbrirPaginas.Location = New-Object System.Drawing.Point(35,310)
$chkAbrirPaginas.Font = New-Object System.Drawing.Font("Segoe UI",9)
$form.Controls.Add($chkAbrirPaginas)

$btnBaixarTodos = New-Object System.Windows.Forms.Button
$btnBaixarTodos.Text = "Baixar Todos"
$btnBaixarTodos.Size = New-Object System.Drawing.Size(140,34)
$btnBaixarTodos.Location = New-Object System.Drawing.Point(235,305)
$form.Controls.Add($btnBaixarTodos)

$btnFechar = New-Object System.Windows.Forms.Button
$btnFechar.Text = "Fechar"
$btnFechar.Size = New-Object System.Drawing.Size(100,34)
$btnFechar.Location = New-Object System.Drawing.Point(390,305)
$form.Controls.Add($btnFechar)

# =========================
# WORKER
# =========================
$worker = New-Object System.ComponentModel.BackgroundWorker
$worker.WorkerReportsProgress = $true

$worker.add_DoWork({
    param($sender, $e)

    try {
        $payload = $e.Argument
        $listaApps = $payload.Apps
        $abrirPaginas = $payload.AbrirPaginas
        $pastaDestino = $payload.Destino

        if (!(Test-Path $pastaDestino)) {
            New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
        }

        $sender.ReportProgress(1, [PSCustomObject]@{
            Nome = ""
            Status = ""
            Geral = "Pasta criada: $pastaDestino"
        })

        $total = $listaApps.Count
        $indice = 0

        foreach ($app in $listaApps) {
            $indice++
            $percentBase = [int](($indice - 1) / $total * 100)
            $percentFim  = [int]($indice / $total * 100)

            $sender.ReportProgress($percentBase, [PSCustomObject]@{
                Nome = $app.Nome
                Status = "Baixando..."
                Geral = "Processando $($app.Nome)..."
            })

            try {
                if ($abrirPaginas -and $app.Url) {
                    Start-Process $app.Url | Out-Null
                }

                if ($app.Tipo -eq "download") {
                    $saida = Join-Path $pastaDestino $app.Arquivo

                    if (Test-Path $saida) {
                        Remove-Item $saida -Force -ErrorAction SilentlyContinue
                    }

                    Invoke-WebRequest -Uri $app.Url -OutFile $saida -UseBasicParsing

                    if ((Test-Path $saida) -and ((Get-Item $saida).Length -gt 0)) {
                        $sender.ReportProgress($percentFim, [PSCustomObject]@{
                            Nome = $app.Nome
                            Status = "Concluido  [OK]"
                            Geral = "$($app.Nome) concluido."
                        })
                    }
                    else {
                        throw "Arquivo vazio ou inexistente."
                    }
                }
                elseif ($app.Tipo -eq "pagina") {
                    Start-Process $app.Url | Out-Null

                    $sender.ReportProgress($percentFim, [PSCustomObject]@{
                        Nome = $app.Nome
                        Status = "Pagina aberta  [OK]"
                        Geral = "Pagina de $($app.Nome) aberta."
                    })
                }
                else {
                    throw "Tipo invalido."
                }
            }
            catch {
                $sender.ReportProgress($percentFim, [PSCustomObject]@{
                    Nome = $app.Nome
                    Status = "Erro  [X]"
                    Geral = "Falha em $($app.Nome): $($_.Exception.Message)"
                })
            }
        }
    }
    catch {
        $sender.ReportProgress(0, [PSCustomObject]@{
            Nome = ""
            Status = ""
            Geral = "Erro geral: $($_.Exception.Message)"
        })
    }
})

$worker.add_ProgressChanged({
    param($sender, $e)

    $data = $e.UserState

    if ($null -ne $data) {
        if ($data.Nome -and $labelsStatus.ContainsKey($data.Nome)) {
            $labelsStatus[$data.Nome].Text = $data.Status

            if ($data.Status -like "Baixando*") {
                $labelsStatus[$data.Nome].ForeColor = [System.Drawing.Color]::DarkOrange
                $progress.Style = "Marquee"
            }
            elseif ($data.Status -like "Concluido*") {
                $labelsStatus[$data.Nome].ForeColor = [System.Drawing.Color]::ForestGreen
                $progress.Style = "Blocks"
                $progress.Value = [Math]::Min($e.ProgressPercentage, 100)
            }
            elseif ($data.Status -like "Pagina aberta*") {
                $labelsStatus[$data.Nome].ForeColor = [System.Drawing.Color]::SteelBlue
                $progress.Style = "Blocks"
                $progress.Value = [Math]::Min($e.ProgressPercentage, 100)
            }
            elseif ($data.Status -like "Erro*") {
                $labelsStatus[$data.Nome].ForeColor = [System.Drawing.Color]::Crimson
                $progress.Style = "Blocks"
                $progress.Value = [Math]::Min($e.ProgressPercentage, 100)
            }
        }

        if ($data.Geral) {
            $lblGeral.Text = $data.Geral
        }
    }
})

$worker.add_RunWorkerCompleted({
    param($sender, $e)

    $progress.Style = "Blocks"
    $progress.Value = 100
    $lblGeral.Text = "Processo finalizado."
    $btnBaixarTodos.Enabled = $true
    $chkAbrirPaginas.Enabled = $true
})

# =========================
# EVENTOS
# =========================
$btnBaixarTodos.Add_Click({
    if (-not $worker.IsBusy) {
        foreach ($app in $apps) {
            $labelsStatus[$app.Nome].Text = "Na fila..."
            $labelsStatus[$app.Nome].ForeColor = [System.Drawing.Color]::Gray
        }

        $progress.Value = 0
        $progress.Style = "Blocks"
        $lblGeral.Text = "Iniciando..."
        $btnBaixarTodos.Enabled = $false
        $chkAbrirPaginas.Enabled = $false

        $worker.RunWorkerAsync([PSCustomObject]@{
            Apps = $apps
            AbrirPaginas = $chkAbrirPaginas.Checked
            Destino = $destinoBase
        })
    }
})

$btnFechar.Add_Click({
    if (-not $worker.IsBusy) {
        $form.Close()
    }
})

[void]$form.ShowDialog()
