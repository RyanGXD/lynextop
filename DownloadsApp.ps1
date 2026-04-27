Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# CONFIG
# =========================
$destinoBase = Join-Path $env:USERPROFILE "Downloads\Instaladores"
$downloadsAtivos = @{}
$statusApps = @{}
$categoryViews = @{}

# =========================
# CORES
# =========================
$bgMain      = [System.Drawing.Color]::FromArgb(14,14,18)
$bgPanel     = [System.Drawing.Color]::FromArgb(22,22,30)
$bgPanel2    = [System.Drawing.Color]::FromArgb(28,28,38)
$bgButton    = [System.Drawing.Color]::FromArgb(44,44,58)
$bgButton2   = [System.Drawing.Color]::FromArgb(60,60,78)
$bgList      = [System.Drawing.Color]::FromArgb(16,16,22)

$fgMain      = [System.Drawing.Color]::FromArgb(232,232,238)
$fgSoft      = [System.Drawing.Color]::FromArgb(165,165,182)
$accent      = [System.Drawing.Color]::FromArgb(132,108,186)
$accentSoft  = [System.Drawing.Color]::FromArgb(90,76,132)

$okColor     = [System.Drawing.Color]::FromArgb(110,200,140)
$errColor    = [System.Drawing.Color]::FromArgb(220,100,100)
$runColor    = [System.Drawing.Color]::FromArgb(220,180,100)
$manualColor = [System.Drawing.Color]::FromArgb(120,175,235)

$borderColor = [System.Drawing.Color]::FromArgb(72,72,90)
$tabBackColor = [System.Drawing.Color]::FromArgb(52,52,62)

