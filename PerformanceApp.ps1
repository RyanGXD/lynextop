Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================================================
# LYNEXT - PERFORMANCE APP V3
# Layout reformulado com foco visual parecido com o Downloads
# =========================================================

# =========================================================
# ADMIN
# =========================================================
$scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

# =========================================================
# PATHS
# =========================================================
$script:LynextRoot = Join-Path $env:ProgramData "Lynext"
$script:BackupFile = Join-Path $script:LynextRoot "performance_backup.json"
$script:LogDir     = Join-Path $script:LynextRoot "Logs"
$null = New-Item -Path $script:LynextRoot -ItemType Directory -Force
$null = New-Item -Path $script:LogDir -ItemType Directory -Force
$script:LogFile = Join-Path $script:LogDir ("PerformanceApp_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$script:Task = $null
$script:IsBusy = $false
$script:CurrentSection = "overview"
$script:SectionPanels = @{}

# =========================================================
# TEMA - VERDE ESCURO SUAVE
# =========================================================
$bgMain        = [System.Drawing.Color]::FromArgb(7,10,9)
$bgHeader      = [System.Drawing.Color]::FromArgb(9,14,12)
$bgSidebar     = [System.Drawing.Color]::FromArgb(12,18,15)
$bgCard        = [System.Drawing.Color]::FromArgb(19,26,23)
$bgCard2       = [System.Drawing.Color]::FromArgb(15,21,18)
$bgEditor      = [System.Drawing.Color]::FromArgb(10,14,12)
$bgButton      = [System.Drawing.Color]::FromArgb(28,41,34)
$bgButtonHover = [System.Drawing.Color]::FromArgb(34,54,43)
$bgButtonDown  = [System.Drawing.Color]::FromArgb(42,67,52)
$txtMain       = [System.Drawing.Color]::FromArgb(236,241,237)
$txtSoft       = [System.Drawing.Color]::FromArgb(156,173,163)
$txtMuted      = [System.Drawing.Color]::FromArgb(120,136,128)
$accent        = [System.Drawing.Color]::FromArgb(102,182,128)
$accent2       = [System.Drawing.Color]::FromArgb(130,215,156)
$borderColor   = [System.Drawing.Color]::FromArgb(64,88,73)
$okColor       = [System.Drawing.Color]::FromArgb(113,224,146)
$warnColor     = [System.Drawing.Color]::FromArgb(245,205,102)
$errColor      = [System.Drawing.Color]::FromArgb(255,120,120)
$sidebarActive = [System.Drawing.Color]::FromArgb(28,44,36)

# =========================================================
# HELPERS GERAIS
# =========================================================
function Write-LogLine {
    param([string]$Text)
    try {
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
    catch {}
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
        "busy"  { $script:lblStatus.ForeColor = $accent2 }
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

function Get-RegValue {
    param([string]$Path,[string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Get-ActivePowerSchemeGuid {
    $line = powercfg /getactivescheme
    if ($line -match '([a-fA-F0-9-]{36})') { return $Matches[1] }
    return $null
}

function Test-ModernStandby {
    try {
        $out = powercfg /a | Out-String
        if ($out -match "Standby \(S0 Low Power Idle\)") { return $true }
    }
    catch {}
    return $false
}

function Get-GpuVendor {
    try {
        $gpuNames = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
        $all = ($gpuNames -join " | ")
        if ($all -match "NVIDIA") { return "NVIDIA" }
        if ($all -match "AMD|Radeon") { return "AMD" }
        if ($all -match "Intel") { return "Intel" }
    }
    catch {}
    return "Unknown"
}

function Get-IsLaptop {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.PCSystemType -in 2,3,4,8,9,10,14) { return $true }
    }
    catch {}
    return $false
}

function Get-NvidiaSmiPath {
    $path1 = Join-Path $env:ProgramFiles "NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (Test-Path $path1) { return $path1 }

    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($pf86) {
        $path2 = Join-Path $pf86 "NVIDIA Corporation\NVSMI\nvidia-smi.exe"
        if (Test-Path $path2) { return $path2 }
    }
    return $null
}

function Ensure-BackupExists {
    if (-not (Test-Path $script:BackupFile)) {
        Start-LynextTask -Name "Criar Backup Inicial" -Code (Get-BackupCode)
        return $false
    }
    return $true
}

function Show-InputDialog {
    param(
        [string]$Title,
        [string]$Label,
        [string]$DefaultValue = ""
    )

    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.Size = New-Object System.Drawing.Size(430,165)
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
    $tb.BackColor = $bgCard
    $tb.ForeColor = $txtMain
    $tb.BorderStyle = "FixedSingle"
    $tb.Font = New-Object System.Drawing.Font("Segoe UI",9)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.Location = New-Object System.Drawing.Point(230,84)
    $ok.Size = New-Object System.Drawing.Size(80,32)
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
    $cancel.Location = New-Object System.Drawing.Point(320,84)
    $cancel.Size = New-Object System.Drawing.Size(80,32)
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
        [int]$H = 40
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
    $btn.FlatAppearance.MouseOverBackColor = $bgButtonHover
    $btn.FlatAppearance.MouseDownBackColor = $bgButtonDown
    $btn.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    return $btn
}

function New-SidebarButton {
    param(
        [string]$Key,
        [string]$Text,
        [int]$Y
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Tag = $Key
    $btn.Location = New-Object System.Drawing.Point(14,$Y)
    $btn.Size = New-Object System.Drawing.Size(206,42)
    $btn.BackColor = $bgSidebar
    $btn.ForeColor = $txtMain
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = $borderColor
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.MouseOverBackColor = $bgButtonHover
    $btn.FlatAppearance.MouseDownBackColor = $bgButtonDown
    $btn.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    return $btn
}

function New-CardPanel {
    param(
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H
    )

    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X,$Y)
    $p.Size = New-Object System.Drawing.Size($W,$H)
    $p.BackColor = $bgCard
    $p.BorderStyle = 'FixedSingle'
    return $p
}

function Add-SectionLabel {
    param($parent,[string]$text,[int]$x,[int]$y,[int]$size=11)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x,$y)
    $lbl.AutoSize = $true
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",$size,[System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $txtMain
    $parent.Controls.Add($lbl)
    return $lbl
}

function Add-SoftLabel {
    param($parent,[string]$text,[int]$x,[int]$y,[int]$w=500,[int]$h=34)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x,$y)
    $lbl.Size = New-Object System.Drawing.Size($w,$h)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $lbl.ForeColor = $txtSoft
    $parent.Controls.Add($lbl)
    return $lbl
}

function New-InfoValueLabel {
    param($parent,[string]$value,[int]$x,[int]$y,[int]$w=220)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $value
    $lbl.Location = New-Object System.Drawing.Point($x,$y)
    $lbl.Size = New-Object System.Drawing.Size($w,24)
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $accent2
    $parent.Controls.Add($lbl)
    return $lbl
}

function Set-SidebarActive {
    param([string]$Key)

    foreach ($btn in $script:sidebarButtons) {
        if ($btn.Tag -eq $Key) {
            $btn.BackColor = $sidebarActive
            $btn.ForeColor = $accent2
        }
        else {
            $btn.BackColor = $bgSidebar
            $btn.ForeColor = $txtMain
        }
    }
}

function Show-Section {
    param([string]$Key)

    foreach ($name in $script:SectionPanels.Keys) {
        $script:SectionPanels[$name].Visible = ($name -eq $Key)
    }

    $script:CurrentSection = $Key
    Set-SidebarActive $Key
}

# =========================================================
# EXECUCAO DE TAREFAS
# =========================================================
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
    Write-LogLine "START: $Name"
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
            Write-LogLine "WARN: $($task.Name)"
        }
        else {
            Set-Status "$($task.Name) concluido." "ok"
            Write-LogLine "OK: $($task.Name)"
        }
    }
    else {
        Set-Status "$($task.Name) falhou." "error"
        Write-LogLine "FAIL: $($task.Name) ExitCode=$exitCode"
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

# =========================================================
# CODES / ACTIONS
# =========================================================
function Get-BackupCode {
@"
function Get-RegValue {
    param([string]`$Path,[string]`$Name)
    try { return (Get-ItemProperty -Path `$Path -Name `$Name -ErrorAction Stop).`$Name } catch { return `$null }
}
function Get-ActivePowerSchemeGuid {
    `$line = powercfg /getactivescheme
    if (`$line -match '([a-fA-F0-9-]{36})') { return `$Matches[1] }
    return `$null
}
function Test-ModernStandby {
    try {
        `$out = powercfg /a | Out-String
        if (`$out -match "Standby \(S0 Low Power Idle\)") { return `$true }
    }
    catch {}
    return `$false
}
function Get-GpuVendor {
    try {
        `$gpuNames = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
        `$all = (`$gpuNames -join " | ")
        if (`$all -match "NVIDIA") { return "NVIDIA" }
        if (`$all -match "AMD|Radeon") { return "AMD" }
        if (`$all -match "Intel") { return "Intel" }
    }
    catch {}
    return "Unknown"
}
function Get-IsLaptop {
    try {
        `$cs = Get-CimInstance Win32_ComputerSystem
        if (`$cs.PCSystemType -in 2,3,4,8,9,10,14) { return `$true }
    }
    catch {}
    return `$false
}
function Get-NvidiaSmiPath {
    `$path1 = Join-Path `$env:ProgramFiles "NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    if (Test-Path `$path1) { return `$path1 }
    `$pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if (`$pf86) {
        `$path2 = Join-Path `$pf86 "NVIDIA Corporation\NVSMI\nvidia-smi.exe"
        if (Test-Path `$path2) { return `$path2 }
    }
    return `$null
}
`$data = @{
    CreatedAt = (Get-Date).ToString("s")
    PowerSchemeGuid = Get-ActivePowerSchemeGuid
    ModernStandby = Test-ModernStandby
    GpuVendor = Get-GpuVendor
    IsLaptop = Get-IsLaptop
    Registry = @{
        AutoGameModeEnabled    = Get-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled"
        AllowAutoGameMode      = Get-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode"
        AppCaptureEnabled      = Get-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled"
        GameDVR_Enabled        = Get-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled"
        HwSchMode              = Get-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode"
        NetworkThrottlingIndex = Get-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex"
        SystemResponsiveness   = Get-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness"
        PowerThrottlingOff     = Get-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff"
    }
    Nvidia = @{
        DefaultPowerLimit = `$null
    }
}
`$nvidiaSmi = Get-NvidiaSmiPath
if (`$nvidiaSmi) {
    try {
        `$pl = & `$nvidiaSmi --query-gpu=power.default_limit --format=csv,noheader,nounits 2>`$null
        if (`$pl) {
            `$plText = (`$pl | Select-Object -First 1).ToString().Trim()
            if (`$plText -match '^\d+(\.\d+)?$') {
                `$data.Nvidia.DefaultPowerLimit = [double]`$plText
            }
        }
    }
    catch {}
}
`$data | ConvertTo-Json -Depth 12 | Set-Content -Path '$($script:BackupFile)' -Encoding UTF8
'Backup salvo com sucesso.'
"@
}

function Get-CPUUltraCode {
@"
function Set-PowerValueSafe {
    param([string]`$Subgroup,[string]`$Setting,[int]`$AcValue,[int]`$DcValue)
    try { powercfg /setacvalueindex scheme_current `$Subgroup `$Setting `$AcValue | Out-Null } catch {}
    try { powercfg /setdcvalueindex scheme_current `$Subgroup `$Setting `$DcValue | Out-Null } catch {}
    try { powercfg /setactive scheme_current | Out-Null } catch {}
}
function Test-ModernStandby {
    try {
        `$out = powercfg /a | Out-String
        if (`$out -match "Standby \(S0 Low Power Idle\)") { return `$true }
    }
    catch {}
    return `$false
}
`$modern = Test-ModernStandby
if (`$modern) {
    powercfg /setactive SCHEME_BALANCED | Out-Null
    'Modern Standby detectado. Usando Balanced compativel.'
}
else {
    try {
        `$guid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        `$result = powercfg -duplicatescheme `$guid 2>&1 | Out-String
        if (`$result -match '([a-fA-F0-9-]{36})') {
            `$newGuid = `$Matches[1]
            powercfg /changename `$newGuid 'Lynext Ultra Performance' | Out-Null
            powercfg /setactive `$newGuid | Out-Null
            'Plano Lynext Ultra Performance ativado.'
        }
        else {
            powercfg /setactive SCHEME_MIN | Out-Null
            'Ultimate indisponivel. Usando High Performance.'
        }
    }
    catch {
        powercfg /setactive SCHEME_MIN | Out-Null
        'Ultimate indisponivel. Usando High Performance.'
    }
}
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PROCTHROTTLEMIN'    -AcValue 100 -DcValue 50
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PROCTHROTTLEMAX'    -AcValue 100 -DcValue 100
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFEPP'            -AcValue 0   -DcValue 15
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFBOOSTMODE'      -AcValue 2   -DcValue 1
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'CPMINCORES'         -AcValue 100 -DcValue 50
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFAUTONOMOUSMODE' -AcValue 1   -DcValue 1
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'SYSCOOLPOL'         -AcValue 1   -DcValue 1
'CPU Ultra aplicado.'
"@
}

function Get-CPULiteCode {
@"
function Set-PowerValueSafe {
    param([string]`$Subgroup,[string]`$Setting,[int]`$AcValue,[int]`$DcValue)
    try { powercfg /setacvalueindex scheme_current `$Subgroup `$Setting `$AcValue | Out-Null } catch {}
    try { powercfg /setdcvalueindex scheme_current `$Subgroup `$Setting `$DcValue | Out-Null } catch {}
    try { powercfg /setactive scheme_current | Out-Null } catch {}
}
function Test-ModernStandby {
    try {
        `$out = powercfg /a | Out-String
        if (`$out -match "Standby \(S0 Low Power Idle\)") { return `$true }
    }
    catch {}
    return `$false
}
function Get-IsLaptop {
    try {
        `$cs = Get-CimInstance Win32_ComputerSystem
        if (`$cs.PCSystemType -in 2,3,4,8,9,10,14) { return `$true }
    }
    catch {}
    return `$false
}
function Ensure-LitePlan {
    try {
        `$list = powercfg /list | Out-String
        `$match = [regex]::Match(`$list, '([a-fA-F0-9-]{36}).*Lynext Lite')
        if (`$match.Success) { return `$match.Groups[1].Value }

        `$dup = powercfg -duplicatescheme SCHEME_BALANCED 2>&1 | Out-String
        if (`$dup -match '([a-fA-F0-9-]{36})') {
            `$guid = `$Matches[1]
            powercfg /changename `$guid 'Lynext Lite' | Out-Null
            return `$guid
        }
    }
    catch {}
    return `$null
}
`$modern = Test-ModernStandby
`$isLaptop = Get-IsLaptop
if (`$modern -or `$isLaptop) {
    powercfg /setactive SCHEME_BALANCED | Out-Null
    'Balanced mantido por compatibilidade.'
}
else {
    `$guid = Ensure-LitePlan
    if (`$guid) {
        powercfg /setactive `$guid | Out-Null
        'Plano Lynext Lite ativado.'
    }
    else {
        powercfg /setactive SCHEME_BALANCED | Out-Null
        'Nao consegui ativar Lynext Lite. Usando Balanced.'
    }
}
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PROCTHROTTLEMIN'    -AcValue 5   -DcValue 5
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PROCTHROTTLEMAX'    -AcValue 100 -DcValue 100
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFEPP'            -AcValue 25  -DcValue 40
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFBOOSTMODE'      -AcValue 1   -DcValue 1
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'CPMINCORES'         -AcValue 50  -DcValue 25
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFAUTONOMOUSMODE' -AcValue 1   -DcValue 1
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'SYSCOOLPOL'         -AcValue 1   -DcValue 1
'CPU Lynext Lite aplicado.'
"@
}

