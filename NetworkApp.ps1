Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# ADMIN
# =========================
$scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

# =========================
# GLOBAL
# =========================
$script:IsBusy = $false
$script:LogDir = Join-Path $env:TEMP "Lynext\Logs"
$null = New-Item -Path $script:LogDir -ItemType Directory -Force
$script:LogFile = Join-Path $script:LogDir ("NetworkApp_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$bgMain      = [System.Drawing.Color]::FromArgb(8,12,20)
$bgPanel     = [System.Drawing.Color]::FromArgb(15,20,32)
$bgPanel2    = [System.Drawing.Color]::FromArgb(20,26,40)
$bgButton    = [System.Drawing.Color]::FromArgb(12,18,30)
$bgHover     = [System.Drawing.Color]::FromArgb(20,30,48)
$bgDown      = [System.Drawing.Color]::FromArgb(26,40,60)
$txtMain     = [System.Drawing.Color]::FromArgb(235,240,250)
$txtSoft     = [System.Drawing.Color]::FromArgb(160,170,190)
$accent      = [System.Drawing.Color]::FromArgb(0,190,255)
$okColor     = [System.Drawing.Color]::FromArgb(0,230,140)
$warnColor   = [System.Drawing.Color]::FromArgb(255,190,70)
$errColor    = [System.Drawing.Color]::FromArgb(255,95,95)
$borderColor = [System.Drawing.Color]::FromArgb(35,90,130)

# =========================
# HELPERS
# =========================
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

    if ($Clear) {
        $script:txtOutput.Clear()
    }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }

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
        default { $script:lblStatus.ForeColor = $txtMain }
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
        if ($nic) {
            return $nic.Name
        }
    }
    catch {}
    return "Ethernet"
}

function Show-InputDialog {
    param(
        [string]$Title,
        [string]$Label,
        [string]$DefaultValue = ""
    )

    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.Size = New-Object System.Drawing.Size(430,160)
    $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.BackColor = $bgMain
    $f.ForeColor = $txtMain

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Location = New-Object System.Drawing.Point(15,15)
    $lbl.Size = New-Object System.Drawing.Size(385,20)
    $lbl.ForeColor = $txtMain
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",9)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(15,45)
    $tb.Size = New-Object System.Drawing.Size(385,25)
    $tb.Text = $DefaultValue
    $tb.BackColor = $bgPanel2
    $tb.ForeColor = $txtMain
    $tb.BorderStyle = "FixedSingle"
    $tb.Font = New-Object System.Drawing.Font("Segoe UI",9)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Location = New-Object System.Drawing.Point(230,80)
    $ok.Size = New-Object System.Drawing.Size(80,30)
    $ok.FlatStyle = "Flat"
    $ok.BackColor = $bgButton
    $ok.ForeColor = $txtMain
    $ok.FlatAppearance.BorderColor = $borderColor
    $ok.Add_Click({
        $f.Tag = $tb.Text
        $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $f.Close()
    })

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(320,80)
    $cancel.Size = New-Object System.Drawing.Size(80,30)
    $cancel.FlatStyle = "Flat"
    $cancel.BackColor = $bgButton
    $cancel.ForeColor = $txtMain
    $cancel.FlatAppearance.BorderColor = $borderColor
    $cancel.Add_Click({
        $f.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $f.Close()
    })

    $f.Controls.AddRange(@($lbl,$tb,$ok,$cancel))
    $f.AcceptButton = $ok
    $f.CancelButton = $cancel

    $result = $f.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return [string]$f.Tag
    }

    return $null
}

function New-LynextButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 180,
        [int]$H = 42
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X,$Y)
    $btn.Size = New-Object System.Drawing.Size($W,$H)
    $btn.BackColor = $bgButton
    $btn.ForeColor = $txtMain
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderColor = $borderColor
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.MouseOverBackColor = $bgHover
    $btn.FlatAppearance.MouseDownBackColor = $bgDown
    $btn.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    return $btn
}