# =========================
# BASE DE APPS
# =========================
$apps = @(
    [PSCustomObject]@{
        Nome = "CapFrameX"
        Categoria = "Performance"
        Tipo = "Manual"
        Descricao = "Captura e analisa frametimes, FPS e percentis. Bom para comparar testes e validar se um tweak realmente melhorou o jogo."
        Metodo = "Pagina"
        Url = "https://www.capframex.com/download"
        Arquivo = ""
        Fonte = "Pagina oficial"
    }
    [PSCustomObject]@{
        Nome = "ISLC"
        Categoria = "Performance"
        Tipo = "Automatico"
        Descricao = "Gerencia a standby list da memoria para reduzir travadas e melhorar a responsividade em jogos e multitarefa."
        Metodo = "ISLCLatest"
        Url = "https://www.wagnardsoft.com/intelligent-standby-list-cleaner-islc"
        Arquivo = "ISLC.exe"
        Fonte = "Site oficial (ultima versao)"
    }
    [PSCustomObject]@{
        Nome = "MSI Afterburner"
        Categoria = "Performance"
        Tipo = "Manual"
        Descricao = "Ferramenta de overclock, undervolt, fan curve e monitoramento da GPU. Ideal para ajuste fino e teste de estabilidade."
        Metodo = "Pagina"
        Url = "https://br.msi.com/Landing/afterburner/graphics-cards"
        Arquivo = ""
        Fonte = "Pagina oficial"
    }
    [PSCustomObject]@{
        Nome = "MSI Utility v3"
        Categoria = "Performance"
        Tipo = "Automatico"
        Descricao = "Utilitario usado para ajustar politicas MSI e prioridade de interrupcoes em dispositivos PCIe."
        Metodo = "Direto"
        Url = "https://raw.githubusercontent.com/Sathango/Msi-Utility-v3/main/Msi%20Utility%20v3.exe"
        Arquivo = "MsiUtilityV3.exe"
        Fonte = "GitHub raw"
    }
    [PSCustomObject]@{
        Nome = "NVIDIA Profile Inspector"
        Categoria = "Performance"
        Tipo = "Automatico"
        Descricao = "Editor avancado dos perfis internos da NVIDIA. Aqui ele baixa a ultima release estavel automaticamente."
        Metodo = "GitHubLatestZip"
        Url = "https://api.github.com/repos/Orbmu2k/nvidiaProfileInspector/releases"
        Arquivo = "NVIDIAProfileInspector.zip"
        Fonte = "GitHub latest stable"
    }
    [PSCustomObject]@{
        Nome = "Power Settings Explorer"
        Categoria = "Performance"
        Tipo = "Manual"
        Descricao = "Mostra e libera opcoes avancadas dos planos de energia do Windows para ajuste fino de desempenho e latencia."
        Metodo = "Pagina"
        Url = "https://www.mediafire.com/file/wt37sbsejk7iepm/PowerSettingsExplorer.zip"
        Arquivo = ""
        Fonte = "MediaFire"
    }
    [PSCustomObject]@{
        Nome = "Process Lasso"
        Categoria = "Performance"
        Tipo = "Manual"
        Descricao = "Automacao e ajuste de afinidade, prioridade e comportamento de processos para manter o sistema responsivo."
        Metodo = "Pagina"
        Url = "https://bitsum.com/download-process-lasso/"
        Arquivo = ""
        Fonte = "Pagina oficial"
    }
    [PSCustomObject]@{
        Nome = "hidusbf"
        Categoria = "Performance"
        Tipo = "Automatico"
        Descricao = "Utilitario para ajuste de polling rate de dispositivos USB/HID. Muito usado para mouse, mas exige cuidado."
        Metodo = "Direto"
        Url = "https://raw.githubusercontent.com/LordOfMice/hidusbf/master/hidusbf.zip"
        Arquivo = "hidusbf.zip"
        Fonte = "GitHub raw"
    }
    [PSCustomObject]@{
        Nome = "CPU-Z"
        Categoria = "Monitoramento"
        Tipo = "Manual"
        Descricao = "Mostra informacoes detalhadas do processador, placa-mae, memoria e clocks em tempo real."
        Metodo = "Pagina"
        Url = "https://www.cpuid.com/softwares/cpu-z.html"
        Arquivo = ""
        Fonte = "Pagina oficial"
    }
    [PSCustomObject]@{
        Nome = "HWiNFO"
        Categoria = "Monitoramento"
        Tipo = "Manual"
        Descricao = "Uma das melhores ferramentas para sensores, temperaturas, consumo, clocks, VRM e diagnostico geral do hardware."
        Metodo = "Pagina"
        Url = "https://www.hwinfo.com/download/"
        Arquivo = ""
        Fonte = "Pagina oficial"
    }
    [PSCustomObject]@{
        Nome = "LatencyMon"
        Categoria = "Monitoramento"
        Tipo = "Automatico"
        Descricao = "Analisa DPC, ISR e pagefaults para identificar gargalos de latencia e problemas que causam stutter ou audio drop."
        Metodo = "Direto"
        Url = "https://www.resplendence.com/download/LatencyMon.exe"
        Arquivo = "LatencyMon.exe"
        Fonte = "Download direto oficial"
    }
    [PSCustomObject]@{
        Nome = "OCCT"
        Categoria = "Monitoramento"
        Tipo = "Manual"
        Descricao = "Ferramenta de stress test e validacao para CPU, GPU, memoria, VRAM e fonte. Boa para estabilidade."
        Metodo = "Pagina"
        Url = "https://www.ocbase.com/download"
        Arquivo = ""
        Fonte = "Pagina oficial"
    }
    [PSCustomObject]@{
        Nome = "Adobe Reader"
        Categoria = "Suporte"
        Tipo = "Automatico"
        Descricao = "Leitor de PDF oficial da Adobe. Baixa o instalador offline MUI oficial, sem ofertas extras como McAfee ou Adobe Express."
        Metodo = "AdobeReaderLatest"
        Url = "https://get.adobe.com/br/reader/"
        Arquivo = "AdobeReader_x64_MUI.exe"
        Fonte = "Adobe CDN oficial sem ofertas extras"
    }
    [PSCustomObject]@{
        Nome = "AnyDesk"
        Categoria = "Suporte"
        Tipo = "Automatico"
        Descricao = "Acesso remoto leve e rapido para suporte tecnico e manutencao a distancia."
        Metodo = "Direto"
        Url = "https://download.anydesk.com/AnyDesk.exe"
        Arquivo = "AnyDesk.exe"
        Fonte = "Download direto oficial"
    }
    [PSCustomObject]@{
        Nome = "Chrome"
        Categoria = "Suporte"
        Tipo = "Automatico"
        Descricao = "Navegador da Google. Aqui usa o instalador enterprise 64-bit para download direto."
        Metodo = "Direto"
        Url = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
        Arquivo = "Chrome.msi"
        Fonte = "Download direto oficial"
    }
    [PSCustomObject]@{
        Nome = "Java"
        Categoria = "Suporte"
        Tipo = "Automatico"
        Descricao = "Oracle Java para aplicativos de desktop. Baixa automaticamente o instalador Windows Off-line 64 bits da pagina oficial."
        Metodo = "JavaLatest"
        Url = "https://www.java.com/pt-BR/download/manual.jsp"
        Arquivo = "JavaSetup64.exe"
        Fonte = "Oracle Java oficial"
    }
)

# =========================
# FUNCOES VISUAIS
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
        [int]$Largura = 140,
        [int]$Altura = 34
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
    $btn.FlatAppearance.MouseDownBackColor = $accentSoft
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function Criar-Painel {
    param(
        [int]$X,
        [int]$Y,
        [int]$Largura,
        [int]$Altura,
        $Cor = $bgPanel
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Largura, $Altura)
    $panel.BackColor = $Cor
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    return $panel
}

