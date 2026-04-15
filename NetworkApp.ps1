Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# Elevacao
# =========================
$scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

# =========================
# Config
# =========================
$script:EnableConfirmationBeep = $false
$script:IsBusy = $false
$script:LogDir  = Join-Path $env:TEMP "Lynext\Logs"
$null = New-Item -Path $script:LogDir -ItemType Directory -Force
$script:LogFile = Join-Path $script:LogDir ("NetworkApp_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$bgMain   = [System.Drawing.Color]::FromArgb(16,18,24)
$bgPanel  = [System.Drawing.Color]::FromArgb(22,25,33)
$bgBox    = [System.Drawing.Color]::FromArgb(28,31,40)
$accent   = [System.Drawing.Color]::FromArgb(0,191,255)
$okColor  = [System.Drawing.Color]::FromArgb(0,220,138)
$warnColor= [System.Drawing.Color]::FromArgb(255,185,0)
$errColor = [System.Drawing.Color]::FromArgb(255,80,80)
$txtColor = [System.Drawing.Color]::WhiteSmoke
$subColor = [System.Drawing.Color]::Silver

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $Message
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
}

function Append-Output {
    param(
        [string]$Text,
        [switch]$Clear
    )
    if ($Clear) { $script:txtOutput.Clear() }
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $stamp = Get-Date -Format "HH:mm:ss"
    $script:txtOutput.AppendText("[$stamp] $Text`r`n")
    $script:txtOutput.SelectionStart = $script:txtOutput.TextLength
    $script:txtOutput.ScrollToCaret()
}

function Set-Status {
    param(
        [string]$Text,
        [ValidateSet("info","busy","ok","warn","error")]
        [string]$State = "info"
    )
    $script:lblStatus.Text = "Status: $Text"
    switch ($State) {
        "busy"  { $script:lblStatus.ForeColor = $accent }
        "ok"    { $script:lblStatus.ForeColor = $okColor }
        "warn"  { $script:lblStatus.ForeColor = $warnColor }
        "error" { $script:lblStatus.ForeColor = $errColor }
        default { $script:lblStatus.ForeColor = $txtColor }
    }
}

function Convert-ToEncodedCommand {
    param([string]$Code)
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
}

function Escape-SQ {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return ($Text -replace "'", "''")
}

function Get-ActiveAdapterName {
    try {
        $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface } | Sort-Object ifIndex | Select-Object -First 1
        if (-not $nic) {
            $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object ifIndex | Select-Object -First 1
        }
        if ($nic) { return $nic.Name }
    } catch {}
    return "Ethernet"
}

function New-LynextButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 180,
        [int]$H = 44
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X,$Y)
    $btn.Size = New-Object System.Drawing.Size($W,$H)
    $btn.BackColor = $bgPanel
    $btn.ForeColor = $txtColor
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderColor = $accent
    $btn.FlatAppearance.BorderSize = 1
    $btn.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

function Start-LynextAction {
    param(
        [string]$Name,
        [string]$Code,
        [switch]$Confirm,
        [string]$ConfirmMessage = "Confirmar execução?"
    )

    if ($script:IsBusy) {
        Set-Status "Aguarde a ação atual terminar." "warn"
        return
    }

    if ($Confirm) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $ConfirmMessage,
            "Lynext - Confirmação",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    Append-Output ">>> $Name" -Clear
    Write-Log "INICIO: $Name"
    Set-Status "Executando: $Name" "busy"
    $script:prg.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:IsBusy = $true

    $fullCode = @"
`$ProgressPreference = 'SilentlyContinue'
`$ErrorActionPreference = 'Stop'
$Code
"@

    $encoded = Convert-ToEncodedCommand $fullCode

    $worker = New-Object System.ComponentModel.BackgroundWorker
    $worker.add_DoWork({
        param($sender, $e)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $($e.Argument.Encoded)"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        $e.Result = [pscustomobject]@{
            Name = $e.Argument.Name
            ExitCode = $proc.ExitCode
            StdOut = $stdout
            StdErr = $stderr
        }
    })

    $worker.add_RunWorkerCompleted({
        param($sender, $e)

        $script:IsBusy = $false
        $script:prg.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks

        if ($e.Error) {
            Append-Output ("ERRO FATAL: " + $e.Error.Message)
            Write-Log ("ERRO FATAL: " + $e.Error.Message) "ERROR"
            Set-Status "Falha fatal ao executar ação." "error"
            return
        }

        $result = $e.Result

        if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
            Append-Output $result.StdOut.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
            Append-Output ("ERRO:`r`n" + $result.StdErr.TrimEnd())
        }

        if ($result.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($result.StdErr)) {
            Set-Status "$($result.Name) concluído." "ok"
            Write-Log "OK: $($result.Name)"
            if ($script:EnableConfirmationBeep) {
                try { [console]::Beep(900,80) } catch {}
            }
        }
        elseif ($result.ExitCode -eq 0) {
            Set-Status "$($result.Name) concluído com avisos." "warn"
            Write-Log "AVISO: $($result.Name)" "WARN"
        }
        else {
            Set-Status "$($result.Name) falhou." "error"
            Write-Log "FALHA: $($result.Name) (ExitCode=$($result.ExitCode))" "ERROR"
        }
    })

    $worker.RunWorkerAsync([pscustomobject]@{
        Name = $Name
        Encoded = $encoded
    })
}