function Start-LynextAction {
    param(
        [string]$Name,
        [string]$Code,
        [switch]$Confirm,
        [string]$ConfirmMessage = "Confirm action?"
    )

    if ($script:IsBusy) {
        Set-Status "Wait for the current action to finish." "warn"
        return
    }

    if ($Confirm) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $ConfirmMessage,
            "Lynext",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    $script:IsBusy = $true
    $script:prg.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    Append-Output ">>> $Name" -Clear
    Write-Log "START: $Name"
    Set-Status "Running: $Name" "busy"

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
        $psi.RedirectStandardError = $true
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
            Append-Output ("FATAL ERROR: " + $e.Error.Message)
            Write-Log ("FATAL ERROR: " + $e.Error.Message) "ERROR"
            Set-Status "Fatal error while running action." "error"
            return
        }

        $result = $e.Result

        if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
            Append-Output $result.StdOut.TrimEnd()
        }

        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
            Append-Output ("ERROR:`r`n" + $result.StdErr.TrimEnd())
        }

        if ($result.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($result.StdErr)) {
            Set-Status "$($result.Name) done." "ok"
            Write-Log "OK: $($result.Name)"
        }
        elseif ($result.ExitCode -eq 0) {
            Set-Status "$($result.Name) done with warnings." "warn"
            Write-Log "WARN: $($result.Name)" "WARN"
        }
        else {
            Set-Status "$($result.Name) failed." "error"
            Write-Log "FAIL: $($result.Name) ExitCode=$($result.ExitCode)" "ERROR"
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
    throw 'No ICMP reply received.'
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
    throw 'Failed even with payload 1200. Check connectivity.'
}

`$best = `$low

while (`$low -le `$high) {
    `$mid = [int][math]::Floor((`$low + `$high) / 2)

    if (Test-Payload -Size `$mid) {
        `$best = `$mid
        `$low = `$mid + 1
    }
    else {
        `$high = `$mid - 1
    }
}

`$mtu = `$best + 28

[pscustomobject]@{
    Target = `$target
    BestPayload = `$best
    SuggestedIPv4MTU = `$mtu
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
'---'
netsh interface ipv4 set subinterface name="`$alias" mtu=$Mtu store=persistent
'---'
netsh interface ipv4 show subinterfaces
"@
}

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 8000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 150
$toolTip.ShowAlways = $true

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext | Network"
$form.Size = New-Object System.Drawing.Size(1220,760)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgMain
$form.ForeColor = $txtMain
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# =========================
# HEADER
# =========================
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Lynext"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",24,[System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $accent
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(24,18)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Network Center | diagnose, repair and safe baseline"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI",10)
$lblSub.ForeColor = $txtSoft
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(28,62)

$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text = "Created by Ryan"
$lblCredit.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Italic)
$lblCredit.ForeColor = $txtSoft
$lblCredit.AutoSize = $true
$lblCredit.Location = New-Object System.Drawing.Point(1030,24)

# =========================
# LEFT PANELS
# =========================
$panelDiag = New-Object System.Windows.Forms.Panel
$panelDiag.Location = New-Object System.Drawing.Point(24,100)
$panelDiag.Size = New-Object System.Drawing.Size(560,170)
$panelDiag.BackColor = $bgPanel

$panelFix = New-Object System.Windows.Forms.Panel
$panelFix.Location = New-Object System.Drawing.Point(24,285)
$panelFix.Size = New-Object System.Drawing.Size(560,170)
$panelFix.BackColor = $bgPanel

$panelTune = New-Object System.Windows.Forms.Panel
$panelTune.Location = New-Object System.Drawing.Point(24,470)
$panelTune.Size = New-Object System.Drawing.Size(560,170)
$panelTune.BackColor = $bgPanel

$panelLinks = New-Object System.Windows.Forms.Panel
$panelLinks.Location = New-Object System.Drawing.Point(24,655)
$panelLinks.Size = New-Object System.Drawing.Size(560,50)
$panelLinks.BackColor = $bgPanel