function Get-CPUThermalCode {
@"
function Set-PowerValueSafe {
    param([string]`$Subgroup,[string]`$Setting,[int]`$AcValue,[int]`$DcValue)
    try { powercfg /setacvalueindex scheme_current `$Subgroup `$Setting `$AcValue | Out-Null } catch {}
    try { powercfg /setdcvalueindex scheme_current `$Subgroup `$Setting `$DcValue | Out-Null } catch {}
    try { powercfg /setactive scheme_current | Out-Null } catch {}
}
powercfg /setactive SCHEME_BALANCED | Out-Null
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PROCTHROTTLEMIN'    -AcValue 5  -DcValue 5
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PROCTHROTTLEMAX'    -AcValue 99 -DcValue 99
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFEPP'            -AcValue 60 -DcValue 80
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFBOOSTMODE'      -AcValue 0  -DcValue 0
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'CPMINCORES'         -AcValue 25 -DcValue 10
Set-PowerValueSafe -Subgroup 'sub_processor' -Setting 'PERFAUTONOMOUSMODE' -AcValue 1  -DcValue 1
'Modo termico / quieto aplicado.'
"@
}

function Get-WindowsUltraCode {
@"
function Set-RegDword {
    param([string]`$Path,[string]`$Name,[UInt32]`$Value)
    if (-not (Test-Path `$Path)) { New-Item -Path `$Path -Force | Out-Null }
    New-ItemProperty -Path `$Path -Name `$Name -Value `$Value -PropertyType DWord -Force | Out-Null
}
Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1
Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1
Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 0xffffffff
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 10
Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value 1
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'GPU Priority' -Value 8
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Priority' -Value 6
'Windows Ultra aplicado.'
'Reinicio recomendado para HAGS.'
"@
}

