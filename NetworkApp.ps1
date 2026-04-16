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
$script:LogDir = Join-Path $env:TEMP "Lynext\Logs"
$null = New-Item -Path $script:LogDir -ItemType Directory -Force
$script:LogFile = Join-Path $script:LogDir ("NetworkApp_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$script:Task = $null
$script:IsBusy = $false

# =========================
# CORES
# =========================
$bgMain      = [System.Drawing.Color]::FromArgb(7,10,18)
$bgPanel     = [System.Drawing.Color]::FromArgb(15,20,32)
$bgPanel2    = [System.Drawing.Color]::FromArgb(20,26,40)
$bgButton    = [System.Drawing.Color]::FromArgb(10,18,30)
$bgHover     = [System.Drawing.Color]::FromArgb(20,30,48)
$bgDown      = [System.Drawing.Color]::FromArgb(28,42,62)
$txtMain     = [System.Drawing.Color]::FromArgb(235,240,250)
$txtSoft     = [System.Drawing.Color]::FromArgb(155,170,190)
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

function Escape-SQ {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return ($Text -replace "'", "''")
}

function Convert-ToEncodedCommand {
    param([string]$Code)
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
}

function Get-ActiveAdapterName {
    try {
        $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface } | Sort-Object ifIndex | Select-Object -First 1
        if (-not $nic) {
            $nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object ifIndex | Select-Object -First 1
        }
        if ($nic) { return $nic.Name }
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
    $cancel.Text = "Cancelar"
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

function Select-AdapterDialog {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Selecionar adaptador"
    $f.Size = New-Object System.Drawing.Size(430,190)
    $f.StartPosition = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.BackColor = $bgMain
    $f.ForeColor = $txtMain

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Escolha o adaptador de rede:"
    $lbl.Location = New-Object System.Drawing.Point(15,18)
    $lbl.Size = New-Object System.Drawing.Size(380,20)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $lbl.ForeColor = $txtMain

    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.Location = New-Object System.Drawing.Point(15,50)
    $cmb.Size = New-Object System.Drawing.Size(385,28)
    $cmb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cmb.BackColor = $bgPanel2
    $cmb.ForeColor = $txtMain
    $cmb.FlatStyle = "Flat"
    $cmb.Font = New-Object System.Drawing.Font("Segoe UI",9)

    try {
        $adaptadores = Get-NetAdapter | Sort-Object Status, Name
        foreach ($ad in $adaptadores) {
            $status = if ($ad.Status) { [string]$ad.Status } else { "Desconhecido" }
            $item = "{0} [{1}]" -f $ad.Name, $status
            [void]$cmb.Items.Add($item)
        }

        $preferido = -1
        for ($i = 0; $i -lt $adaptadores.Count; $i++) {
            if ($adaptadores[$i].Status -eq "Up") {
                $preferido = $i
                break
            }
        }

        if ($preferido -ge 0) {
            $cmb.SelectedIndex = $preferido
        }
        elseif ($cmb.Items.Count -gt 0) {
            $cmb.SelectedIndex = 0
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Falha ao listar adaptadores.", "Lynext", "OK", "Error") | Out-Null
        return $null
    }

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Exemplo: Ethernet, Wi-Fi, Radmin."
    $lblInfo.Location = New-Object System.Drawing.Point(15,85)
    $lblInfo.Size = New-Object System.Drawing.Size(380,18)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI",8)
    $lblInfo.ForeColor = $txtSoft

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Location = New-Object System.Drawing.Point(235,112)
    $ok.Size = New-Object System.Drawing.Size(80,30)
    $ok.FlatStyle = "Flat"
    $ok.BackColor = $bgButton
    $ok.ForeColor = $txtMain
    $ok.FlatAppearance.BorderColor = $borderColor

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancelar"
    $cancel.Location = New-Object System.Drawing.Point(320,112)
    $cancel.Size = New-Object System.Drawing.Size(80,30)
    $cancel.FlatStyle = "Flat"
    $cancel.BackColor = $bgButton
    $cancel.ForeColor = $txtMain
    $cancel.FlatAppearance.BorderColor = $borderColor

    $ok.Add_Click({
        if ($cmb.SelectedIndex -ge 0) {
            $f.Tag = $adaptadores[$cmb.SelectedIndex].Name
            $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $f.Close()
        }
    })

    $cancel.Add_Click({
        $f.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $f.Close()
    })

    $f.Controls.AddRange(@($lbl,$cmb,$lblInfo,$ok,$cancel))
    $f.AcceptButton = $ok
    $f.CancelButton = $cancel

    if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return [string]$f.Tag
    }

    return $null
}

function New-LynextButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 170,
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

function Start-LynextTask {
    param(
        [string]$Name,
        [string]$Code,
        [switch]$Confirm,
        [string]$ConfirmMessage = "Confirmar execucao?"
    )

    if ($script:IsBusy) {
        Set-Status "Aguarde a acao atual terminar." "warn"
        return
    }

    if ($Confirm) {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            $ConfirmMessage,
            "Lynext",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    $outFile = Join-Path $script:LogDir ("task_out_{0}.txt" -f ([guid]::NewGuid().ToString("N")))
    $errFile = Join-Path $script:LogDir ("task_err_{0}.txt" -f ([guid]::NewGuid().ToString("N")))

    $fullCode = @"
`$ProgressPreference = 'SilentlyContinue'
`$ErrorActionPreference = 'Stop'
$Code
"@

    $encoded = Convert-ToEncodedCommand $fullCode

    Append-Output ">>> $Name" -Clear
    Set-Status "Executando: $Name" "busy"
    Write-Log "START: $Name"
    $script:prg.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $script:IsBusy = $true

    $proc = Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError $errFile `
        -WindowStyle Hidden `
        -PassThru

    $script:Task = [pscustomobject]@{
        Name = $Name
        Process = $proc
        OutFile = $outFile
        ErrFile = $errFile
        LastOutLen = 0
        LastErrLen = 0
    }
}

function Finish-LynextTask {
    if (-not $script:Task) { return }

    $task = $script:Task

    if (Test-Path $task.OutFile) {
        $out = Get-Content $task.OutFile -Raw -ErrorAction SilentlyContinue
        if ($out.Length -gt $task.LastOutLen) {
            $new = $out.Substring($task.LastOutLen)
            if (-not [string]::IsNullOrWhiteSpace($new)) {
                Append-Output $new.TrimEnd()
            }
        }
    }

    if (Test-Path $task.ErrFile) {
        $err = Get-Content $task.ErrFile -Raw -ErrorAction SilentlyContinue
        if ($err.Length -gt $task.LastErrLen) {
            $newErr = $err.Substring($task.LastErrLen)
            if (-not [string]::IsNullOrWhiteSpace($newErr)) {
                Append-Output ("ERRO:`r`n" + $newErr.TrimEnd())
            }
        }
    }

    $exitCode = $task.Process.ExitCode

    if ($exitCode -eq 0) {
        if ((Test-Path $task.ErrFile) -and ((Get-Item $task.ErrFile).Length -gt 0)) {
            Set-Status "$($task.Name) concluido com avisos." "warn"
            Write-Log "WARN: $($task.Name)" "WARN"
        }
        else {
            Set-Status "$($task.Name) concluido." "ok"
            Write-Log "OK: $($task.Name)"
        }
    }
    else {
        Set-Status "$($task.Name) falhou." "error"
        Write-Log "FAIL: $($task.Name) ExitCode=$exitCode" "ERROR"
    }

    $script:prg.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $script:IsBusy = $false
    $script:Task = $null
}

function Poll-LynextTask {
    if (-not $script:Task) { return }

    $task = $script:Task

    if (Test-Path $task.OutFile) {
        $out = Get-Content $task.OutFile -Raw -ErrorAction SilentlyContinue
        if ($out.Length -gt $task.LastOutLen) {
            $new = $out.Substring($task.LastOutLen)
            $task.LastOutLen = $out.Length
            $script:Task = $task
            if (-not [string]::IsNullOrWhiteSpace($new)) {
                Append-Output $new.TrimEnd()
            }
        }
    }

    if (Test-Path $task.ErrFile) {
        $err = Get-Content $task.ErrFile -Raw -ErrorAction SilentlyContinue
        if ($err.Length -gt $task.LastErrLen) {
            $newErr = $err.Substring($task.LastErrLen)
            $task.LastErrLen = $err.Length
            $script:Task = $task
            if (-not [string]::IsNullOrWhiteSpace($newErr)) {
                Append-Output ("ERRO:`r`n" + $newErr.TrimEnd())
            }
        }
    }

    if ($task.Process.HasExited) {
        Finish-LynextTask
    }
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

[pscustomobject]@{
    Destino = `$target
    Enviados = `$sent
    Recebidos = `$received
    PerdaPercent = `$loss
    MediaMs = `$avg
    MinMs = `$min
    MaxMs = `$max
    JitterMs = `$jitter
    Amostras = (`$samples -join ', ')
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
    throw 'Falha mesmo com payload 1200. Verifique conectividade.'
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
    Destino = `$target
    MelhorPayload = `$best
    MTU_Sugerido = `$mtu
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
$toolTip.InitialDelay = 300
$toolTip.ReshowDelay = 150
$toolTip.ShowAlways = $true

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext | Rede"
$form.Size = New-Object System.Drawing.Size(1180,760)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgMain
$form.ForeColor = $txtMain
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Lynext"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",24,[System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $accent
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(24,18)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Central de rede | diagnostico, reparo e baseline segura"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI",10)
$lblSub.ForeColor = $txtSoft
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(28,62)

$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text = "Created by Ryan"
$lblCredit.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Italic)
$lblCredit.ForeColor = $txtSoft
$lblCredit.AutoSize = $true
$lblCredit.Location = New-Object System.Drawing.Point(1010,24)

# LEFT
$panelDiag = New-Object System.Windows.Forms.Panel
$panelDiag.Location = New-Object System.Drawing.Point(24,100)
$panelDiag.Size = New-Object System.Drawing.Size(540,170)
$panelDiag.BackColor = $bgPanel

$panelFix = New-Object System.Windows.Forms.Panel
$panelFix.Location = New-Object System.Drawing.Point(24,285)
$panelFix.Size = New-Object System.Drawing.Size(540,170)
$panelFix.BackColor = $bgPanel

$panelTune = New-Object System.Windows.Forms.Panel
$panelTune.Location = New-Object System.Drawing.Point(24,470)
$panelTune.Size = New-Object System.Drawing.Size(540,170)
$panelTune.BackColor = $bgPanel

$panelLinks = New-Object System.Windows.Forms.Panel
$panelLinks.Location = New-Object System.Drawing.Point(24,655)
$panelLinks.Size = New-Object System.Drawing.Size(540,50)
$panelLinks.BackColor = $bgPanel

function New-SectionTitle {
    param([string]$Text)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $txtMain
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(14,10)
    return $lbl
}

$panelDiag.Controls.Add((New-SectionTitle "DIAGNOSTICO"))
$panelFix.Controls.Add((New-SectionTitle "REPARO"))
$panelTune.Controls.Add((New-SectionTitle "OTIMIZACAO"))
$panelLinks.Controls.Add((New-SectionTitle "LINKS"))

# OUTPUT
$panelOutput = New-Object System.Windows.Forms.Panel
$panelOutput.Location = New-Object System.Drawing.Point(580,100)
$panelOutput.Size = New-Object System.Drawing.Size(575,605)
$panelOutput.BackColor = $bgPanel

$outTitle = New-Object System.Windows.Forms.Label
$outTitle.Text = "SAIDA"
$outTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$outTitle.ForeColor = $txtMain
$outTitle.AutoSize = $true
$outTitle.Location = New-Object System.Drawing.Point(14,10)

$script:txtOutput = New-Object System.Windows.Forms.TextBox
$script:txtOutput.Location = New-Object System.Drawing.Point(15,40)
$script:txtOutput.Size = New-Object System.Drawing.Size(545,550)
$script:txtOutput.Multiline = $true
$script:txtOutput.ScrollBars = "Vertical"
$script:txtOutput.ReadOnly = $true
$script:txtOutput.BackColor = $bgPanel2
$script:txtOutput.ForeColor = $txtMain
$script:txtOutput.BorderStyle = "FixedSingle"
$script:txtOutput.Font = New-Object System.Drawing.Font("Consolas",9)

$panelOutput.Controls.Add($outTitle)
$panelOutput.Controls.Add($script:txtOutput)

# STATUS
$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = "Status: Pronto"
$script:lblStatus.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$script:lblStatus.ForeColor = $okColor
$script:lblStatus.AutoSize = $true
$script:lblStatus.Location = New-Object System.Drawing.Point(24,720)

$script:prg = New-Object System.Windows.Forms.ProgressBar
$script:prg.Location = New-Object System.Drawing.Point(220,721)
$script:prg.Size = New-Object System.Drawing.Size(340,14)
$script:prg.Style = "Blocks"

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log: $script:LogFile"
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI",8)
$lblLog.ForeColor = $txtSoft
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(580,720)

# =========================
# BOTOES
# =========================
# Diagnostico
$btnSnapshot = New-LynextButton "SNAPSHOT" 15 42
$btnPing     = New-LynextButton "PING / JITTER" 185 42
$btnTrace    = New-LynextButton "TRACEROUTE" 355 42
$btnPath     = New-LynextButton "PATHPING" 15 95
$btnDns      = New-LynextButton "RESOLVER DNS" 185 95
$btnTcp      = New-LynextButton "MOSTRAR TCP" 355 95

$panelDiag.Controls.AddRange(@($btnSnapshot,$btnPing,$btnTrace,$btnPath,$btnDns,$btnTcp))

# Reparo
$btnFlush    = New-LynextButton "FLUSH DNS" 15 42
$btnWinsock  = New-LynextButton "RESET WINSOCK" 185 42
$btnResetIp  = New-LynextButton "RESET IP / DHCP" 355 42
$btnRestart  = New-LynextButton "REINICIAR ADAPTADOR" 15 95
$btnFull     = New-LynextButton "RESET COMPLETO" 185 95
$btnFirewall = New-LynextButton "RESET FIREWALL" 355 95

$panelFix.Controls.AddRange(@($btnFlush,$btnWinsock,$btnResetIp,$btnRestart,$btnFull,$btnFirewall))

# Otimizacao
$btnBaseline = New-LynextButton "BASELINE TCP" 15 42
$btnMtuFind  = New-LynextButton "DESCOBRIR MTU" 185 42
$btnMtuSet   = New-LynextButton "APLICAR MTU" 355 42
$btnDnsCF    = New-LynextButton "DNS CLOUDFLARE" 15 95
$btnDnsGG    = New-LynextButton "DNS GOOGLE" 185 95
$btnDnsAuto  = New-LynextButton "DNS AUTOMATICO" 355 95

$panelTune.Controls.AddRange(@($btnBaseline,$btnMtuFind,$btnMtuSet,$btnDnsCF,$btnDnsGG,$btnDnsAuto))

# Links
$btnSpeedWeb = New-LynextButton "SPEEDTEST WEB" 55 7 125 34
$btnIntel    = New-LynextButton "INTEL DSA" 190 7 110 34
$btnRealtek  = New-LynextButton "REALTEK" 310 7 100 34
$btnLogs     = New-LynextButton "ABRIR LOGS" 420 7 105 34

$panelLinks.Controls.AddRange(@($btnSpeedWeb,$btnIntel,$btnRealtek,$btnLogs))

# =========================
# TOOLTIPS
# =========================
$toolTip.SetToolTip($btnSnapshot, "Coleta adaptadores, IP, gateway, DNS e rota padrao.")
$toolTip.SetToolTip($btnPing, "Executa 20 testes ICMP e mostra media, min, max, perda e jitter.")
$toolTip.SetToolTip($btnTrace, "Mostra os saltos ate o destino.")
$toolTip.SetToolTip($btnPath, "Teste de rota com perda por salto. Pode demorar.")
$toolTip.SetToolTip($btnDns, "Mostra DNS atual e testa resolucao.")
$toolTip.SetToolTip($btnTcp, "Mostra estado global do TCP e offloads.")

$toolTip.SetToolTip($btnFlush, "Limpa o cache DNS local.")
$toolTip.SetToolTip($btnWinsock, "Reseta o catalogo Winsock. Reinicio recomendado.")
$toolTip.SetToolTip($btnResetIp, "Reseta a pilha IP e renova o DHCP.")
$toolTip.SetToolTip($btnRestart, "Reinicia o adaptador ativo.")
$toolTip.SetToolTip($btnFull, "Executa um reset seguro de rede.")
$toolTip.SetToolTip($btnFirewall, "Restaura os padroes do firewall do Windows.")

$toolTip.SetToolTip($btnBaseline, "Aplica baseline segura de TCP.")
$toolTip.SetToolTip($btnMtuFind, "Descobre um MTU sugerido por teste real.")
$toolTip.SetToolTip($btnMtuSet, "Aplica MTU no adaptador escolhido.")
$toolTip.SetToolTip($btnDnsCF, "Pergunta o adaptador e aplica DNS Cloudflare.")
$toolTip.SetToolTip($btnDnsGG, "Pergunta o adaptador e aplica DNS Google.")
$toolTip.SetToolTip($btnDnsAuto, "Pergunta o adaptador e restaura DNS automatico.")

$toolTip.SetToolTip($btnSpeedWeb, "Abre speed.cloudflare.com")
$toolTip.SetToolTip($btnIntel, "Abre Intel Driver and Support Assistant.")
$toolTip.SetToolTip($btnRealtek, "Abre o portal da Realtek.")
$toolTip.SetToolTip($btnLogs, "Abre a pasta de logs do Lynext.")

# =========================
# EVENTOS - DIAGNOSTICO
# =========================
$btnSnapshot.Add_Click({
$code = @"
'=== ADAPTADORES ==='
Get-NetAdapter | Sort-Object Status, Name | Format-Table -Auto Name, InterfaceDescription, Status, LinkSpeed, MacAddress

'`n=== IP CONFIG ==='
Get-NetIPConfiguration -All | Format-List InterfaceAlias, InterfaceIndex, IPv4Address, IPv6Address, IPv4DefaultGateway, DNSServer

'`n=== PERFIL ==='
Get-NetConnectionProfile | Format-Table -Auto Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity

'`n=== DNS ==='
Get-DnsClientServerAddress | Format-Table -Auto InterfaceAlias, AddressFamily, ServerAddresses

'`n=== ROTA PADRAO ==='
Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Format-Table -Auto ifIndex, InterfaceAlias, NextHop, RouteMetric
"@
    Start-LynextTask -Name "Snapshot" -Code $code
})

$btnPing.Add_Click({
    $target = Show-InputDialog -Title "Ping / Jitter" -Label "Host ou IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextTask -Name "Ping / Jitter para $target" -Code (Get-PingJitterCode -Target $target)
})

$btnTrace.Add_Click({
    $target = Show-InputDialog -Title "Traceroute" -Label "Host ou IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextTask -Name "Traceroute para $target" -Code (Get-TracertCode -Target $target)
})

$btnPath.Add_Click({
    $target = Show-InputDialog -Title "Pathping" -Label "Host ou IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextTask -Name "Pathping para $target" -Code (Get-PathPingCode -Target $target)
})

$btnDns.Add_Click({
$code = @"
'=== DNS ATUAL ==='
Get-DnsClientServerAddress | Format-Table -Auto InterfaceAlias, AddressFamily, ServerAddresses

'`n=== TESTE DE RESOLUCAO ==='
Resolve-DnsName -Name 'www.cloudflare.com' -Type A | Format-Table -Auto Name, Type, IPAddress, TTL
Resolve-DnsName -Name 'www.google.com' -Type A | Format-Table -Auto Name, Type, IPAddress, TTL
"@
    Start-LynextTask -Name "Resolver DNS" -Code $code
})

$btnTcp.Add_Click({
$code = @"
netsh int tcp show global
'`n=== TCP SETTINGS ==='
Get-NetTCPSetting | Select-Object SettingName, AutoTuningLevelLocal, CongestionProvider | Format-Table -Auto
'`n=== OFFLOAD GLOBAL ==='
Get-NetOffloadGlobalSetting | Format-List
"@
    Start-LynextTask -Name "Mostrar TCP" -Code $code
})

# =========================
# EVENTOS - REPARO
# =========================
$btnFlush.Add_Click({
    Start-LynextTask -Name "Flush DNS" -Code "ipconfig /flushdns"
})

$btnWinsock.Add_Click({
$code = @"
netsh winsock reset
'Reinicio recomendado: SIM'
"@
    Start-LynextTask -Name "Reset Winsock" -Code $code
})

$btnResetIp.Add_Click({
$code = @"
netsh int ip reset
ipconfig /release
Start-Sleep -Seconds 1
ipconfig /renew
'Reinicio recomendado: SIM'
"@
    Start-LynextTask -Name "Reset IP / DHCP" -Code $code
})

$btnRestart.Add_Click({
$code = @"
`$nic = Get-NetAdapter | Where-Object { `$_.Status -eq 'Up' } | Sort-Object ifIndex | Select-Object -First 1
if (-not `$nic) { throw 'Nenhum adaptador ativo encontrado.' }
Restart-NetAdapter -Name `$nic.Name -Confirm:`$false
Get-NetAdapter -Name `$nic.Name | Format-Table -Auto Name, Status, LinkSpeed
"@
    Start-LynextTask -Name "Reiniciar adaptador" -Code $code
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
'Reinicio recomendado: SIM'
"@
    Start-LynextTask -Name "Reset completo" -Code $code -Confirm -ConfirmMessage "Executar reset completo de rede?"
})

$btnFirewall.Add_Click({
$code = @"
netsh advfirewall reset
'Aviso: regras personalizadas do firewall podem ser removidas.'
"@
    Start-LynextTask -Name "Reset Firewall" -Code $code -Confirm -ConfirmMessage "Resetar o firewall do Windows?"
})

# =========================
# EVENTOS - OTIMIZACAO
# =========================
$btnBaseline.Add_Click({
$code = @"
netsh int tcp set global autotuninglevel=normal
netsh int tcp set global rss=enabled
'---'
netsh int tcp show global
"@
    Start-LynextTask -Name "Baseline TCP" -Code $code
})

$btnMtuFind.Add_Click({
    $target = Show-InputDialog -Title "Descobrir MTU" -Label "Host ou IP:" -DefaultValue "1.1.1.1"
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    Start-LynextTask -Name "Descobrir MTU para $target" -Code (Get-MtuDiscoveryCode -Target $target)
})

$btnMtuSet.Add_Click({
    $alias = Select-AdapterDialog
    if ([string]::IsNullOrWhiteSpace($alias)) { return }

    $mtuText = Show-InputDialog -Title "Aplicar MTU" -Label "Valor do MTU:" -DefaultValue "1492"
    if ([string]::IsNullOrWhiteSpace($mtuText)) { return }

    [int]$mtu = 0
    if (-not [int]::TryParse($mtuText, [ref]$mtu)) {
        [System.Windows.Forms.MessageBox]::Show("Valor de MTU invalido.", "Lynext", "OK", "Error") | Out-Null
        return
    }

    Start-LynextTask -Name "Aplicar MTU $mtu em $alias" -Code (Get-SetMtuCode -Alias $alias -Mtu $mtu) -Confirm -ConfirmMessage "Aplicar MTU $mtu em '$alias'?"
})

$btnDnsCF.Add_Click({
    $adaptador = Select-AdapterDialog
    if ([string]::IsNullOrWhiteSpace($adaptador)) { return }

    $a = Escape-SQ $adaptador
$code = @"
Set-DnsClientServerAddress -InterfaceAlias '$a' -ServerAddresses 1.1.1.1,1.0.0.1
Get-DnsClientServerAddress -InterfaceAlias '$a' | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextTask -Name "DNS Cloudflare em $adaptador" -Code $code
})

$btnDnsGG.Add_Click({
    $adaptador = Select-AdapterDialog
    if ([string]::IsNullOrWhiteSpace($adaptador)) { return }

    $a = Escape-SQ $adaptador
$code = @"
Set-DnsClientServerAddress -InterfaceAlias '$a' -ServerAddresses 8.8.8.8,8.8.4.4
Get-DnsClientServerAddress -InterfaceAlias '$a' | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextTask -Name "DNS Google em $adaptador" -Code $code
})

$btnDnsAuto.Add_Click({
    $adaptador = Select-AdapterDialog
    if ([string]::IsNullOrWhiteSpace($adaptador)) { return }

    $a = Escape-SQ $adaptador
$code = @"
Set-DnsClientServerAddress -InterfaceAlias '$a' -ResetServerAddresses
Get-DnsClientServerAddress -InterfaceAlias '$a' | Format-Table -Auto InterfaceAlias, ServerAddresses
"@
    Start-LynextTask -Name "DNS automatico em $adaptador" -Code $code
})

# =========================
# EVENTOS - LINKS
# =========================
$btnSpeedWeb.Add_Click({
    Start-Process "https://speed.cloudflare.com/"
    Set-Status "Speedtest web aberto." "ok"
    Write-Log "Opened speedtest web"
})

$btnIntel.Add_Click({
    Start-Process "https://www.intel.com.br/content/www/br/pt/support/detect.html"
    Set-Status "Intel DSA aberto." "ok"
    Write-Log "Opened Intel DSA"
})

$btnRealtek.Add_Click({
    Start-Process "https://www.realtek.com/Download/Overview?menu_id=355"
    Set-Status "Portal Realtek aberto." "ok"
    Write-Log "Opened Realtek"
})

$btnLogs.Add_Click({
    Start-Process explorer.exe $script:LogDir
    Set-Status "Pasta de logs aberta." "ok"
    Write-Log "Opened logs folder"
})

# =========================
# TIMER
# =========================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    Poll-LynextTask
})
$timer.Start()

# =========================
# ADD
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

Append-Output "Lynext Rede iniciado."
Append-Output "Log: $script:LogFile"
Write-Log "Lynext Rede iniciado"
Set-Status "Pronto" "ok"

[void]$form.ShowDialog()