# Titles
$diagTitle = New-Object System.Windows.Forms.Label
$diagTitle.Text = "DIAG"
$diagTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$diagTitle.ForeColor = $txtMain
$diagTitle.AutoSize = $true
$diagTitle.Location = New-Object System.Drawing.Point(14,10)

$fixTitle = New-Object System.Windows.Forms.Label
$fixTitle.Text = "REPAIR"
$fixTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$fixTitle.ForeColor = $txtMain
$fixTitle.AutoSize = $true
$fixTitle.Location = New-Object System.Drawing.Point(14,10)

$tuneTitle = New-Object System.Windows.Forms.Label
$tuneTitle.Text = "TUNE"
$tuneTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$tuneTitle.ForeColor = $txtMain
$tuneTitle.AutoSize = $true
$tuneTitle.Location = New-Object System.Drawing.Point(14,10)

$linksTitle = New-Object System.Windows.Forms.Label
$linksTitle.Text = "LINKS"
$linksTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$linksTitle.ForeColor = $txtMain
$linksTitle.AutoSize = $true
$linksTitle.Location = New-Object System.Drawing.Point(14,12)

$panelDiag.Controls.Add($diagTitle)
$panelFix.Controls.Add($fixTitle)
$panelTune.Controls.Add($tuneTitle)
$panelLinks.Controls.Add($linksTitle)

# =========================
# OUTPUT PANEL
# =========================
$panelOutput = New-Object System.Windows.Forms.Panel
$panelOutput.Location = New-Object System.Drawing.Point(600,100)
$panelOutput.Size = New-Object System.Drawing.Size(590,540)
$panelOutput.BackColor = $bgPanel

$outTitle = New-Object System.Windows.Forms.Label
$outTitle.Text = "OUTPUT"
$outTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$outTitle.ForeColor = $txtMain
$outTitle.AutoSize = $true
$outTitle.Location = New-Object System.Drawing.Point(14,10)

$script:txtOutput = New-Object System.Windows.Forms.TextBox
$script:txtOutput.Location = New-Object System.Drawing.Point(15,40)
$script:txtOutput.Size = New-Object System.Drawing.Size(560,480)
$script:txtOutput.Multiline = $true
$script:txtOutput.ScrollBars = "Vertical"
$script:txtOutput.ReadOnly = $true
$script:txtOutput.BackColor = $bgPanel2
$script:txtOutput.ForeColor = $txtMain
$script:txtOutput.BorderStyle = "FixedSingle"
$script:txtOutput.Font = New-Object System.Drawing.Font("Consolas",9)

$panelOutput.Controls.Add($outTitle)
$panelOutput.Controls.Add($script:txtOutput)

# =========================
# STATUS
# =========================
$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = "Status: Ready"
$script:lblStatus.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$script:lblStatus.ForeColor = $okColor
$script:lblStatus.AutoSize = $true
$script:lblStatus.Location = New-Object System.Drawing.Point(24,720)

$script:prg = New-Object System.Windows.Forms.ProgressBar
$script:prg.Location = New-Object System.Drawing.Point(220,721)
$script:prg.Size = New-Object System.Drawing.Size(370,14)
$script:prg.Style = "Blocks"

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log: $script:LogFile"
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI",8)
$lblLog.ForeColor = $txtSoft
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(600,720)

# =========================
# BUTTONS - DIAG
# =========================
$btnSnapshot = New-LynextButton "SNAPSHOT" 18 42
$btnPing     = New-LynextButton "PING / JITTER" 196 42
$btnTrace    = New-LynextButton "TRACEROUTE" 374 42
$btnPath     = New-LynextButton "PATHPING" 18 92
$btnDns      = New-LynextButton "RESOLVE DNS" 196 92
$btnTcp      = New-LynextButton "SHOW TCP" 374 92

$panelDiag.Controls.AddRange(@($btnSnapshot,$btnPing,$btnTrace,$btnPath,$btnDns,$btnTcp))