function Get-WindowsLiteCode {
@"
function Set-RegDword {
    param([string]`$Path,[string]`$Name,[UInt32]`$Value)
    if (-not (Test-Path `$Path)) { New-Item -Path `$Path -Force | Out-Null }
    New-ItemProperty -Path `$Path -Name `$Name -Value `$Value -PropertyType DWord -Force | Out-Null
}
Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1
Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1
Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 10
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 20
Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value 1
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'GPU Priority' -Value 8
Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Priority' -Value 6
'Windows Lite aplicado.'
'Reinicio recomendado para HAGS.'
"@
}

function Get-WindowsResetCode {
@"
function Set-RegDword {
    param([string]`$Path,[string]`$Name,[UInt32]`$Value)
    if (-not (Test-Path `$Path)) { New-Item -Path `$Path -Force | Out-Null }
    New-ItemProperty -Path `$Path -Name `$Name -Value `$Value -PropertyType DWord -Force | Out-Null
}
function Remove-RegValue {
    param([string]`$Path,[string]`$Name)
    try {
        if (Test-Path `$Path) { Remove-ItemProperty -Path `$Path -Name `$Name -Force -ErrorAction SilentlyContinue }
    }
    catch {}
}
`$backup = Get-Content -Path '$($script:BackupFile)' -Raw | ConvertFrom-Json
if (-not `$backup) { throw 'Backup nao encontrado.' }
if (`$backup.PowerSchemeGuid) { try { powercfg /setactive `$backup.PowerSchemeGuid | Out-Null } catch {} }
if (`$null -ne `$backup.Registry.AutoGameModeEnabled) { Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value ([UInt32]`$backup.Registry.AutoGameModeEnabled) }
if (`$null -ne `$backup.Registry.AllowAutoGameMode) { Set-RegDword -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value ([UInt32]`$backup.Registry.AllowAutoGameMode) }
if (`$null -ne `$backup.Registry.AppCaptureEnabled) { Set-RegDword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value ([UInt32]`$backup.Registry.AppCaptureEnabled) }
if (`$null -ne `$backup.Registry.GameDVR_Enabled) { Set-RegDword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value ([UInt32]`$backup.Registry.GameDVR_Enabled) }
if (`$null -ne `$backup.Registry.HwSchMode) { Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value ([UInt32]`$backup.Registry.HwSchMode) }
if (`$null -ne `$backup.Registry.SystemResponsiveness) { Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value ([UInt32]`$backup.Registry.SystemResponsiveness) }
if (`$null -ne `$backup.Registry.PowerThrottlingOff) { Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Name 'PowerThrottlingOff' -Value ([UInt32]`$backup.Registry.PowerThrottlingOff) }
if (`$null -ne `$backup.Registry.NetworkThrottlingIndex) {
    try {
        `$v = [UInt32]`$backup.Registry.NetworkThrottlingIndex
        Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value `$v
    }
    catch {
        Remove-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex'
    }
}
'Windows restaurado pelo backup.'
"@
}

function Get-NvidiaUltraCode {
@"
function Get-NvidiaSmiPath {
    `$path1 = Join-Path `$env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path `$path1) { return `$path1 }
    `$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (`$pf86) {
        `$path2 = Join-Path `$pf86 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path `$path2) { return `$path2 }
    }
    return `$null
}
`$nvidiaSmi = Get-NvidiaSmiPath
if (-not `$nvidiaSmi) {
    'nvidia-smi nao encontrado. Aplicacao automatica limitada.'
    exit 0
}
try {
    `$limits = & `$nvidiaSmi --query-gpu=power.min_limit,power.max_limit,power.default_limit --format=csv,noheader,nounits 2>`$null
    if (`$limits) {
        `$parts = (`$limits | Select-Object -First 1).ToString().Split(',') | ForEach-Object { `$_.Trim() }
        if (`$parts.Count -ge 2) {
            `$max = [double]`$parts[1]
            & `$nvidiaSmi -pl `$max | Out-Null
            "Power limit ajustado para `$max W"
        }
    }
}
catch {
    'Nao consegui aplicar power limit automatico.'
}
'Politica sugerida no Painel NVIDIA:'
'- Prefer maximum performance'
'- Low Latency Ultra somente se nao houver Reflex'
'- Texture filtering: High performance'
"@
}

function Get-NvidiaLiteCode {
@"
function Get-NvidiaSmiPath {
    `$path1 = Join-Path `$env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path `$path1) { return `$path1 }
    `$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (`$pf86) {
        `$path2 = Join-Path `$pf86 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path `$path2) { return `$path2 }
    }
    return `$null
}
`$backup = Get-Content -Path '$($script:BackupFile)' -Raw | ConvertFrom-Json
`$nvidiaSmi = Get-NvidiaSmiPath
if (`$nvidiaSmi -and `$backup -and `$backup.Nvidia.DefaultPowerLimit) {
    try {
        & `$nvidiaSmi -pl ([double]`$backup.Nvidia.DefaultPowerLimit) | Out-Null
        "Power limit restaurado para o valor padrao salvo: `$([double]`$backup.Nvidia.DefaultPowerLimit) W"
    }
    catch {
        'Nao consegui restaurar power limit salvo.'
    }
}
else {
    'Sem power limit padrao salvo ou nvidia-smi indisponivel.'
}
'Politica sugerida no Painel NVIDIA:'
'- Optimal / driver controlled'
'- Low Latency ON'
'- Sem forcar clocks agressivos'
"@
}