function Criar-Lista {
    param(
        [int]$X,
        [int]$Y,
        [int]$Largura,
        [int]$Altura
    )

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point($X, $Y)
    $list.Size = New-Object System.Drawing.Size($Largura, $Altura)
    $list.BackColor = $bgList
    $list.ForeColor = $fgMain
    $list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $list.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $list.IntegralHeight = $false
    $list.DisplayMember = "Nome"
    $list.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $list.ItemHeight = 24

    $list.Add_DrawItem({
        param($sender, $e)

        if ($e.Index -lt 0) {
            return
        }

        $item = $sender.Items[$e.Index]
        $status = Get-AppStatusInfo $item.Nome
        $dotColor = Get-AppStatusColor $status.Tipo

        $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected)
        $backBrush = if ($isSelected) {
            New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35,115,190))
        }
        else {
            New-Object System.Drawing.SolidBrush($sender.BackColor)
        }

        $textBrush = if ($isSelected) {
            New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        }
        else {
            New-Object System.Drawing.SolidBrush($sender.ForeColor)
        }

        $dotBrush = New-Object System.Drawing.SolidBrush($dotColor)

        try {
            $e.Graphics.FillRectangle($backBrush, $e.Bounds)
            $dotRect = New-Object System.Drawing.Rectangle(($e.Bounds.Left + 8), ($e.Bounds.Top + 7), 10, 10)
            $e.Graphics.FillEllipse($dotBrush, $dotRect)

            $textRect = New-Object System.Drawing.RectangleF(
                ($e.Bounds.Left + 26),
                ($e.Bounds.Top + 3),
                ($e.Bounds.Width - 32),
                ($e.Bounds.Height - 4)
            )

            $e.Graphics.DrawString($item.Nome, $sender.Font, $textBrush, $textRect)
        }
        finally {
            $backBrush.Dispose()
            $textBrush.Dispose()
            $dotBrush.Dispose()
        }
    }.GetNewClosure())

    return $list
}

function Criar-TextoLeitura {
    param(
        [int]$X,
        [int]$Y,
        [int]$Largura,
        [int]$Altura
    )

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point($X, $Y)
    $txt.Size = New-Object System.Drawing.Size($Largura, $Altura)
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txt.BackColor = $bgList
    $txt.ForeColor = $fgMain
    $txt.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    return $txt
}