# =========================
# BUTTONS - REPAIR
# =========================
$btnFlush    = New-LynextButton "FLUSH DNS" 18 42
$btnWinsock  = New-LynextButton "RESET WINSOCK" 196 42
$btnResetIp  = New-LynextButton "RESET IP / DHCP" 374 42
$btnRestart  = New-LynextButton "RESTART ADAPTER" 18 92
$btnFull     = New-LynextButton "FULL RESET" 196 92
$btnFirewall = New-LynextButton "RESET FIREWALL" 374 92

$panelFix.Controls.AddRange(@($btnFlush,$btnWinsock,$btnResetIp,$btnRestart,$btnFull,$btnFirewall))

# =========================
# BUTTONS - TUNE
# =========================
$btnBaseline = New-LynextButton "TCP BASELINE" 18 42
$btnMtuFind  = New-LynextButton "DISCOVER MTU" 196 42
$btnMtuSet   = New-LynextButton "APPLY MTU" 374 42
$btnDnsCF    = New-LynextButton "DNS CLOUDFLARE" 18 92
$btnDnsGG    = New-LynextButton "DNS GOOGLE" 196 92
$btnDnsAuto  = New-LynextButton "DNS AUTO" 374 92

$panelTune.Controls.AddRange(@($btnBaseline,$btnMtuFind,$btnMtuSet,$btnDnsCF,$btnDnsGG,$btnDnsAuto))

# =========================
# BUTTONS - LINKS
# =========================
$btnSpeedWeb = New-LynextButton "SPEEDTEST WEB" 100 4 150 36
$btnIntel    = New-LynextButton "INTEL DSA" 260 4 120 36
$btnRealtek  = New-LynextButton "REALTEK" 390 4 120 36
$btnLogs     = New-LynextButton "OPEN LOGS" 520 4 120 36

# fit panel
$btnSpeedWeb.Location = New-Object System.Drawing.Point(100,7)
$btnIntel.Location    = New-Object System.Drawing.Point(255,7)
$btnRealtek.Location  = New-Object System.Drawing.Point(380,7)
$btnLogs.Location     = New-Object System.Drawing.Point(505,7)

$panelLinks.Controls.AddRange(@($btnSpeedWeb,$btnIntel,$btnRealtek,$btnLogs))

# =========================
# TOOLTIPS
# =========================
$toolTip.SetToolTip($btnSnapshot, "Collect adapters, IP, DNS, gateway and default routes.")
$toolTip.SetToolTip($btnPing, "Run 20 ICMP tests and show average, min, max, loss and jitter.")
$toolTip.SetToolTip($btnTrace, "Show route hops to the target.")
$toolTip.SetToolTip($btnPath, "Longer route test with packet loss per hop.")
$toolTip.SetToolTip($btnDns, "Resolve common hosts and show current DNS servers.")
$toolTip.SetToolTip($btnTcp, "Show TCP global settings and offload state.")

$toolTip.SetToolTip($btnFlush, "Clear local DNS cache.")
$toolTip.SetToolTip($btnWinsock, "Reset Winsock catalog. Reboot is recommended.")
$toolTip.SetToolTip($btnResetIp, "Reset IP stack and renew DHCP lease.")
$toolTip.SetToolTip($btnRestart, "Restart the active network adapter.")
$toolTip.SetToolTip($btnFull, "Safe full network reset using supported commands.")
$toolTip.SetToolTip($btnFirewall, "Restore Windows Firewall defaults.")

$toolTip.SetToolTip($btnBaseline, "Restore a safe TCP baseline with autotuning normal and RSS enabled.")
$toolTip.SetToolTip($btnMtuFind, "Find suggested IPv4 MTU using binary search.")
$toolTip.SetToolTip($btnMtuSet, "Apply MTU to a specific adapter.")
$toolTip.SetToolTip($btnDnsCF, "Set Cloudflare DNS on active adapter.")
$toolTip.SetToolTip($btnDnsGG, "Set Google DNS on active adapter.")
$toolTip.SetToolTip($btnDnsAuto, "Restore DNS from DHCP.")