function Get-PingJitterCode {
    param([string]$Target)

    $t = Escape-SQ $Target
    @"
`$target = '$t'
`$count = 20
`$samples = @()
`$result = Test-Connection -ComputerName `$target -Count `$count -ErrorAction SilentlyContinue

foreach (`$r in @(`$result)) {
    if (`$null -eq `$r) { continue }

    if (`$r.PSObject.Properties.Name -contains 'ResponseTime') {
        if ([int]`$r.ResponseTime -ge 0) { `$samples += [double]`$r.ResponseTime }
    }
    elseif (`$r.PSObject.Properties.Name -contains 'Latency') {
        if ([double]`$r.Latency -ge 0) { `$samples += [double]`$r.Latency }
    }
}

`$sent = `$count
`$received = `$samples.Count
`$loss = [math]::Round(((`$sent - `$received) / [double]`$sent) * 100, 2)

if (`$received -eq 0) {
    throw 'Nenhuma resposta ICMP recebida.'
}

`$avg = [math]::Round((`$samples | Measure-Object -Average).Average, 2)
`$min = [math]::Round((`$samples | Measure-Object -Minimum).Minimum, 2)
`$max = [math]::Round((`$samples | Measure-Object -Maximum).Maximum, 2)

`$jvals = @()
for (`$i = 1; `$i -lt `$samples.Count; `$i++) {
    `$jvals += [math]::Abs(`$samples[`$i] - `$samples[`$i - 1])
}
`$jitter = if (`$jvals.Count -gt 0) {
    [math]::Round((`$jvals | Measure-Object -Average).Average, 2)
} else { 0 }

`$chars = '▁▂▃▄▅▆▇█'
`$spark = ''
if (`$max -eq `$min) {
    `$spark = ('▄' * `$samples.Count)
}
else {
    foreach (`$s in `$samples) {
        `$idx = [math]::Floor(((`$s - `$min) / (`$max - `$min)) * 7)
        if (`$idx -lt 0) { `$idx = 0 }
        if (`$idx -gt 7) { `$idx = 7 }
        `$spark += `$chars[`$idx]
    }
}

[pscustomobject]@{
    Target = `$target
    Sent = `$sent
    Received = `$received
    LossPercent = `$loss
    AvgMs = `$avg
    MinMs = `$min
    MaxMs = `$max
    JitterMs = `$jitter
    Samples = (`$samples -join ', ')
    Sparkline = `$spark
} | Format-List
"@
}

function Get-TracertCode {
    param([string]$Target)
    $t = Escape-SQ $Target
    @"
tracert -d '$t'
"@
}

function Get-PathPingCode {
    param([string]$Target)
    $t = Escape-SQ $Target
    @"
pathping -n '$t'
"@
}

function Get-MtuDiscoveryCode {
    param([string]$Target)
    $t = Escape-SQ $Target
    @"
`$target = '$t'

function Test-Payload {
    param([int]`$Size)
    `$reply = ping.exe -n 1 -f -l `$Size `$target
    return (`$reply | Select-String -Pattern 'TTL=' -Quiet)
}

`$low = 1200
`$high = 1472

if (-not (Test-Payload -Size `$low)) {
    throw 'Falha até com payload de 1200 bytes. Verifique conectividade.'
}

`$best = `$low
while (`$low -le `$high) {
    `$mid = [int][math]::Floor((`$low + `$high) / 2)
    if (Test-Payload -Size `$mid) {
        `$best = `$mid
        `$low = `$mid + 1
    } else {
        `$high = `$mid - 1
    }
}

`$mtu = `$best + 28
[pscustomobject]@{
    Target = `$target
    BestPayload = `$best
    SuggestedIPv4MTU = `$mtu
    Note = 'Aplique manualmente só em PPP/VPN/túnel ou fragmentação real.'
} | Format-List
"@
}

function Get-SetMtuCode {
    param(
        [string]$Alias,
        [int]$Mtu
    )
    $a = Escape-SQ $Alias
    @"
`$alias = '$a'
netsh interface ipv4 show subinterfaces
netsh interface ipv4 set subinterface "`$alias" mtu=$Mtu store=persistent
'---'
netsh interface ipv4 show subinterfaces
"@
}

function Get-SpeedTestCode {
@"
function Get-SpeedtestCommand {
    `$cmd = Get-Command speedtest -ErrorAction SilentlyContinue
    if (-not `$cmd) { `$cmd = Get-Command speedtest.exe -ErrorAction SilentlyContinue }
    if (`$cmd) { return `$cmd.Source }

    foreach (`$root in @(
        (Join-Path `$env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path `$env:ProgramFiles 'Ookla'),
        (Join-Path `$env:ProgramFiles 'speedtest')
    )) {
        if (Test-Path `$root) {
            `$file = Get-ChildItem `$root -Filter speedtest.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (`$file) { return `$file.FullName }
        }
    }
    return `$null
}

`$speed = Get-SpeedtestCommand

if (-not `$speed) {
    `$winget = Get-Command winget -ErrorAction SilentlyContinue
    if (`$winget) {
        Write-Output 'Speedtest CLI não encontrado. Tentando instalar via winget...'
        & `$winget.Source install -e --id Ookla.Speedtest.CLI --accept-source-agreements --accept-package-agreements --silent | Out-Null
        Start-Sleep -Seconds 2
        `$speed = Get-SpeedtestCommand
    }
}

if (-not `$speed) {
    throw 'Speedtest CLI não encontrado. Instale Ookla.Speedtest.CLI ou use o teste web do Cloudflare.'
}

`$json = ''
try {
    `$json = & `$speed --accept-license --accept-gdpr --format=json
} catch {
    `$json = & `$speed --accept-license --accept-gdpr -f json
}

if (-not `$json) {
    throw 'Nenhum dado retornado pelo Speedtest CLI.'
}

`$r = `$json | ConvertFrom-Json

`$down = if (`$r.download.bandwidth) { [math]::Round((`$r.download.bandwidth * 8) / 1000000, 2) } else { 0 }
`$up   = if (`$r.upload.bandwidth)   { [math]::Round((`$r.upload.bandwidth * 8) / 1000000, 2) } else { 0 }
`$lat  = if (`$r.ping.latency)       { [math]::Round([double]`$r.ping.latency, 2) } else { 0 }
`$jit  = if (`$r.ping.jitter)        { [math]::Round([double]`$r.ping.jitter, 2) } else { 0 }
`$pl   = if (`$null -ne `$r.packetLoss) { [math]::Round([double]`$r.packetLoss, 2) } else { 0 }

[pscustomobject]@{
    Provider = if (`$r.isp) { `$r.isp } else { 'N/D' }
    Server   = if (`$r.server.name) { ('{0} - {1}/{2}' -f `$r.server.name, `$r.server.location, `$r.server.country) } else { 'N/D' }
    PingMs   = `$lat
    JitterMs = `$jit
    PacketLossPercent = `$pl
    DownloadMbps = `$down
    UploadMbps = `$up
    ResultUrl = if (`$r.result.url) { `$r.result.url } else { '' }
} | Format-List
"@
}

# =========================
# Form / UI
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext | Network"
$form.Size = New-Object System.Drawing.Size(1120,720)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgMain
$form.ForeColor = $txtColor
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Lynext"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",22,[System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $accent
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(22,18)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Network Center | Diagnóstico, correção e baseline segura"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI",10)
$lblSub.ForeColor = $subColor
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(26,60)

$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text = "Created by Ryan"
$lblCredit.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Italic)
$lblCredit.ForeColor = $subColor
$lblCredit.AutoSize = $true
$lblCredit.Location = New-Object System.Drawing.Point(930,24)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(24,100)
$tabs.Size = New-Object System.Drawing.Size(640,500)

$tabDiag = New-Object System.Windows.Forms.TabPage
$tabDiag.Text = "Diagnóstico"
$tabDiag.BackColor = $bgBox
$tabDiag.ForeColor = $txtColor

$tabFix = New-Object System.Windows.Forms.TabPage
$tabFix.Text = "Correções"
$tabFix.BackColor = $bgBox
$tabFix.ForeColor = $txtColor

$tabTune = New-Object System.Windows.Forms.TabPage
$tabTune.Text = "Otimização"
$tabTune.BackColor = $bgBox
$tabTune.ForeColor = $txtColor

$tabLinks = New-Object System.Windows.Forms.TabPage
$tabLinks.Text = "Drivers e links"
$tabLinks.BackColor = $bgBox
$tabLinks.ForeColor = $txtColor

$tabs.TabPages.AddRange(@($tabDiag,$tabFix,$tabTune,$tabLinks))

$script:txtOutput = New-Object System.Windows.Forms.TextBox
$script:txtOutput.Location = New-Object System.Drawing.Point(686,100)
$script:txtOutput.Size = New-Object System.Drawing.Size(392,500)
$script:txtOutput.Multiline = $true
$script:txtOutput.ScrollBars = "Vertical"
$script:txtOutput.ReadOnly = $true
$script:txtOutput.BackColor = $bgBox
$script:txtOutput.ForeColor = $txtColor
$script:txtOutput.Font = New-Object System.Drawing.Font("Consolas",9)

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = "Status: Pronto"
$script:lblStatus.Location = New-Object System.Drawing.Point(24,620)
$script:lblStatus.AutoSize = $true
$script:lblStatus.ForeColor = $txtColor
$script:lblStatus.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)

$script:prg = New-Object System.Windows.Forms.ProgressBar
$script:prg.Location = New-Object System.Drawing.Point(24,648)
$script:prg.Size = New-Object System.Drawing.Size(650,16)
$script:prg.Style = "Blocks"

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log: $script:LogFile"
$lblLog.Location = New-Object System.Drawing.Point(686,620)
$lblLog.Size = New-Object System.Drawing.Size(392,40)
$lblLog.ForeColor = $subColor
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI",8)

# =========================
# Botoes - Diagnostico
# =========================
$btnSnap   = New-LynextButton "SNAPSHOT DE REDE" 18 18
$btnPing   = New-LynextButton "PING / JITTER" 218 18
$btnTrace  = New-LynextButton "TRACEROUTE" 418 18
$btnPath   = New-LynextButton "PATHPING" 18 78
$btnSpeed  = New-LynextButton "SPEEDTEST CLI" 218 78
$btnSpeedW = New-LynextButton "SPEEDTEST WEB" 418 78
$btnDnsRes = New-LynextButton "RESOLVE DNS" 18 138
$btnShowTcp= New-LynextButton "MOSTRAR TCP" 218 138
$btnDrv    = New-LynextButton "VER DRIVERS" 418 138

$tabDiag.Controls.AddRange(@($btnSnap,$btnPing,$btnTrace,$btnPath,$btnSpeed,$btnSpeedW,$btnDnsRes,$btnShowTcp,$btnDrv))

# =========================
# Botoes - Correcoes
# =========================
$btnFlush  = New-LynextButton "FLUSH DNS" 18 18
$btnWins   = New-LynextButton "RESET WINSOCK" 218 18
$btnIp     = New-LynextButton "RESET IP / DHCP" 418 18
$btnRestartNic = New-LynextButton "REINICIAR ADAPTADOR" 18 78
$btnFullReset  = New-LynextButton "RESET COMPLETO" 218 78
$btnFwReset    = New-LynextButton "RESET FIREWALL" 418 78
$btnNetUi      = New-LynextButton "RESET DE REDE UI" 18 138
$btnPowerOff   = New-LynextButton "SEM ECONOMIA NIC" 218 138
$btnNicRestore = New-LynextButton "RESTAURAR NIC" 418 138

$tabFix.Controls.AddRange(@($btnFlush,$btnWins,$btnIp,$btnRestartNic,$btnFullReset,$btnFwReset,$btnNetUi,$btnPowerOff,$btnNicRestore))

# =========================
# Botoes - Otimizacao
# =========================
$btnTcpBase  = New-LynextButton "BASELINE TCP SEGURA" 18 18
$btnMtuDisc  = New-LynextButton "DESCOBRIR MTU" 218 18
$btnMtuSet   = New-LynextButton "APLICAR MTU" 418 18
$btnDnsCf    = New-LynextButton "DNS CLOUDFLARE" 18 78
$btnDnsGo    = New-LynextButton "DNS GOOGLE" 218 78
$btnDnsQ9    = New-LynextButton "DNS QUAD9" 418 78
$btnDnsAuto  = New-LynextButton "DNS AUTOMATICO" 18 138
$btnLogs     = New-LynextButton "ABRIR LOGS" 218 138
$btnCopyLog  = New-LynextButton "COPIAR CAMINHO LOG" 418 138

$tabTune.Controls.AddRange(@($btnTcpBase,$btnMtuDisc,$btnMtuSet,$btnDnsCf,$btnDnsGo,$btnDnsQ9,$btnDnsAuto,$btnLogs,$btnCopyLog))

# =========================
# Botoes - Drivers e links
# =========================
$btnNetDevR = New-LynextButton "RESTART NET DEVICES" 18 18
$btnIntel   = New-LynextButton "INTEL DSA" 218 18
$btnRealtek = New-LynextButton "REALTEK" 418 18
$btnCatalog = New-LynextButton "UPDATE CATALOG" 18 78
$btnCfWeb   = New-LynextButton "CLOUDFLARE TEST" 218 78
$btnServices= New-LynextButton "VER SERVICOS" 418 78

$tabLinks.Controls.AddRange(@($btnNetDevR,$btnIntel,$btnRealtek,$btnCatalog,$btnCfWeb,$btnServices))

# =========================
# Eventos
# =========================
$btnSnap.Add_Click({
    $code = @"
'=== ADAPTADORES ==='
Get-NetAdapter | Sort-Object Status, Name | Format-Table -Auto Name, InterfaceDescription, Status, LinkSpeed, MacAddress
'`n=== IP CONFIG ==='
Get-NetIPConfiguration -All | Format-List InterfaceAlias, InterfaceIndex, IPv4Address, IPv6Address, IPv4DefaultGateway, DNSServer, NetProfile
'`n=== PERFIL ==='
Get-NetConnectionProfile | Format-Table -Auto Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity
'`n=== DNS ==='
Get-DnsClientServerAddress | Format-Table -Auto InterfaceAlias, AddressFamily, ServerAddresses
'`n=== ROTA DEFAULT ==='
Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Format-Table -Auto ifIndex, InterfaceAlias, NextHop, RouteMetric
"@
    Start-LynextAction -Name "Snapshot de rede" -Code $code
})

$btnPing.Add_Click({
    $target = [Microsoft.VisualBasic.Interaction]::InputBox("Host/IP para teste de ping e jitter:", "Lynext - Ping/Jitter", "1.1.1.1")
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Ping/Jitter para $target" -Code (Get-PingJitterCode -Target $target)
})

$btnTrace.Add_Click({
    $target = [Microsoft.VisualBasic.Interaction]::InputBox("Host/IP para tracert:", "Lynext - Traceroute", "1.1.1.1")
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Traceroute para $target" -Code (Get-TracertCode -Target $target)
})

$btnPath.Add_Click({
    $target = [Microsoft.VisualBasic.Interaction]::InputBox("Host/IP para pathping (demora mais):", "Lynext - PathPing", "1.1.1.1")
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "PathPing para $target" -Code (Get-PathPingCode -Target $target)
})

$btnSpeed.Add_Click({
    Start-LynextAction -Name "Speedtest CLI" -Code (Get-SpeedTestCode) -Confirm -ConfirmMessage "Este teste pode consumir bastante tráfego. Continuar?"
})

$btnSpeedW.Add_Click({
    Start-Process "https://speed.cloudflare.com/"
    Set-Status "Speedtest web aberto no navegador." "ok"
    Write-Log "Abrindo speed.cloudflare.com"
})

$btnDnsRes.Add_Click({
    $code = @"
'=== DNS atuais ==='
Get-DnsClientServerAddress | Format-Table -Auto InterfaceAlias, AddressFamily, ServerAddresses
'`n=== Resolve-DnsName ==='
Resolve-DnsName -Name 'www.cloudflare.com' -Type A | Format-Table -Auto Name, Type, IPAddress, TTL
Resolve-DnsName -Name 'www.google.com' -Type A | Format-Table -Auto Name, Type, IPAddress, TTL
"@
    Start-LynextAction -Name "Resolve DNS" -Code $code
})

$btnShowTcp.Add_Click({
    $code = @"
netsh int tcp show global
'`n=== TCP SETTINGS ==='
Get-NetTCPSetting | Select-Object SettingName, AutoTuningLevelLocal, ScalingHeuristics, InitialCongestionWindowMss, CongestionProvider, MinRtoMs | Format-Table -Auto
'`n=== OFFLOAD GLOBAL ==='
Get-NetOffloadGlobalSetting | Format-List
"@
    Start-LynextAction -Name "Mostrar TCP e offloads" -Code $code
})

$btnDrv.Add_Click({
    $code = @"
'=== ADAPTADORES ==='
Get-NetAdapter | Sort-Object Name | Format-Table -Auto Name, InterfaceDescription, Status, LinkSpeed, MacAddress
'`n=== DRIVERS NET ==='
Get-CimInstance Win32_PnPSignedDriver | Where-Object { `$_.DeviceClass -eq 'NET' } |
    Sort-Object DeviceName |
    Select-Object DeviceName, DriverVersion, DriverProviderName, Manufacturer, InfName |
    Format-Table -Auto
"@
    Start-LynextAction -Name "Ver drivers de rede" -Code $code
})

$btnFlush.Add_Click({
    Start-LynextAction -Name "Flush DNS" -Code "ipconfig /flushdns"
})

$btnWins.Add_Click({
    $code = @"
netsh winsock reset
'Reinício recomendado: SIM'
"@
    Start-LynextAction -Name "Reset Winsock" -Code $code
})

$btnIp.Add_Click({
    $code = @"
netsh int ip reset
ipconfig /release
Start-Sleep -Seconds 1
ipconfig /renew
'Reinício recomendado: SIM'
"@
    Start-LynextAction -Name "Reset IP / DHCP" -Code $code
})

$btnRestartNic.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Restart-NetAdapter -Name `$nic.Name -Confirm:`$false
Get-NetAdapter -Name `$nic.Name | Format-Table -Auto Name, Status, LinkSpeed
"@
    Start-LynextAction -Name "Reiniciar adaptador ativo" -Code $code
})

$btnFullReset.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
ipconfig /flushdns
try { Restart-Service Dnscache -Force -ErrorAction Stop } catch {}
netsh winsock reset
netsh int ip reset
ipconfig /release
Start-Sleep -Seconds 1
ipconfig /renew
nbtstat -R
nbtstat -RR
if (`$nic) {
    Restart-NetAdapter -Name `$nic.Name -Confirm:`$false
}
'Reinício recomendado: SIM'
"@
    Start-LynextAction -Name "Reset completo seguro" -Code $code -Confirm -ConfirmMessage "Executar reset completo de rede seguro agora?"
})

$btnFwReset.Add_Click({
    $code = @"
netsh advfirewall reset
'ATENÇÃO: regras customizadas do firewall podem ter sido removidas.'
"@
    Start-LynextAction -Name "Reset firewall" -Code $code -Confirm -ConfirmMessage "Isso restaura políticas padrão do firewall. Continuar?"
})

$btnNetUi.Add_Click({
    Start-Process "ms-settings:network-status"
    Set-Status "Tela de reset de rede aberta." "ok"
    Write-Log "Abrindo ms-settings:network-status"
})

$btnPowerOff.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Disable-NetAdapterPowerManagement -Name `$nic.Name
try {
    Get-NetAdapterPowerManagement -Name `$nic.Name | Format-List
} catch {
    'Comando executado, mas o adaptador não expõe todos os detalhes de power management.'
}
"@
    Start-LynextAction -Name "Desativar economia do NIC" -Code $code
})

$btnNicRestore.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Reset-NetAdapterAdvancedProperty -Name `$nic.Name
Get-NetAdapterAdvancedProperty -Name `$nic.Name | Format-Table -Auto DisplayName, DisplayValue
"@
    Start-LynextAction -Name "Restaurar propriedades avançadas do NIC" -Code $code -Confirm -ConfirmMessage "Isso reverte tweaks avançados do adaptador ativo. Continuar?"
})

$btnTcpBase.Add_Click({
    $code = @"
netsh int tcp set global autotuninglevel=normal
netsh int tcp set global rss=enabled
'---'
netsh int tcp show global
"@
    Start-LynextAction -Name "Aplicar baseline TCP segura" -Code $code
})

$btnMtuDisc.Add_Click({
    $target = [Microsoft.VisualBasic.Interaction]::InputBox("Host/IP para descoberta de MTU IPv4:", "Lynext - Descobrir MTU", "1.1.1.1")
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Descobrir MTU para $target" -Code (Get-MtuDiscoveryCode -Target $target)
})

$btnMtuSet.Add_Click({
    $alias = [Microsoft.VisualBasic.Interaction]::InputBox("Adaptador (alias) para aplicar MTU:", "Lynext - Aplicar MTU", (Get-ActiveAdapterName))
    if ([string]::IsNullOrWhiteSpace($alias)) { return }

    $mtuText = [Microsoft.VisualBasic.Interaction]::InputBox("Valor de MTU IPv4:", "Lynext - Aplicar MTU", "1492")
    if ([string]::IsNullOrWhiteSpace($mtuText)) { return }

    [int]$mtu = 0
    if (-not [int]::TryParse($mtuText, [ref]$mtu)) {
        [System.Windows.Forms.MessageBox]::Show("Valor de MTU inválido.", "Lynext", "OK", "Error") | Out-Null
        return
    }

    Start-LynextAction -Name "Aplicar MTU $mtu em $alias" -Code (Get-SetMtuCode -Alias $alias -Mtu $mtu) -Confirm -ConfirmMessage "Aplicar MTU $mtu no adaptador '$alias'?"
})

$btnDnsCf.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ServerAddresses 1.1.1.1,1.0.0.1
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "Aplicar DNS Cloudflare" -Code $code
})

$btnDnsGo.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ServerAddresses 8.8.8.8,8.8.4.4
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "Aplicar DNS Google" -Code $code
})

$btnDnsQ9.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ServerAddresses 9.9.9.9,149.112.112.112
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "Aplicar DNS Quad9" -Code $code
})

$btnDnsAuto.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ResetServerAddresses
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "Restaurar DNS automático" -Code $code
})

$btnLogs.Add_Click({
    Start-Process explorer.exe $script:LogDir
    Set-Status "Pasta de logs aberta." "ok"
    Write-Log "Abrindo pasta de logs"
})

$btnCopyLog.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText($script:LogFile)
    Set-Status "Caminho do log copiado." "ok"
    Write-Log "Caminho do log copiado"
})

$btnNetDevR.Add_Click({
    Start-LynextAction -Name "Restart Net Devices (PnPUtil)" -Code "pnputil /restart-device /class Net" -Confirm -ConfirmMessage "Isso reinicia dispositivos da classe Net. Continuar?"
})

$btnIntel.Add_Click({
    Start-Process "https://www.intel.com.br/content/www/br/pt/support/detect.html"
    Set-Status "Intel DSA aberto no navegador." "ok"
    Write-Log "Abrindo Intel DSA"
})

$btnRealtek.Add_Click({
    Start-Process "https://www.realtek.com/Download/Overview?menu_id=355"
    Set-Status "Portal Realtek aberto no navegador." "ok"
    Write-Log "Abrindo portal Realtek"
})

$btnCatalog.Add_Click({
    Start-Process "https://www.catalog.update.microsoft.com/Search.aspx?q=network%20adapter%20driver"
    Set-Status "Microsoft Update Catalog aberto." "ok"
    Write-Log "Abrindo Microsoft Update Catalog"
})

$btnCfWeb.Add_Click({
    Start-Process "https://speed.cloudflare.com/"
    Set-Status "Cloudflare Speed Test aberto." "ok"
    Write-Log "Abrindo Cloudflare Speed Test"
})

$btnServices.Add_Click({
    $code = @"
Get-Service Dnscache, Dhcp, NlaSvc, WlanSvc, mpssvc, BFE -ErrorAction SilentlyContinue |
    Format-Table -Auto Name, DisplayName, Status, StartType
"@
    Start-LynextAction -Name "Ver serviços essenciais" -Code $code
})

$form.Controls.AddRange(@($lblTitle,$lblSub,$lblCredit,$tabs,$script:txtOutput,$script:lblStatus,$script:prg,$lblLog))

Append-Output "Lynext Network Center iniciado. Logs em: $script:LogFile"
Write-Log "Lynext Network Center iniciado"
Set-Status "Pronto" "ok"

[void]$form.ShowDialog()