function Get-NvidiaResetCode {
@"
function Get-NvidiaSmiPath {
    `$path1 = Join-Path `$env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path `$path1) { return `$path1 }
    `$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (`$pf86) {
        `$path2 = Join-Path `$pf86 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path `$path2) { return `$path2 }
    }
    return `$null
}
`$backup = Get-Content -Path '$($script:BackupFile)' -Raw | ConvertFrom-Json
`$nvidiaSmi = Get-NvidiaSmiPath
if (-not `$nvidiaSmi) {
    'nvidia-smi nao encontrado.'
    exit 0
}
try { & `$nvidiaSmi -rgc | Out-Null; 'Clocks resetados.' } catch { 'Sua GPU pode nao suportar reset de clocks por nvidia-smi.' }
if (`$backup -and `$backup.Nvidia.DefaultPowerLimit) {
    try {
        & `$nvidiaSmi -pl ([double]`$backup.Nvidia.DefaultPowerLimit) | Out-Null
        "Power limit restaurado para `$([double]`$backup.Nvidia.DefaultPowerLimit) W"
    }
    catch {
        'Nao consegui restaurar power limit salvo.'
    }
}
else {
    'Power limit padrao nao encontrado no backup.'
}
"@
}

function Get-SummaryCode {
@"
function Get-ActivePowerSchemeGuid {
    `$line = powercfg /getactivescheme
    if (`$line -match '([a-fA-F0-9-]{36})') { return `$Matches[1] }
    return `$null
}
function Test-ModernStandby {
    try {
        `$out = powercfg /a | Out-String
        if (`$out -match "Standby \(S0 Low Power Idle\)") { return `$true }
    }
    catch {}
    return `$false
}
function Get-GpuVendor {
    try {
        `$gpuNames = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
        `$all = (`$gpuNames -join " | ")
        if (`$all -match "NVIDIA") { return "NVIDIA" }
        if (`$all -match "AMD|Radeon") { return "AMD" }
        if (`$all -match "Intel") { return "Intel" }
    }
    catch {}
    return "Unknown"
}
function Get-IsLaptop {
    try {
        `$cs = Get-CimInstance Win32_ComputerSystem
        if (`$cs.PCSystemType -in 2,3,4,8,9,10,14) { return `$true }
    }
    catch {}
    return `$false
}
`$os = Get-CimInstance Win32_OperatingSystem
`$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
`$gpus = Get-CimInstance Win32_VideoController
'Windows: ' + `$os.Caption + ' build ' + `$os.BuildNumber
'CPU: ' + `$cpu.Name
'GPU vendor: ' + (Get-GpuVendor)
'Notebook: ' + (Get-IsLaptop)
'Modern Standby: ' + (Test-ModernStandby)
'Plano ativo: ' + (Get-ActivePowerSchemeGuid)
''
'GPUs detectadas:'
foreach (`$gpu in `$gpus) {
    ' - ' + `$gpu.Name + ' | Driver: ' + `$gpu.DriverVersion
}
"@
}

# =========================================================
# FORM BASE
# =========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Lynext - Performance App'
$form.Size = New-Object System.Drawing.Size(1280,820)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bgMain
$form.ForeColor = $txtMain
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

# =========================================================
# HEADER
# =========================================================
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0,0)
$header.Size = New-Object System.Drawing.Size(1280,96)
$header.BackColor = $bgHeader

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Central de Performance'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI',22,[System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $txtMain
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(455,18)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'Energia, Windows, GPU e perfis organizados'
$lblSub.Font = New-Object System.Drawing.Font('Segoe UI',10)
$lblSub.ForeColor = $txtSoft
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(486,56)

$headerLine = New-Object System.Windows.Forms.Panel
$headerLine.Location = New-Object System.Drawing.Point(0,95)
$headerLine.Size = New-Object System.Drawing.Size(1280,1)
$headerLine.BackColor = $borderColor

$header.Controls.AddRange(@($lblTitle,$lblSub,$headerLine))

# =========================================================
# SIDEBAR
# =========================================================
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = New-Object System.Drawing.Point(18,114)
$sidebar.Size = New-Object System.Drawing.Size(236,642)
$sidebar.BackColor = $bgSidebar
$sidebar.BorderStyle = 'FixedSingle'

$navTitle = New-Object System.Windows.Forms.Label
$navTitle.Text = 'Categorias'
$navTitle.Location = New-Object System.Drawing.Point(14,14)
$navTitle.AutoSize = $true
$navTitle.Font = New-Object System.Drawing.Font('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
$navTitle.ForeColor = $txtMain

$navSub = New-Object System.Windows.Forms.Label
$navSub.Text = 'Deixei separado igual voce queria, pra nao misturar tudo.'
$navSub.Location = New-Object System.Drawing.Point(14,38)
$navSub.Size = New-Object System.Drawing.Size(195,38)
$navSub.Font = New-Object System.Drawing.Font('Segoe UI',8)
$navSub.ForeColor = $txtSoft

$btnNavOverview = New-SidebarButton 'overview' 'Visao Geral' 90
$btnNavModes    = New-SidebarButton 'modes' 'Modos Prontos' 138
$btnNavCpu      = New-SidebarButton 'cpu' 'CPU / Energia' 186
$btnNavWindows  = New-SidebarButton 'windows' 'Windows / Jogos' 234
$btnNavNvidia   = New-SidebarButton 'nvidia' 'NVIDIA' 282
$btnNavOther    = New-SidebarButton 'other' 'AMD / Intel' 330
$btnNavBackup   = New-SidebarButton 'backup' 'Backup / Reset' 378

$sidebar.Controls.AddRange(@(
    $navTitle,$navSub,
    $btnNavOverview,$btnNavModes,$btnNavCpu,$btnNavWindows,$btnNavNvidia,$btnNavOther,$btnNavBackup
))

$script:sidebarButtons = @($btnNavOverview,$btnNavModes,$btnNavCpu,$btnNavWindows,$btnNavNvidia,$btnNavOther,$btnNavBackup)

# =========================================================
# CONTENT AREA
# =========================================================
$content = New-Object System.Windows.Forms.Panel
$content.Location = New-Object System.Drawing.Point(268,114)
$content.Size = New-Object System.Drawing.Size(610,642)
$content.BackColor = $bgMain

function New-SectionPanel {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(0,0)
    $p.Size = New-Object System.Drawing.Size(610,642)
    $p.BackColor = $bgMain
    $p.Visible = $false
    return $p
}

# =========================================================
# OVERVIEW
# =========================================================
$panelOverview = New-SectionPanel

$ovCardTop = New-CardPanel 0 0 610 190
Add-SectionLabel $ovCardTop 'Resumo rapido' 18 14 13
Add-SoftLabel $ovCardTop 'Tela inicial mais limpa, inspirada no teu app de downloads e sem aquela cara de menu cru.' 18 42 560 34

Add-SoftLabel $ovCardTop 'GPU detectada' 18 86 140 20 | Out-Null
$lblDetectedGpu = New-InfoValueLabel $ovCardTop (Get-GpuVendor) 18 108 140
Add-SoftLabel $ovCardTop 'Notebook' 180 86 120 20 | Out-Null
$lblIsLaptop = New-InfoValueLabel $ovCardTop ((Get-IsLaptop).ToString()) 180 108 120
Add-SoftLabel $ovCardTop 'Modern Standby' 320 86 130 20 | Out-Null
$lblModern = New-InfoValueLabel $ovCardTop ((Test-ModernStandby).ToString()) 320 108 130
Add-SoftLabel $ovCardTop 'Plano atual' 460 86 120 20 | Out-Null
$lblPlan = New-InfoValueLabel $ovCardTop (Get-ActivePowerSchemeGuid) 460 108 130
$lblPlan.Font = New-Object System.Drawing.Font('Segoe UI',8,[System.Drawing.FontStyle]::Bold)

$ovCardQuick = New-CardPanel 0 206 610 204
Add-SectionLabel $ovCardQuick 'Acoes rapidas' 18 14 13
Add-SoftLabel $ovCardQuick 'Aqui fica o que voce mais usa sem entrar nas categorias.' 18 42 520 24

$btnQuickUltra = New-LynextButton 'Ultra Performance' 18 82 180 42
$btnQuickLite  = New-LynextButton 'Modo Lite' 208 82 180 42
$btnQuickInfo  = New-LynextButton 'Resumo do Sistema' 398 82 180 42
$btnQuickReset = New-LynextButton 'Reset Geral' 18 132 180 42
$btnQuickBackup = New-LynextButton 'Criar Backup' 208 132 180 42
$btnQuickLogs = New-LynextButton 'Abrir Logs' 398 132 180 42
$ovCardQuick.Controls.AddRange(@($btnQuickUltra,$btnQuickLite,$btnQuickInfo,$btnQuickReset,$btnQuickBackup,$btnQuickLogs))

$ovCardTips = New-CardPanel 0 426 610 180
Add-SectionLabel $ovCardTips 'Notas' 18 14 13
Add-SoftLabel $ovCardTips 'Ultra: mais agressivo.' 18 50 240 20 | Out-Null
Add-SoftLabel $ovCardTips 'Lite: mais equilibrado.' 18 76 240 20 | Out-Null
Add-SoftLabel $ovCardTips 'Backup: sempre recomendado antes de brincar nos perfis.' 18 102 360 20 | Out-Null
Add-SoftLabel $ovCardTips 'NVIDIA tem mais automacao por enquanto. AMD e Intel ficaram mais conservadores.' 18 128 520 34 | Out-Null

$panelOverview.Controls.AddRange(@($ovCardTop,$ovCardQuick,$ovCardTips))

# =========================================================
# MODES
# =========================================================
$panelModes = New-SectionPanel

$modesTop = New-CardPanel 0 0 610 210
Add-SectionLabel $modesTop 'Modos prontos' 18 14 13
Add-SoftLabel $modesTop 'Esses presets juntam CPU, Windows e GPU numa tacada so.' 18 42 520 24

$btnUltra = New-LynextButton 'LYNEXT ULTRA PERFORMANCE' 18 84 270 48
$btnLite  = New-LynextButton 'LYNEXT LITE' 304 84 270 48
$btnReset = New-LynextButton 'RESET GERAL' 18 142 180 40
$btnInfo  = New-LynextButton 'RESUMO DO SISTEMA' 208 142 180 40
$btnBackupCreate = New-LynextButton 'CRIAR BACKUP' 398 142 176 40
$modesTop.Controls.AddRange(@($btnUltra,$btnLite,$btnReset,$btnInfo,$btnBackupCreate))

$modesDesc = New-CardPanel 0 226 610 188
Add-SectionLabel $modesDesc 'O que cada modo faz' 18 14 13
Add-SoftLabel $modesDesc 'Ultra:' 18 50 70 20 | Out-Null
Add-SoftLabel $modesDesc 'prioriza desempenho, usa ajustes mais agressivos de energia e Windows.' 82 50 490 20 | Out-Null
Add-SoftLabel $modesDesc 'Lite:' 18 80 70 20 | Out-Null
Add-SoftLabel $modesDesc 'tenta manter desempenho com menos calor, consumo e stress.' 82 80 490 20 | Out-Null
Add-SoftLabel $modesDesc 'Reset:' 18 110 70 20 | Out-Null
Add-SoftLabel $modesDesc 'restaura usando o backup salvo na pasta do Lynext.' 82 110 490 20 | Out-Null

$panelModes.Controls.AddRange(@($modesTop,$modesDesc))

# =========================================================
# CPU
# =========================================================
$panelCpu = New-SectionPanel

$cpuCard = New-CardPanel 0 0 610 240
Add-SectionLabel $cpuCard 'CPU / Energia' 18 14 13
Add-SoftLabel $cpuCard 'Separado do resto pra nao misturar rede, windows e energia tudo no mesmo lugar.' 18 42 560 24

$btnCpuUltra   = New-LynextButton 'CPU ULTRA' 18 88 180 42
$btnCpuLite    = New-LynextButton 'CPU LITE' 208 88 180 42
$btnCpuThermal = New-LynextButton 'TERMICO / QUIETO' 398 88 176 42
$cpuCard.Controls.AddRange(@($btnCpuUltra,$btnCpuLite,$btnCpuThermal))

Add-SoftLabel $cpuCard 'Ultra: clocks e boost mais agressivos.' 18 150 400 20 | Out-Null
Add-SoftLabel $cpuCard 'Lite: equilibrio entre resposta e consumo.' 18 176 400 20 | Out-Null
Add-SoftLabel $cpuCard 'Termico: reduz agressividade pra segurar temperatura e ruido.' 18 202 480 20 | Out-Null

$panelCpu.Controls.Add($cpuCard)

# =========================================================
# WINDOWS
# =========================================================
$panelWindows = New-SectionPanel

$winCard = New-CardPanel 0 0 610 240
Add-SectionLabel $winCard 'Windows / Jogos' 18 14 13
Add-SoftLabel $winCard 'Aqui fica HAGS, DVR, Game Mode e os ajustes mais leves de latencia.' 18 42 560 24

$btnWinUltra = New-LynextButton 'WINDOWS ULTRA' 18 88 180 42
$btnWinLite  = New-LynextButton 'WINDOWS LITE' 208 88 180 42
$btnWinReset = New-LynextButton 'RESET WINDOWS' 398 88 176 42
$winCard.Controls.AddRange(@($btnWinUltra,$btnWinLite,$btnWinReset))

Add-SoftLabel $winCard 'Esses ajustes mexem em Game DVR, HAGS e prioridades de multimedia.' 18 150 520 20 | Out-Null
Add-SoftLabel $winCard 'Reinicio pode ser necessario dependendo do que for alterado.' 18 176 520 20 | Out-Null

$panelWindows.Controls.Add($winCard)

# =========================================================
# NVIDIA
# =========================================================
$panelNvidia = New-SectionPanel

$nvCard = New-CardPanel 0 0 610 300
Add-SectionLabel $nvCard 'NVIDIA' 18 14 13
Add-SoftLabel $nvCard 'Essa area ficou propria pra GPU, sem embolar com os outros menus.' 18 42 540 24

$btnNvInfo  = New-LynextButton 'SUPORTE / ESTADO' 18 88 180 42
$btnNvUltra = New-LynextButton 'NVIDIA ULTRA' 208 88 180 42
$btnNvLite  = New-LynextButton 'NVIDIA LITE' 398 88 176 42
$btnNvReset = New-LynextButton 'RESET NVIDIA' 18 142 180 42
$btnNvPower = New-LynextButton 'POWER LIMIT MANUAL' 208 142 180 42
$nvCard.Controls.AddRange(@($btnNvInfo,$btnNvUltra,$btnNvLite,$btnNvReset,$btnNvPower))

Add-SoftLabel $nvCard 'Automacao depende do nvidia-smi estar disponivel no driver.' 18 208 520 20 | Out-Null
Add-SoftLabel $nvCard 'Se nao houver suporte, ele informa e segue de forma conservadora.' 18 234 540 20 | Out-Null

$panelNvidia.Controls.Add($nvCard)

# =========================================================
# OTHER
# =========================================================
$panelOther = New-SectionPanel

$otherCard = New-CardPanel 0 0 610 240
Add-SectionLabel $otherCard 'AMD / Intel' 18 14 13
Add-SoftLabel $otherCard 'Deixei essa parte mais informativa por enquanto, sem tuning automatico pesado.' 18 42 560 24

$btnAmdInfo   = New-LynextButton 'AMD INFO' 18 88 180 42
$btnIntelInfo = New-LynextButton 'INTEL INFO' 208 88 180 42
$btnPolicy    = New-LynextButton 'GUIA RAPIDO' 398 88 176 42
$otherCard.Controls.AddRange(@($btnAmdInfo,$btnIntelInfo,$btnPolicy))

Add-SoftLabel $otherCard 'Isso evita quebrar compatibilidade em hardware que varia muito de driver pra driver.' 18 150 550 24 | Out-Null

$panelOther.Controls.Add($otherCard)

# =========================================================
# BACKUP
# =========================================================
$panelBackup = New-SectionPanel

$backupCard = New-CardPanel 0 0 610 240
Add-SectionLabel $backupCard 'Backup / Reset' 18 14 13
Add-SoftLabel $backupCard 'A parte de seguranca ficou separada, porque ela merece area propria.' 18 42 540 24

$btnOpenFolder = New-LynextButton 'ABRIR PASTA LYNEXT' 18 88 180 42
$btnOpenLogs   = New-LynextButton 'ABRIR LOGS' 208 88 180 42
$btnBackupRefresh = New-LynextButton 'ATUALIZAR BACKUP' 398 88 176 42
$backupCard.Controls.AddRange(@($btnOpenFolder,$btnOpenLogs,$btnBackupRefresh))

Add-SoftLabel $backupCard 'Backup salvo em ProgramData\Lynext.' 18 150 300 20 | Out-Null
Add-SoftLabel $backupCard 'Logs separados em pasta propria pra facilitar debug.' 18 176 300 20 | Out-Null

$panelBackup.Controls.Add($backupCard)

$content.Controls.AddRange(@($panelOverview,$panelModes,$panelCpu,$panelWindows,$panelNvidia,$panelOther,$panelBackup))
$script:SectionPanels['overview'] = $panelOverview
$script:SectionPanels['modes']    = $panelModes
$script:SectionPanels['cpu']      = $panelCpu
$script:SectionPanels['windows']  = $panelWindows
$script:SectionPanels['nvidia']   = $panelNvidia
$script:SectionPanels['other']    = $panelOther
$script:SectionPanels['backup']   = $panelBackup

# =========================================================
# OUTPUT AREA
# =========================================================
$outputWrap = New-Object System.Windows.Forms.Panel
$outputWrap.Location = New-Object System.Drawing.Point(894,114)
$outputWrap.Size = New-Object System.Drawing.Size(352,642)
$outputWrap.BackColor = $bgCard
$outputWrap.BorderStyle = 'FixedSingle'

$outTitle = New-Object System.Windows.Forms.Label
$outTitle.Text = 'Painel de Saida'
$outTitle.Location = New-Object System.Drawing.Point(16,14)
$outTitle.AutoSize = $true
$outTitle.Font = New-Object System.Drawing.Font('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$outTitle.ForeColor = $txtMain

$outSub = New-Object System.Windows.Forms.Label
$outSub.Text = 'Aqui voce acompanha o que o app executou.'
$outSub.Location = New-Object System.Drawing.Point(16,40)
$outSub.Size = New-Object System.Drawing.Size(300,22)
$outSub.Font = New-Object System.Drawing.Font('Segoe UI',8)
$outSub.ForeColor = $txtSoft

$script:txtOutput = New-Object System.Windows.Forms.TextBox
$script:txtOutput.Location = New-Object System.Drawing.Point(16,72)
$script:txtOutput.Size = New-Object System.Drawing.Size(316,518)
$script:txtOutput.Multiline = $true
$script:txtOutput.ScrollBars = 'Vertical'
$script:txtOutput.ReadOnly = $true
$script:txtOutput.BackColor = $bgEditor
$script:txtOutput.ForeColor = $txtMain
$script:txtOutput.BorderStyle = 'FixedSingle'
$script:txtOutput.Font = New-Object System.Drawing.Font('Consolas',9)

$btnClearOutput = New-LynextButton 'Limpar painel' 16 602 150 28
$btnCopyLogPath = New-LynextButton 'Mostrar log' 182 602 150 28

$outputWrap.Controls.AddRange(@($outTitle,$outSub,$script:txtOutput,$btnClearOutput,$btnCopyLogPath))

# =========================================================
# FOOTER
# =========================================================
$footer = New-Object System.Windows.Forms.Panel
$footer.Location = New-Object System.Drawing.Point(0,767)
$footer.Size = New-Object System.Drawing.Size(1280,30)
$footer.BackColor = $bgHeader

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = 'Status: Pronto'
$script:lblStatus.Location = New-Object System.Drawing.Point(18,6)
$script:lblStatus.AutoSize = $true
$script:lblStatus.Font = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
$script:lblStatus.ForeColor = $okColor

$script:prg = New-Object System.Windows.Forms.ProgressBar
$script:prg.Location = New-Object System.Drawing.Point(190,7)
$script:prg.Size = New-Object System.Drawing.Size(220,12)
$script:prg.Style = 'Blocks'

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log: $script:LogFile"
$lblLog.Location = New-Object System.Drawing.Point(430,6)
$lblLog.Size = New-Object System.Drawing.Size(820,18)
$lblLog.Font = New-Object System.Drawing.Font('Segoe UI',8)
$lblLog.ForeColor = $txtMuted

$footer.Controls.AddRange(@($script:lblStatus,$script:prg,$lblLog))

# =========================================================
# TOOLTIPS
# =========================================================
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 8000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 150
$toolTip.ShowAlways = $true

$toolTip.SetToolTip($btnUltra, 'Aplica CPU Ultra + Windows Ultra + NVIDIA Ultra quando suportado.')
$toolTip.SetToolTip($btnLite, 'Aplica CPU Lite + Windows Lite + NVIDIA Lite quando suportado.')
$toolTip.SetToolTip($btnReset, 'Restaura os ajustes pelo backup salvo.')
$toolTip.SetToolTip($btnInfo, 'Mostra um resumo tecnico do sistema.')
$toolTip.SetToolTip($btnCpuUltra, 'Modo agressivo de energia e boost.')
$toolTip.SetToolTip($btnCpuLite, 'Modo equilibrado.')
$toolTip.SetToolTip($btnCpuThermal, 'Foco em temperatura e ruido.')
$toolTip.SetToolTip($btnWinUltra, 'Game Mode ON, DVR OFF, HAGS ON.')
$toolTip.SetToolTip($btnWinLite, 'Ajuste mais leve de Windows/Jogos.')
$toolTip.SetToolTip($btnWinReset, 'Restaura os principais ajustes de Windows.')
$toolTip.SetToolTip($btnNvInfo, 'Mostra estado da GPU via nvidia-smi.')
$toolTip.SetToolTip($btnNvUltra, 'Modo NVIDIA mais agressivo.')
$toolTip.SetToolTip($btnNvLite, 'Restaura limite salvo e aplica politica mais leve.')
$toolTip.SetToolTip($btnNvReset, 'Reseta clocks e power limit salvo.')
$toolTip.SetToolTip($btnNvPower, 'Permite definir o power limit manualmente.')

# =========================================================
# NAV EVENTS
# =========================================================
$btnNavOverview.Add_Click({ Show-Section 'overview' })
$btnNavModes.Add_Click({ Show-Section 'modes' })
$btnNavCpu.Add_Click({ Show-Section 'cpu' })
$btnNavWindows.Add_Click({ Show-Section 'windows' })
$btnNavNvidia.Add_Click({ Show-Section 'nvidia' })
$btnNavOther.Add_Click({ Show-Section 'other' })
$btnNavBackup.Add_Click({ Show-Section 'backup' })

# =========================================================
# ACTIONS
# =========================================================
$btnBackupCreate.Add_Click({
    Start-LynextTask -Name 'Criar / Atualizar Backup' -Code (Get-BackupCode)
})
$btnBackupRefresh.Add_Click({
    Start-LynextTask -Name 'Criar / Atualizar Backup' -Code (Get-BackupCode)
})
$btnQuickBackup.Add_Click({
    Start-LynextTask -Name 'Criar / Atualizar Backup' -Code (Get-BackupCode)
})

$btnInfo.Add_Click({
    Start-LynextTask -Name 'Resumo do Sistema' -Code (Get-SummaryCode)
})
$btnQuickInfo.Add_Click({
    Start-LynextTask -Name 'Resumo do Sistema' -Code (Get-SummaryCode)
})

$btnCpuUltra.Add_Click({ Start-LynextTask -Name 'CPU Ultra' -Code (Get-CPUUltraCode) })
$btnCpuLite.Add_Click({ Start-LynextTask -Name 'CPU Lite' -Code (Get-CPULiteCode) })
$btnCpuThermal.Add_Click({ Start-LynextTask -Name 'CPU Termico / Quieto' -Code (Get-CPUThermalCode) })

$btnWinUltra.Add_Click({ Start-LynextTask -Name 'Windows Ultra' -Code (Get-WindowsUltraCode) })
$btnWinLite.Add_Click({ Start-LynextTask -Name 'Windows Lite' -Code (Get-WindowsLiteCode) })
$btnWinReset.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show('Backup nao encontrado.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }
    Start-LynextTask -Name 'Reset Windows pelo Backup' -Code (Get-WindowsResetCode)
})

$btnUltra.Add_Click({
    if (-not (Ensure-BackupExists)) { return }

    $code = @"
$(Get-CPUUltraCode)
'---'
$(Get-WindowsUltraCode)
'---'
if ((Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join ' | ' -match 'NVIDIA') {
$(Get-NvidiaUltraCode)
}
else {
'GPU nao NVIDIA detectada. Parte automatica de GPU mantida conservadora.'
}
'---'
'Lynext Ultra Performance concluido.'
"@
    Start-LynextTask -Name 'Lynext Ultra Performance' -Code $code -Confirm -ConfirmMessage 'O modo Ultra e mais agressivo. Deseja continuar?'
})
$btnQuickUltra.Add_Click({ $btnUltra.PerformClick() })

$btnLite.Add_Click({
    if (-not (Ensure-BackupExists)) { return }

    $code = @"
$(Get-CPULiteCode)
'---'
$(Get-WindowsLiteCode)
'---'
if ((Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join ' | ' -match 'NVIDIA') {
$(Get-NvidiaLiteCode)
}
else {
'GPU nao NVIDIA detectada. Parte automatica de GPU mantida conservadora.'
}
'---'
'Lynext Lite concluido.'
"@
    Start-LynextTask -Name 'Lynext Lite' -Code $code
})
$btnQuickLite.Add_Click({ $btnLite.PerformClick() })

$btnReset.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show('Backup nao encontrado.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }

    $code = @"
$(Get-WindowsResetCode)
'---'
$(Get-NvidiaResetCode)
'---'
'Reset geral concluido.'
"@
    Start-LynextTask -Name 'Reset Geral' -Code $code -Confirm -ConfirmMessage 'Deseja restaurar os ajustes pelo backup?'
})
$btnQuickReset.Add_Click({ $btnReset.PerformClick() })

$btnNvInfo.Add_Click({
    $code = @"
function Get-NvidiaSmiPath {
    `$path1 = Join-Path `$env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path `$path1) { return `$path1 }
    `$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (`$pf86) {
        `$path2 = Join-Path `$pf86 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path `$path2) { return `$path2 }
    }
    return `$null
}
`$gpuNames = Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name
if ((`$gpuNames -join ' | ') -notmatch 'NVIDIA') {
    'GPU NVIDIA nao detectada.'
    exit 0
}
`$nvidiaSmi = Get-NvidiaSmiPath
if (-not `$nvidiaSmi) {
    'nvidia-smi nao encontrado.'
    exit 0
}
& `$nvidiaSmi -q -d POWER,CLOCK
"@
    Start-LynextTask -Name 'NVIDIA Suporte / Estado' -Code $code
})

$btnNvUltra.Add_Click({ Start-LynextTask -Name 'NVIDIA Ultra' -Code (Get-NvidiaUltraCode) })
$btnNvLite.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show('Crie um backup antes.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }
    Start-LynextTask -Name 'NVIDIA Lite' -Code (Get-NvidiaLiteCode)
})
$btnNvReset.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show('Backup nao encontrado.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }
    Start-LynextTask -Name 'NVIDIA Reset' -Code (Get-NvidiaResetCode)
})
$btnNvPower.Add_Click({
    $watts = Show-InputDialog -Title 'Power Limit NVIDIA' -Label 'Valor em Watts:' -DefaultValue '200'
    if ([string]::IsNullOrWhiteSpace($watts)) { return }

    if ($watts -notmatch '^\d+(\.\d+)?$') {
        [System.Windows.Forms.MessageBox]::Show('Valor invalido.', 'Lynext', 'OK', 'Error') | Out-Null
        return
    }

    $w = Escape-SQ $watts
    $code = @"
function Get-NvidiaSmiPath {
    `$path1 = Join-Path `$env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path `$path1) { return `$path1 }
    `$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (`$pf86) {
        `$path2 = Join-Path `$pf86 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path `$path2) { return `$path2 }
    }
    return `$null
}
`$nvidiaSmi = Get-NvidiaSmiPath
if (-not `$nvidiaSmi) { throw 'nvidia-smi nao encontrado.' }
& `$nvidiaSmi -pl $w | Out-Null
'Power limit ajustado para $w W'
"@
    Start-LynextTask -Name 'NVIDIA Power Limit Manual' -Code $code
})

$btnAmdInfo.Add_Click({
    $code = @"
`$gpus = Get-CimInstance Win32_VideoController | Where-Object { `$_.Name -match 'AMD|Radeon' }
if (-not `$gpus) {
    'GPU AMD nao detectada.'
    exit 0
}
`$gpus | Select-Object Name, DriverVersion, VideoProcessor | Format-List
''
'Politica recomendada AMD:'
'- Anti-Lag ON'
'- Chill OFF'
'- Boost moderado'
'- Sharpening leve a moderado'
"@
    Start-LynextTask -Name 'AMD Info' -Code $code
})

$btnIntelInfo.Add_Click({
    $code = @"
`$gpus = Get-CimInstance Win32_VideoController | Where-Object { `$_.Name -match 'Intel' }
if (-not `$gpus) {
    'GPU Intel nao detectada.'
    exit 0
}
`$gpus | Select-Object Name, DriverVersion, VideoProcessor | Format-List
''
'Politica recomendada Intel:'
'- Driver atualizado'
'- Ajustes conservadores'
'- Foco maior em energia / estabilidade'
"@
    Start-LynextTask -Name 'Intel Info' -Code $code
})

$btnPolicy.Add_Click({
    $text = @"
GUIA RAPIDO AMD / INTEL

AMD:
- Anti-Lag ON
- Chill OFF
- Boost moderado
- Sharpening leve ou moderado
- Evitar exagero em tuning sem o Adrenalin

INTEL:
- Driver atualizado
- Sem agressividade desnecessaria
- Foco em estabilidade e plano de energia correto

OBS:
- O tuning automatico mais forte ficou focado em NVIDIA por enquanto.
"@
    Append-Output $text -Clear
    Set-Status 'Guia rapido exibido.' 'ok'
})

$btnOpenFolder.Add_Click({
    Start-Process explorer.exe $script:LynextRoot
    Set-Status 'Pasta Lynext aberta.' 'ok'
})
$btnOpenLogs.Add_Click({
    Start-Process explorer.exe $script:LogDir
    Set-Status 'Pasta de logs aberta.' 'ok'
})
$btnQuickLogs.Add_Click({ $btnOpenLogs.PerformClick() })

$btnClearOutput.Add_Click({
    $script:txtOutput.Clear()
    Set-Status 'Painel limpo.' 'ok'
})
$btnCopyLogPath.Add_Click({
    [System.Windows.Forms.MessageBox]::Show($script:LogFile, 'Log atual') | Out-Null
})

# =========================================================
# TIMER
# =========================================================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({ Poll-LynextTask })
$timer.Start()

# =========================================================
# MONTAGEM FINAL
# =========================================================
$form.Controls.AddRange(@($header,$sidebar,$content,$outputWrap,$footer))
Show-Section 'overview'

Append-Output 'Lynext Performance Center iniciado.'
Append-Output "Log: $script:LogFile"
Set-Status 'Pronto' 'ok'
Write-LogLine 'Lynext Performance Center iniciado'

[void]$form.ShowDialog()