$toolTip.SetToolTip($btnSpeedWeb, "Open Cloudflare speed test in the browser.")
$toolTip.SetToolTip($btnIntel, "Open Intel Driver and Support Assistant.")
$toolTip.SetToolTip($btnRealtek, "Open Realtek download page.")
$toolTip.SetToolTip($btnLogs, "Open Lynext log folder.")

# =========================
# EVENTS - DIAG
# =========================
$btnSnapshot.Add_Click({
    $code = @"
'=== ADAPTERS ==='
Get-NetAdapter | Sort-Object Status, Name | Format-Table -Auto Name, InterfaceDescription, Status, LinkSpeed, MacAddress

'`n=== IP CONFIG ==='
Get-NetIPConfiguration -All | Format-List InterfaceAlias, InterfaceIndex, IPv4Address, IPv6Address, IPv4DefaultGateway, DNSServer

'`n=== PROFILE ==='
Get-NetConnectionProfile | Format-Table -Auto Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity

'`n=== DNS ==='
Get-DnsClientServerAddress | Format-Table -Auto InterfaceAlias, AddressFamily, ServerAddresses

'`n=== DEFAULT ROUTE ==='
Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Format-Table -Auto ifIndex, InterfaceAlias, NextHop, RouteMetric
"@
    Start-LynextAction -Name "Snapshot" -Code $code
})

$btnPing.Add_Click({
    $target = Show-InputDialog -Title "Ping / Jitter" -Label "Host or IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Ping / Jitter for $target" -Code (Get-PingJitterCode -Target $target)
})

$btnTrace.Add_Click({
    $target = Show-InputDialog -Title "Traceroute" -Label "Host or IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Traceroute for $target" -Code (Get-TracertCode -Target $target)
})

$btnPath.Add_Click({
    $target = Show-InputDialog -Title "Pathping" -Label "Host or IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Pathping for $target" -Code (Get-PathPingCode -Target $target)
})

$btnDns.Add_Click({
    $code = @"
'=== CURRENT DNS ==='
Get-DnsClientServerAddress | Format-Table -Auto InterfaceAlias, AddressFamily, ServerAddresses

'`n=== RESOLVE DNS ==='
Resolve-DnsName -Name 'www.cloudflare.com' -Type A | Format-Table -Auto Name, Type, IPAddress, TTL
Resolve-DnsName -Name 'www.google.com' -Type A | Format-Table -Auto Name, Type, IPAddress, TTL
"@
    Start-LynextAction -Name "Resolve DNS" -Code $code
})

$btnTcp.Add_Click({
    $code = @"
netsh int tcp show global
'`n=== TCP SETTINGS ==='
Get-NetTCPSetting | Select-Object SettingName, AutoTuningLevelLocal, CongestionProvider | Format-Table -Auto
'`n=== OFFLOAD GLOBAL ==='
Get-NetOffloadGlobalSetting | Format-List
"@
    Start-LynextAction -Name "Show TCP" -Code $code
})

# =========================
# EVENTS - REPAIR
# =========================
$btnFlush.Add_Click({
    Start-LynextAction -Name "Flush DNS" -Code "ipconfig /flushdns"
})

$btnWinsock.Add_Click({
    $code = @"
netsh winsock reset
'Reboot recommended: YES'
"@
    Start-LynextAction -Name "Reset Winsock" -Code $code
})

$btnResetIp.Add_Click({
    $code = @"
netsh int ip reset
ipconfig /release
Start-Sleep -Seconds 1
ipconfig /renew
'Reboot recommended: YES'
"@
    Start-LynextAction -Name "Reset IP / DHCP" -Code $code
})