function Set-Status {
    param(
        [System.Windows.Forms.Control]$Label,
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

function Get-AppStatusColor {
    param([string]$Tipo)

    switch ($Tipo) {
        "ok"      { return $okColor }
        "andando" { return $runColor }
        "manual"  { return $manualColor }
        default   { return $errColor }
    }
}

function AtualizarIndicadoresListas {
    foreach ($categoria in $categoryViews.Keys) {
        $view = $categoryViews[$categoria]
        $view.ListaAuto.Invalidate()
        $view.ListaManual.Invalidate()
    }
}

# =========================
# FUNCOES DE DOWNLOAD
# =========================
function Get-WebHeaders {
    return @{
        "User-Agent" = "Mozilla/5.0 Lynext-Downloader"
        "Accept"     = "*/*"
    }
}

function Formatar-Tamanho {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) { return "$([math]::Round($Bytes / 1GB, 2)) GB" }
    if ($Bytes -ge 1MB) { return "$([math]::Round($Bytes / 1MB, 2)) MB" }
    if ($Bytes -ge 1KB) { return "$([math]::Round($Bytes / 1KB, 2)) KB" }
    return "$Bytes B"
}

function Formatar-Tempo {
    param([double]$Segundos)

    if ($Segundos -le 0 -or [double]::IsInfinity($Segundos) -or [double]::IsNaN($Segundos)) {
        return "--"
    }

    $ts = [TimeSpan]::FromSeconds($Segundos)

    if ($ts.TotalHours -ge 1) {
        return "{0:00}:{1:00}:{2:00}" -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
    }

    return "{0:00}:{1:00}" -f $ts.Minutes, $ts.Seconds
}

function Get-LatestGitHubStableAsset {
    param(
        [Parameter(Mandatory = $true)][string]$RepoApiUrl,
        [string]$ExtensaoDesejada = ".zip"
    )

    try {
        $headers = @{
            "User-Agent" = "Lynext-Downloader"
            "Accept"     = "application/vnd.github+json"
        }

        $releases = Invoke-RestMethod -Uri $RepoApiUrl -Headers $headers -UseBasicParsing -ErrorAction Stop

        if (-not $releases) {
            return $null
        }

        $releaseEstavel = $releases | Where-Object {
            $_.prerelease -eq $false -and $_.draft -eq $false
        } | Select-Object -First 1

        if (-not $releaseEstavel) {
            return $null
        }

        $asset = $releaseEstavel.assets | Where-Object {
            $_.name -like "*$ExtensaoDesejada"
        } | Select-Object -First 1

        if (-not $asset) {
            return $null
        }

        return [PSCustomObject]@{
            Url         = $asset.browser_download_url
            NomeArquivo = $asset.name
            Versao      = $releaseEstavel.tag_name
        }
    }
    catch {
        return $null
    }
}

function Get-LatestISLCAsset {
    try {
        $headers = Get-WebHeaders

        $listagem = Invoke-WebRequest `
            -Uri "https://www.wagnardsoft.com/intelligent-standby-list-cleaner-islc" `
            -Headers $headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $matchPost = [regex]::Matches(
            $listagem.Content,
            'href="([^"]*?/content/Download-Intelligent-standby-list-cleaner-ISLC-[^"]*)"'
        ) | Select-Object -First 1

        if (-not $matchPost) {
            throw "Nao foi possivel localizar a pagina da versao atual do ISLC."
        }

        $postUrl = $matchPost.Groups[1].Value
        if ($postUrl -notmatch '^https?://') {
            $postUrl = "https://www.wagnardsoft.com" + $postUrl
        }

        $paginaVersao = Invoke-WebRequest `
            -Uri $postUrl `
            -Headers $headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $matchExe = [regex]::Matches(
            $paginaVersao.Content,
            'href="([^"]*?/ISLC/[^"]+\.exe)"'
        ) | Select-Object -First 1

        if (-not $matchExe) {
            throw "Nao foi possivel localizar o executavel do ISLC."
        }

        $exeUrl = $matchExe.Groups[1].Value
        if ($exeUrl -notmatch '^https?://') {
            $exeUrl = "https://www.wagnardsoft.com" + $exeUrl
        }

        return [PSCustomObject]@{
            Url         = $exeUrl
            NomeArquivo = "ISLC.exe"
            Versao      = "Atual"
        }
    }
    catch {
        return [PSCustomObject]@{
            Url         = "https://www.wagnardsoft.com/ISLC/ISLC%20v1.0.4.5.exe"
            NomeArquivo = "ISLC.exe"
            Versao      = "Fallback"
        }
    }
}

function Get-LatestJavaAsset {
    try {
        $headers = Get-WebHeaders

        $pagina = Invoke-WebRequest `
            -Uri "https://www.java.com/pt-BR/download/manual.jsp" `
            -Headers $headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $links = [regex]::Matches(
            $pagina.Content,
            '(?is)<a\b[^>]*href="([^"]*AutoDL\?BundleId=[^"]+)"[^>]*>(.*?)</a>'
        )

        foreach ($link in $links) {
            $texto = [regex]::Replace($link.Groups[2].Value, '<.*?>', '')
            $texto = [System.Net.WebUtility]::HtmlDecode($texto)

            if ($texto -match 'Windows\s+Off-?line\s+\(64\s*bits\)') {
                $url = [System.Net.WebUtility]::HtmlDecode($link.Groups[1].Value)

                if ($url -notmatch '^https?://') {
                    $url = "https://www.java.com$url"
                }

                return [PSCustomObject]@{
                    Url         = $url
                    NomeArquivo = "JavaSetup64.exe"
                    Versao      = "Atual"
                }
            }
        }

        throw "Nao foi possivel localizar o Java Windows Off-line 64 bits."
    }
    catch {
        return $null
    }
}

function Get-LatestAdobeReaderAsset {
    try {
        $headers = @{
            "User-Agent" = "Lynext-Downloader"
            "Accept"     = "application/vnd.github+json"
        }

        $baseApi = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/a/Adobe/Acrobat/Reader/64-bit"
        $versoes = Invoke-RestMethod -Uri $baseApi -Headers $headers -UseBasicParsing -ErrorAction Stop

        $ultimaVersao = $versoes |
            Where-Object { $_.type -eq "dir" -and $_.name -match '^\d+\.' } |
            Sort-Object { [version]$_.name } -Descending |
            Select-Object -First 1

        if (-not $ultimaVersao) {
            throw "Nao foi possivel localizar a versao mais recente do Adobe Reader."
        }

        $arquivosVersao = Invoke-RestMethod `
            -Uri $ultimaVersao.url `
            -Headers $headers `
            -UseBasicParsing `
            -ErrorAction Stop

        $manifest = $arquivosVersao |
            Where-Object { $_.name -like "*.installer.yaml" } |
            Select-Object -First 1

        if (-not $manifest) {
            throw "Manifesto de instalador nao encontrado."
        }

        $yaml = Invoke-WebRequest `
            -Uri $manifest.download_url `
            -Headers (Get-WebHeaders) `
            -UseBasicParsing `
            -ErrorAction Stop

        $matchUrl = [regex]::Matches(
            $yaml.Content,
            'InstallerUrl:\s*(https://[^\r\n]+AcroRdrDCx64[^\r\n]+_MUI\.exe)'
        ) | Select-Object -First 1

        if (-not $matchUrl) {
            throw "URL do instalador MUI x64 nao encontrada."
        }

        return [PSCustomObject]@{
            Url         = $matchUrl.Groups[1].Value.Trim()
            NomeArquivo = "AdobeReader_x64_MUI.exe"
            Versao      = $ultimaVersao.name
        }
    }
    catch {
        return [PSCustomObject]@{
            Url         = "https://ardownload3.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121431/AcroRdrDCx642600121431_MUI.exe"
            NomeArquivo = "AdobeReader_x64_MUI.exe"
            Versao      = "Fallback"
        }
    }
}

function Iniciar-DownloadExterno {
    param(
        [string]$Nome,
        [string]$Url,
        [string]$Arquivo
    )

    try {
        Garantir-Pasta $destinoBase
        $saida = Join-Path $destinoBase $Arquivo

        if (Test-Path $saida) {
            Remove-Item $saida -Force -ErrorAction SilentlyContinue
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $client = New-Object System.Net.WebClient

        foreach ($header in (Get-WebHeaders).GetEnumerator()) {
            $client.Headers.Add($header.Key, $header.Value)
        }

        $download = [PSCustomObject]@{
            Cliente     = $client
            Arquivo     = $saida
            Url         = $Url
            Finalizado  = $false
            Sucesso     = $false
            Progresso   = 0
            Recebido    = 0
            Total       = 0
            Velocidade  = 0
            Eta         = "--"
            Inicio      = Get-Date
            Erro        = $null
        }

        $downloadsAtivos[$Nome] = $download

        $statusApps[$Nome] = [PSCustomObject]@{
            Texto = "Iniciando download..."
            Tipo  = "andando"
        }

        $client.add_DownloadProgressChanged({
            param($sender, $e)

            $download.Progresso = [int]$e.ProgressPercentage
            $download.Recebido = [double]$e.BytesReceived
            $download.Total = [double]$e.TotalBytesToReceive

            $tempo = ((Get-Date) - $download.Inicio).TotalSeconds
            if ($tempo -gt 0) {
                $download.Velocidade = $download.Recebido / $tempo
            }

            if ($download.Total -gt 0 -and $download.Velocidade -gt 0) {
                $restante = $download.Total - $download.Recebido
                $download.Eta = Formatar-Tempo ($restante / $download.Velocidade)
            }
            else {
                $download.Eta = "--"
            }

            $baixadoTxt = Formatar-Tamanho $download.Recebido
            $totalTxt = if ($download.Total -gt 0) { Formatar-Tamanho $download.Total } else { "tamanho desconhecido" }
            $velTxt = if ($download.Velocidade -gt 0) { "$(Formatar-Tamanho $download.Velocidade)/s" } else { "--" }

            $statusApps[$Nome] = [PSCustomObject]@{
                Texto = "$($download.Progresso)% concluido`r`nBaixado: $baixadoTxt de $totalTxt`r`nVelocidade: $velTxt | Tempo restante: $($download.Eta)"
                Tipo  = "andando"
            }
        }.GetNewClosure())

        $client.add_DownloadFileCompleted({
            param($sender, $e)

            $download.Finalizado = $true

            if ($e.Cancelled) {
                $download.Sucesso = $false
                $download.Erro = "Cancelado"
                $statusApps[$Nome] = [PSCustomObject]@{
                    Texto = "Cancelado"
                    Tipo  = "erro"
                }
            }
            elseif ($null -ne $e.Error) {
                $download.Sucesso = $false
                $download.Erro = $e.Error.Message
                $statusApps[$Nome] = [PSCustomObject]@{
                    Texto = "Erro [X]"
                    Tipo  = "erro"
                }
            }
            elseif ((Test-Path $download.Arquivo) -and ((Get-Item $download.Arquivo).Length -gt 0)) {
                $download.Sucesso = $true
                $download.Progresso = 100
                $tamanhoFinal = Formatar-Tamanho ((Get-Item $download.Arquivo).Length)
                $statusApps[$Nome] = [PSCustomObject]@{
                    Texto = "100% concluido [OK]`r`nArquivo salvo em: $($download.Arquivo)`r`nTamanho final: $tamanhoFinal"
                    Tipo  = "ok"
                }
            }
            else {
                $download.Sucesso = $false
                $download.Erro = "Arquivo vazio ou nao encontrado."
                $statusApps[$Nome] = [PSCustomObject]@{
                    Texto = "Erro [X]"
                    Tipo  = "erro"
                }
            }

            $client.Dispose()
        }.GetNewClosure())

        $client.DownloadFileAsync([Uri]$Url, $saida)
        return $true
    }
    catch {
        $statusApps[$Nome] = [PSCustomObject]@{
            Texto = "Erro [X]"
            Tipo  = "erro"
        }

        $geral.Text = "Erro ao iniciar download de ${Nome}: $($_.Exception.Message)"
        return $false
    }
}

function Resolver-DownloadInfo {
    param($App)

    switch ($App.Metodo) {
        "Direto" {
            return [PSCustomObject]@{
                Url     = $App.Url
                Arquivo = $App.Arquivo
            }
        }
        "GitHubLatestZip" {
            $asset = Get-LatestGitHubStableAsset -RepoApiUrl $App.Url -ExtensaoDesejada ".zip"
            if ($null -eq $asset) { return $null }

            return [PSCustomObject]@{
                Url     = $asset.Url
                Arquivo = $App.Arquivo
            }
        }
        "ISLCLatest" {
            $asset = Get-LatestISLCAsset
            if ($null -eq $asset) { return $null }

            return [PSCustomObject]@{
                Url     = $asset.Url
                Arquivo = $App.Arquivo
            }
        }
        "JavaLatest" {
            $asset = Get-LatestJavaAsset
            if ($null -eq $asset) { return $null }

            return [PSCustomObject]@{
                Url     = $asset.Url
                Arquivo = $App.Arquivo
            }
        }
        "AdobeReaderLatest" {
            $asset = Get-LatestAdobeReaderAsset
            if ($null -eq $asset) { return $null }

            return [PSCustomObject]@{
                Url     = $asset.Url
                Arquivo = $App.Arquivo
            }
        }
        default {
            return $null
        }
    }
}

# =========================
# FUNCOES DE UI / DADOS
# =========================
function Get-AppStatusInfo {
    param([string]$Nome)

    if ($statusApps.ContainsKey($Nome)) {
        return $statusApps[$Nome]
    }

    return [PSCustomObject]@{
        Texto = "Aguardando"
        Tipo  = "normal"
    }
}

function Get-SelectedAppFromCategory {
    param([string]$Categoria)

    if (-not $categoryViews.ContainsKey($Categoria)) {
        return $null
    }

    $view = $categoryViews[$Categoria]

    if ($null -ne $view.ListaAuto.SelectedItem) {
        return $view.ListaAuto.SelectedItem
    }

    if ($null -ne $view.ListaManual.SelectedItem) {
        return $view.ListaManual.SelectedItem
    }

    return $null
}

function AtualizarDetalhesCategoria {
    param([string]$Categoria)

    if (-not $categoryViews.ContainsKey($Categoria)) {
        return
    }

    $view = $categoryViews[$Categoria]
    $app = Get-SelectedAppFromCategory $Categoria

    if ($null -eq $app) {
        $view.Titulo.Text = "Selecione um app"
        $view.Tipo.Text = "Tipo: -"
        $view.Fonte.Text = "Fonte: -"
        $view.Arquivo.Text = "Arquivo: -"
        $view.Descricao.Text = "Clique em um app para ver o que ele faz e baixar ou abrir a pagina oficial."
        $view.Acao.Text = "Selecionar app"
        $view.Acao.Enabled = $false
        Set-Status $view.Status "Aguardando selecao." "normal"
        return
    }

    $status = Get-AppStatusInfo $app.Nome

    $view.Titulo.Text = $app.Nome
    $view.Tipo.Text = "Tipo: $($app.Tipo)"
    $view.Fonte.Text = "Fonte: $($app.Fonte)"

    if ([string]::IsNullOrWhiteSpace($app.Arquivo)) {
        $view.Arquivo.Text = "Arquivo: aberto pelo site"
    }
    else {
        $view.Arquivo.Text = "Arquivo: $($app.Arquivo)"
    }

    $view.Descricao.Text = $app.Descricao

    if ($app.Tipo -eq "Automatico") {
        if ($downloadsAtivos.ContainsKey($app.Nome) -and -not $downloadsAtivos[$app.Nome].Finalizado) {
            $view.Acao.Text = "Baixando..."
            $view.Acao.Enabled = $false
        }
        else {
            $view.Acao.Text = "Baixar"
            $view.Acao.Enabled = $true
        }
    }
    else {
        $view.Acao.Text = "Abrir pagina"
        $view.Acao.Enabled = $true
    }

    Set-Status $view.Status $status.Text $status.Tipo
}

function PopularListaApps {
    param(
        [System.Windows.Forms.ListBox]$Lista,
        [object[]]$Itens
    )

    $Lista.Items.Clear()

    foreach ($item in ($Itens | Sort-Object Nome)) {
        [void]$Lista.Items.Add($item)
    }
}

function AbrirPastaDownloads {
    Garantir-Pasta $destinoBase
    Start-Process explorer.exe $destinoBase | Out-Null
}

function ExecutarAcaoDoApp {
    param([string]$Categoria)

    $app = Get-SelectedAppFromCategory $Categoria
    if ($null -eq $app) {
        return
    }

    if ($app.Tipo -eq "Manual") {
        try {
            Start-Process $app.Url
            $statusApps[$app.Nome] = [PSCustomObject]@{
                Texto = "Pagina aberta [OK]"
                Tipo  = "manual"
            }
            $geral.Text = "Pagina de $($app.Nome) aberta."
        }
        catch {
            $statusApps[$app.Nome] = [PSCustomObject]@{
                Texto = "Erro [X]"
                Tipo  = "erro"
            }
            $geral.Text = "Falha ao abrir pagina de $($app.Nome)."
        }

        AtualizarDetalhesCategoria $Categoria
        return
    }

    if ($downloadsAtivos.ContainsKey($app.Nome) -and -not $downloadsAtivos[$app.Nome].Finalizado) {
        $geral.Text = "$($app.Nome) ja esta baixando."
        return
    }

    $geral.Text = "Preparando download de $($app.Nome)..."
    $statusApps[$app.Nome] = [PSCustomObject]@{
        Texto = "Preparando download..."
        Tipo  = "andando"
    }

    AtualizarDetalhesCategoria $Categoria

    $downloadInfo = Resolver-DownloadInfo $app

    if ($null -eq $downloadInfo) {
        $statusApps[$app.Nome] = [PSCustomObject]@{
            Texto = "Erro ao obter versao [X]"
            Tipo  = "erro"
        }

        $geral.Text = "Falha ao resolver download de $($app.Nome)."
        AtualizarDetalhesCategoria $Categoria
        return
    }

    $ok = Iniciar-DownloadExterno -Nome $app.Nome -Url $downloadInfo.Url -Arquivo $downloadInfo.Arquivo

    if ($ok) {
        $geral.Text = "Baixando $($app.Nome)..."
    }
    else {
        $geral.Text = "Falha ao iniciar $($app.Nome)."
    }

    AtualizarDetalhesCategoria $Categoria
}

function CriarAbaCategoria {
    param(
        [string]$Categoria,
        [System.Windows.Forms.TabControl]$TabControl
    )

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $Categoria
    $tab.BackColor = $bgMain
    $tab.ForeColor = $fgMain

    $painelEsquerdo = Criar-Painel 16 18 450 590 $bgPanel
    $tab.Controls.Add($painelEsquerdo)

    $lblAuto = Criar-Label "Automatico" 16 14 11 $true $accent
    $painelEsquerdo.Controls.Add($lblAuto)

    $lblAutoSub = Criar-Label "Baixa direto para Downloads\Instaladores" 16 36 9 $false $fgSoft
    $painelEsquerdo.Controls.Add($lblAutoSub)

    $listaAuto = Criar-Lista 16 60 410 200
    $painelEsquerdo.Controls.Add($listaAuto)

    $lblManual = Criar-Label "Manual" 16 286 11 $true $accent
    $painelEsquerdo.Controls.Add($lblManual)

    $lblManualSub = Criar-Label "Abre a pagina oficial para baixar manualmente" 16 308 9 $false $fgSoft
    $painelEsquerdo.Controls.Add($lblManualSub)

    $listaManual = Criar-Lista 16 332 410 200
    $painelEsquerdo.Controls.Add($listaManual)

    $painelDireito = Criar-Painel 482 18 480 590 $bgPanel2
    $tab.Controls.Add($painelDireito)

    $detTitulo = Criar-Label "Selecione um app" 16 18 15 $true $fgMain
    $painelDireito.Controls.Add($detTitulo)

    $detTipo = Criar-Label "Tipo: -" 16 56 10 $false $fgSoft
    $painelDireito.Controls.Add($detTipo)

    $detFonte = Criar-Label "Fonte: -" 16 80 10 $false $fgSoft
    $painelDireito.Controls.Add($detFonte)

    $detArquivo = Criar-Label "Arquivo: -" 16 104 10 $false $fgSoft
    $painelDireito.Controls.Add($detArquivo)

    $detDescTitulo = Criar-Label "O que ele faz" 16 140 11 $true $accent
    $painelDireito.Controls.Add($detDescTitulo)

    $detDesc = Criar-TextoLeitura 16 166 445 175
    $detDesc.Text = "Clique em um app para ver o que ele faz e baixar ou abrir a pagina oficial."
    $painelDireito.Controls.Add($detDesc)

    $detStatusTitulo = Criar-Label "Status do download" 16 368 11 $true $accent
    $painelDireito.Controls.Add($detStatusTitulo)

    $detStatus = Criar-Label "Aguardando selecao." 16 398 9 $false $fgSoft
    $detStatus.AutoSize = $false
    $detStatus.Size = New-Object System.Drawing.Size(445, 105)
    $detStatus.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $painelDireito.Controls.Add($detStatus)

    $btnAcao = Criar-Botao "Selecionar app" 16 532 200 36
    $btnAcao.Enabled = $false
    $painelDireito.Controls.Add($btnAcao)

    $btnPasta = Criar-Botao "Abrir pasta" 236 532 160 36
    $painelDireito.Controls.Add($btnPasta)

    $itemsCategoria = $apps | Where-Object { $_.Categoria -eq $Categoria }
    $itemsAuto = $itemsCategoria | Where-Object { $_.Tipo -eq "Automatico" } | Sort-Object Nome
    $itemsManual = $itemsCategoria | Where-Object { $_.Tipo -eq "Manual" } | Sort-Object Nome

    PopularListaApps -Lista $listaAuto -Itens $itemsAuto
    PopularListaApps -Lista $listaManual -Itens $itemsManual

    $categoryViews[$Categoria] = [PSCustomObject]@{
        Tab         = $tab
        ListaAuto   = $listaAuto
        ListaManual = $listaManual
        Titulo      = $detTitulo
        Tipo        = $detTipo
        Fonte       = $detFonte
        Arquivo     = $detArquivo
        Descricao   = $detDesc
        Status      = $detStatus
        Acao        = $btnAcao
    }

    $listaAuto.Add_SelectedIndexChanged({
        if ($listaAuto.SelectedIndex -ge 0) {
            $listaManual.ClearSelected()
        }
        AtualizarDetalhesCategoria $Categoria
    }.GetNewClosure())

    $listaManual.Add_SelectedIndexChanged({
        if ($listaManual.SelectedIndex -ge 0) {
            $listaAuto.ClearSelected()
        }
        AtualizarDetalhesCategoria $Categoria
    }.GetNewClosure())

    $listaAuto.Add_DoubleClick({
        if ($listaAuto.SelectedIndex -ge 0) {
            ExecutarAcaoDoApp $Categoria
        }
    }.GetNewClosure())

    $listaManual.Add_DoubleClick({
        if ($listaManual.SelectedIndex -ge 0) {
            ExecutarAcaoDoApp $Categoria
        }
    }.GetNewClosure())

    $btnAcao.Add_Click({
        ExecutarAcaoDoApp $Categoria
    }.GetNewClosure())

    $btnPasta.Add_Click({
        AbrirPastaDownloads
    }.GetNewClosure())

    $TabControl.TabPages.Add($tab) | Out-Null
}

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Downloads"
$form.ClientSize = New-Object System.Drawing.Size(1100, 880)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Topmost = $true
$form.BackColor = $bgMain
$form.ForeColor = $fgMain

$titulo = Criar-Label "Central de Downloads" 415 20 17 $true $fgMain
$form.Controls.Add($titulo)

$subtitulo = Criar-Label "Performance, monitoramento e suporte" 395 52 9 $false $fgSoft
$form.Controls.Add($subtitulo)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(24, 92)
$tabControl.Size = New-Object System.Drawing.Size(990, 650)
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$tabControl.BackColor = $tabBackColor
$form.Controls.Add($tabControl)

CriarAbaCategoria -Categoria "Performance" -TabControl $tabControl
CriarAbaCategoria -Categoria "Monitoramento" -TabControl $tabControl
CriarAbaCategoria -Categoria "Suporte" -TabControl $tabControl

foreach ($tab in $tabControl.TabPages) {
    $tab.BackColor = $bgMain
    $tab.ForeColor = $fgMain
}

# =========================
# RODAPE
# =========================
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(38, 768)
$progress.Size = New-Object System.Drawing.Size(760, 24)
$progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$form.Controls.Add($progress)

$lblProgresso = Criar-Label "0%" 820 761 17 $true $accent
$lblProgresso.AutoSize = $false
$lblProgresso.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblProgresso.Size = New-Object System.Drawing.Size(130, 34)
$form.Controls.Add($lblProgresso)

$geral = Criar-Label "Pronto para iniciar." 38 804 10 $false $fgSoft
$geral.AutoSize = $false
$geral.Size = New-Object System.Drawing.Size(960, 44)
$geral.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
$form.Controls.Add($geral)

$btnFechar = Criar-Botao "Fechar" 982 764 90 34
$form.Controls.Add($btnFechar)

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

# =========================
# TIMER
# =========================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500

$timer.Add_Tick({
    $ativosInfo = @($downloadsAtivos.GetEnumerator() | Where-Object { -not $_.Value.Finalizado })
    $ativos = @($ativosInfo | ForEach-Object { $_.Value })
    $finalizados = @($downloadsAtivos.GetEnumerator() | Where-Object { $_.Value.Finalizado })

    if ($ativos.Count -eq 0) {
        if ($downloadsAtivos.Count -eq 0) {
            $progress.Value = 0
            $lblProgresso.Text = "0%"
        }
        else {
            $ultimo = $finalizados | Select-Object -Last 1
            if ($null -ne $ultimo -and $ultimo.Value.Sucesso) {
                $progress.Value = 100
                $lblProgresso.Text = "100%"
                $textoRodape = $statusApps[$ultimo.Key].Texto -replace "`r`n", " | "
                $geral.Text = "$($ultimo.Key): $textoRodape"
            }
            elseif ($null -ne $ultimo) {
                $lblProgresso.Text = "$($ultimo.Value.Progresso)%"
                $textoRodape = $statusApps[$ultimo.Key].Texto -replace "`r`n", " | "
                $geral.Text = "$($ultimo.Key): $textoRodape"
            }
        }
    }
    elseif ($ativos.Count -eq 1) {
        $ativo = $ativosInfo[0]
        $nomeAtivo = $ativo.Key
        $statusAtivo = Get-AppStatusInfo $nomeAtivo

        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $progress.Value = [math]::Min([int]$ativos[0].Progresso, 100)
        $lblProgresso.Text = "$($progress.Value)%"
        $textoRodape = $statusAtivo.Text -replace "`r`n", " | "
        $geral.Text = "${nomeAtivo}: $textoRodape"
    }
    else {
        $media = [int](($ativos | Measure-Object -Property Progresso -Average).Average)
        $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $progress.Value = [math]::Min($media, 100)
        $lblProgresso.Text = "$($progress.Value)%"
        $geral.Text = "$($ativos.Count) downloads em andamento - media $media%"
    }

    foreach ($categoria in $categoryViews.Keys) {
        AtualizarDetalhesCategoria $categoria
    }

    AtualizarIndicadoresListas
})

$timer.Start()

# =========================
# INICIALIZACAO
# =========================
foreach ($categoria in $categoryViews.Keys) {
    AtualizarDetalhesCategoria $categoria
}

[void]$form.ShowDialog()