$btnRestart.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'No active adapter found.' }
Restart-NetAdapter -Name `$nic.Name -Confirm:`$false
Get-NetAdapter -Name `$nic.Name | Format-Table -Auto Name, Status, LinkSpeed
"@
    Start-LynextAction -Name "Restart Adapter" -Code $code
})

$btnFull.Add_Click({
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
'Reboot recommended: YES'
"@
    Start-LynextAction -Name "Full Reset" -Code $code -Confirm -ConfirmMessage "Run full network reset now?"
})

$btnFirewall.Add_Click({
    $code = @"
netsh advfirewall reset
'Warning: custom firewall rules may be removed.'
"@
    Start-LynextAction -Name "Reset Firewall" -Code $code -Confirm -ConfirmMessage "Reset Windows Firewall defaults?"
})

# =========================
# EVENTS - TUNE
# =========================
$btnBaseline.Add_Click({
    $code = @"
netsh int tcp set global autotuninglevel=normal
netsh int tcp set global rss=enabled
'---'
netsh int tcp show global
"@
    Start-LynextAction -Name "TCP Baseline" -Code $code
})

$btnMtuFind.Add_Click({
    $target = Show-InputDialog -Title "Discover MTU" -Label "Host or IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextAction -Name "Discover MTU for $target" -Code (Get-MtuDiscoveryCode -Target $target)
})

$btnMtuSet.Add_Click({
    $alias = Show-InputDialog -Title "Apply MTU" -Label "Adapter alias:" -DefaultValue (Get-ActiveAdapterName)
    if ([string]::IsNullOrWhiteSpace($alias)) { return }

    $mtuText = Show-InputDialog -Title "Apply MTU" -Label "MTU value:" -DefaultValue "1492"
    if ([string]::IsNullOrWhiteSpace($mtuText)) { return }

    [int]$mtu = 0
    if (-not [int]::TryParse($mtuText, [ref]$mtu)) {
        [System.Windows.Forms.MessageBox]::Show("Invalid MTU value.", "Lynext", "OK", "Error") | Out-Null
        return
    }

    Start-LynextAction -Name "Apply MTU $mtu on $alias" -Code (Get-SetMtuCode -Alias $alias -Mtu $mtu) -Confirm -ConfirmMessage "Apply MTU $mtu on adapter '$alias'?"
})

$btnDnsCF.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'No active adapter found.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ServerAddresses 1.1.1.1,1.0.0.1
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "DNS Cloudflare" -Code $code
})

$btnDnsGG.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'No active adapter found.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ServerAddresses 8.8.8.8,8.8.4.4
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "DNS Google" -Code $code
})

$btnDnsAuto.Add_Click({
    $code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'No active adapter found.' }
Set-DnsClientServerAddress -InterfaceAlias `$nic.Name -ResetServerAddresses
Get-DnsClientServerAddress -InterfaceAlias `$nic.Name | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextAction -Name "DNS Auto" -Code $code
})

# =========================
# EVENTS - LINKS
# =========================
$btnSpeedWeb.Add_Click({
    Start-Process "https://speed.cloudflare.com/"
    Set-Status "Speedtest web opened." "ok"
    Write-Log "Opened speedtest web"
})

$btnIntel.Add_Click({
    Start-Process "https://www.intel.com.br/content/www/br/pt/support/detect.html"
    Set-Status "Intel DSA opened." "ok"
    Write-Log "Opened Intel DSA"
})

$btnRealtek.Add_Click({
    Start-Process "https://www.realtek.com/Download/Overview?menu_id=355"
    Set-Status "Realtek page opened." "ok"
    Write-Log "Opened Realtek page"
})

$btnLogs.Add_Click({
    Start-Process explorer.exe $script:LogDir
    Set-Status "Log folder opened." "ok"
    Write-Log "Opened log folder"
})

# =========================
# ADD CONTROLS
# =========================
$form.Controls.AddRange(@(
    $lblTitle,
    $lblSub,
    $lblCredit,
    $panelDiag,
    $panelFix,
    $panelTune,
    $panelLinks,
    $panelOutput,
    $script:lblStatus,
    $script:prg,
    $lblLog
))

Append-Output "Lynext Network Center started."
Append-Output "Logs: $script:LogFile"
Write-Log "Lynext Network Center started"
Set-Status "Ready" "ok"

[void]$form.ShowDialog()
