Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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

# =========================================================
# TEMA
# =========================================================
$bgMain      = [System.Drawing.Color]::FromArgb(8,12,10)
$bgPanel     = [System.Drawing.Color]::FromArgb(14,22,18)
$bgPanel2    = [System.Drawing.Color]::FromArgb(19,30,24)
$bgButton    = [System.Drawing.Color]::FromArgb(12,26,18)
$bgHover     = [System.Drawing.Color]::FromArgb(20,42,30)
$bgDown      = [System.Drawing.Color]::FromArgb(28,58,40)
$txtMain     = [System.Drawing.Color]::FromArgb(232,240,234)
$txtSoft     = [System.Drawing.Color]::FromArgb(145,170,150)
$accent      = [System.Drawing.Color]::FromArgb(66,170,110)
$accent2     = [System.Drawing.Color]::FromArgb(95,220,140)
$okColor     = [System.Drawing.Color]::FromArgb(90,220,140)
$warnColor   = [System.Drawing.Color]::FromArgb(255,200,90)
$errColor    = [System.Drawing.Color]::FromArgb(255,110,110)
$borderColor = [System.Drawing.Color]::FromArgb(46,92,66)

# =========================================================
# HELPERS
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

function Save-Json {
    param([string]$Path,[object]$Data)
    $Data | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Load-Json {
    param([string]$Path)
    if (Test-Path $Path) {
        try { return Get-Content $Path -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
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
        Backup-CurrentState
    }
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
# SCRIPTS / ACTIONS
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
# FORM
# =========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Lynext - Performance App"
$form.Size = New-Object System.Drawing.Size(1240,780)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgMain
$form.ForeColor = $txtMain
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Lynext"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",24,[System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $accent2
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(24,18)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Performance Center | energia, windows e gpu"
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

# Left container
$panelLeft = New-Object System.Windows.Forms.Panel
$panelLeft.Location = New-Object System.Drawing.Point(24,100)
$panelLeft.Size = New-Object System.Drawing.Size(600,610)
$panelLeft.BackColor = $bgPanel

# Output
$panelOutput = New-Object System.Windows.Forms.Panel
$panelOutput.Location = New-Object System.Drawing.Point(640,100)
$panelOutput.Size = New-Object System.Drawing.Size(560,610)
$panelOutput.BackColor = $bgPanel

$outTitle = New-Object System.Windows.Forms.Label
$outTitle.Text = "SAIDA"
$outTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$outTitle.ForeColor = $txtMain
$outTitle.AutoSize = $true
$outTitle.Location = New-Object System.Drawing.Point(14,10)

$script:txtOutput = New-Object System.Windows.Forms.TextBox
$script:txtOutput.Location = New-Object System.Drawing.Point(15,40)
$script:txtOutput.Size = New-Object System.Drawing.Size(530,550)
$script:txtOutput.Multiline = $true
$script:txtOutput.ScrollBars = "Vertical"
$script:txtOutput.ReadOnly = $true
$script:txtOutput.BackColor = $bgPanel2
$script:txtOutput.ForeColor = $txtMain
$script:txtOutput.BorderStyle = "FixedSingle"
$script:txtOutput.Font = New-Object System.Drawing.Font("Consolas",9)

$panelOutput.Controls.Add($outTitle)
$panelOutput.Controls.Add($script:txtOutput)

# Tabs
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12,14)
$tabs.Size = New-Object System.Drawing.Size(575,580)
$tabs.Font = New-Object System.Drawing.Font("Segoe UI",9)
$tabs.Appearance = 'Normal'
$tabs.Multiline = $false

function New-TabPage {
    param([string]$Title)
    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $Title
    $tab.BackColor = $bgPanel
    $tab.ForeColor = $txtMain
    return $tab
}

$tabModes   = New-TabPage "Modos"
$tabCPU     = New-TabPage "CPU / Energia"
$tabWin     = New-TabPage "Windows / Jogos"
$tabNvidia  = New-TabPage "NVIDIA"
$tabOther   = New-TabPage "AMD / Intel"
$tabBackup  = New-TabPage "Backup / Reset"

$tabs.TabPages.AddRange(@($tabModes,$tabCPU,$tabWin,$tabNvidia,$tabOther,$tabBackup))
$panelLeft.Controls.Add($tabs)

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

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 8000
$toolTip.InitialDelay = 250
$toolTip.ReshowDelay = 150
$toolTip.ShowAlways = $true

# =========================================================
# TAB MODOS
# =========================================================
Add-SectionLabel $tabModes "MODOS PRINCIPAIS" 18 16
Add-SoftLabel $tabModes "Use os presets prontos. Ultra e agressivo. Lite busca equilibrio." 18 42 520 32

$btnUltra = New-LynextButton "LYNEXT ULTRA PERFORMANCE" 18 90 250 50
$btnLite  = New-LynextButton "LYNEXT LITE" 285 90 250 50
$btnReset = New-LynextButton "RESET GERAL" 18 155 250 46
$btnInfo  = New-LynextButton "RESUMO DO SISTEMA" 285 155 250 46
$tabModes.Controls.AddRange(@($btnUltra,$btnLite,$btnReset,$btnInfo))

Add-SectionLabel $tabModes "DESCRICAO" 18 235
Add-SoftLabel $tabModes "Ultra: foco em desempenho maximo. Lite: desempenho com mais controle de consumo e temperatura." 18 262 520 52

# =========================================================
# TAB CPU
# =========================================================
Add-SectionLabel $tabCPU "CPU / ENERGIA" 18 16
Add-SoftLabel $tabCPU "Ajustes de plano de energia e comportamento do processador." 18 42 520 30

$btnCpuUltra   = New-LynextButton "CPU ULTRA" 18 90 170 42
$btnCpuLite    = New-LynextButton "CPU LITE" 198 90 170 42
$btnCpuThermal = New-LynextButton "TERMICO / QUIETO" 378 90 160 42
$tabCPU.Controls.AddRange(@($btnCpuUltra,$btnCpuLite,$btnCpuThermal))

# =========================================================
# TAB WINDOWS
# =========================================================
Add-SectionLabel $tabWin "WINDOWS / JOGOS" 18 16
Add-SoftLabel $tabWin "Game Mode, HAGS, Game DVR e ajustes leves de latencia." 18 42 520 30

$btnWinUltra = New-LynextButton "WINDOWS ULTRA" 18 90 170 42
$btnWinLite  = New-LynextButton "WINDOWS LITE" 198 90 170 42
$btnWinReset = New-LynextButton "RESET WINDOWS" 378 90 160 42
$tabWin.Controls.AddRange(@($btnWinUltra,$btnWinLite,$btnWinReset))

# =========================================================
# TAB NVIDIA
# =========================================================
Add-SectionLabel $tabNvidia "NVIDIA" 18 16
Add-SoftLabel $tabNvidia "Ajustes automaticos limitados ao que o driver / nvidia-smi suportam." 18 42 520 30

$btnNvInfo  = New-LynextButton "SUPORTE / ESTADO" 18 90 170 42
$btnNvUltra = New-LynextButton "NVIDIA ULTRA" 198 90 170 42
$btnNvLite  = New-LynextButton "NVIDIA LITE" 378 90 160 42
$btnNvReset = New-LynextButton "RESET NVIDIA" 18 145 170 42
$btnNvPower = New-LynextButton "POWER LIMIT MANUAL" 198 145 170 42
$tabNvidia.Controls.AddRange(@($btnNvInfo,$btnNvUltra,$btnNvLite,$btnNvReset,$btnNvPower))

# =========================================================
# TAB AMD / INTEL
# =========================================================
Add-SectionLabel $tabOther "AMD / INTEL" 18 16
Add-SoftLabel $tabOther "Por enquanto esta aba mostra informacoes e direcao de politica, sem tuning automatico pesado." 18 42 520 36

$btnAmdInfo   = New-LynextButton "AMD INFO" 18 95 170 42
$btnIntelInfo = New-LynextButton "INTEL INFO" 198 95 170 42
$btnPolicy    = New-LynextButton "GUIA RAPIDO" 378 95 160 42
$tabOther.Controls.AddRange(@($btnAmdInfo,$btnIntelInfo,$btnPolicy))

# =========================================================
# TAB BACKUP
# =========================================================
Add-SectionLabel $tabBackup "BACKUP / RESET" 18 16
Add-SoftLabel $tabBackup "Backup automatico dos principais ajustes antes dos modos prontos." 18 42 520 30

$btnBackupCreate = New-LynextButton "CRIAR / ATUALIZAR BACKUP" 18 90 250 46
$btnOpenFolder   = New-LynextButton "ABRIR PASTA LYNEXT" 285 90 250 46
$btnOpenLogs     = New-LynextButton "ABRIR LOGS" 18 150 250 42
$tabBackup.Controls.AddRange(@($btnBackupCreate,$btnOpenFolder,$btnOpenLogs))

# =========================================================
# TOOLTIPS
# =========================================================
$toolTip.SetToolTip($btnUltra, "Aplica CPU Ultra + Windows Ultra + NVIDIA Ultra quando suportado.")
$toolTip.SetToolTip($btnLite, "Aplica CPU Lite + Windows Lite + NVIDIA Lite quando suportado.")
$toolTip.SetToolTip($btnReset, "Restaura pelo backup salvo.")
$toolTip.SetToolTip($btnInfo, "Mostra resumo do sistema no painel de saida.")

$toolTip.SetToolTip($btnCpuUltra, "Modo agressivo de energia e boost.")
$toolTip.SetToolTip($btnCpuLite, "Modo equilibrado para desempenho com menos estresse.")
$toolTip.SetToolTip($btnCpuThermal, "Modo mais calmo, focado em temperatura e ruido.")

$toolTip.SetToolTip($btnWinUltra, "Game Mode ON, DVR OFF, HAGS ON e prioridades mais agressivas.")
$toolTip.SetToolTip($btnWinLite, "Game Mode ON, DVR OFF, HAGS ON e prioridades mais leves.")
$toolTip.SetToolTip($btnWinReset, "Restaura os principais ajustes de Windows pelo backup.")

$toolTip.SetToolTip($btnNvInfo, "Mostra informacoes do nvidia-smi, se houver.")
$toolTip.SetToolTip($btnNvUltra, "Aplica politica Ultra e tenta usar o limite maximo suportado.")
$toolTip.SetToolTip($btnNvLite, "Restaura power limit salvo e aplica politica Lite.")
$toolTip.SetToolTip($btnNvReset, "Reseta clocks e power limit salvo.")
$toolTip.SetToolTip($btnNvPower, "Define manualmente um power limit para GPU NVIDIA.")

$toolTip.SetToolTip($btnAmdInfo, "Mostra informacoes de GPU AMD detectada.")
$toolTip.SetToolTip($btnIntelInfo, "Mostra informacoes de GPU Intel detectada.")
$toolTip.SetToolTip($btnPolicy, "Abre um resumo de politicas recomendadas para AMD e Intel.")

$toolTip.SetToolTip($btnBackupCreate, "Salva o estado atual para reset futuro.")
$toolTip.SetToolTip($btnOpenFolder, "Abre a pasta ProgramData\Lynext.")
$toolTip.SetToolTip($btnOpenLogs, "Abre a pasta de logs.")

# =========================================================
# EVENTS
# =========================================================
$btnBackupCreate.Add_Click({
    Start-LynextTask -Name "Criar / Atualizar Backup" -Code (Get-BackupCode)
})

$btnInfo.Add_Click({
    Start-LynextTask -Name "Resumo do Sistema" -Code (Get-SummaryCode)
})

$btnCpuUltra.Add_Click({
    Start-LynextTask -Name "CPU Ultra" -Code (Get-CPUUltraCode)
})

$btnCpuLite.Add_Click({
    Start-LynextTask -Name "CPU Lite" -Code (Get-CPULiteCode)
})

$btnCpuThermal.Add_Click({
    Start-LynextTask -Name "CPU Termico / Quieto" -Code (Get-CPUThermalCode)
})

$btnWinUltra.Add_Click({
    Start-LynextTask -Name "Windows Ultra" -Code (Get-WindowsUltraCode)
})

$btnWinLite.Add_Click({
    Start-LynextTask -Name "Windows Lite" -Code (Get-WindowsLiteCode)
})

$btnWinReset.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show("Backup nao encontrado.", "Lynext", "OK", "Warning") | Out-Null
        return
    }
    Start-LynextTask -Name "Reset Windows pelo Backup" -Code (Get-WindowsResetCode)
})

$btnUltra.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        Start-LynextTask -Name "Criar Backup Inicial" -Code (Get-BackupCode)
        return
    }

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
    Start-LynextTask -Name "Lynext Ultra Performance" -Code $code -Confirm -ConfirmMessage "O modo Ultra e mais agressivo. Deseja continuar?"
})

$btnLite.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        Start-LynextTask -Name "Criar Backup Inicial" -Code (Get-BackupCode)
        return
    }

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
    Start-LynextTask -Name "Lynext Lite" -Code $code
})

$btnReset.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show("Backup nao encontrado.", "Lynext", "OK", "Warning") | Out-Null
        return
    }

    $code = @"
$(Get-WindowsResetCode)

'---'
$(Get-NvidiaResetCode)

'---'
'Reset geral concluido.'
"@
    Start-LynextTask -Name "Reset Geral" -Code $code -Confirm -ConfirmMessage "Deseja restaurar os ajustes pelo backup?"
})

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
    Start-LynextTask -Name "NVIDIA Suporte / Estado" -Code $code
})

$btnNvUltra.Add_Click({
    Start-LynextTask -Name "NVIDIA Ultra" -Code (Get-NvidiaUltraCode)
})

$btnNvLite.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show("Crie um backup antes.", "Lynext", "OK", "Warning") | Out-Null
        return
    }
    Start-LynextTask -Name "NVIDIA Lite" -Code (Get-NvidiaLiteCode)
})

$btnNvReset.Add_Click({
    if (-not (Test-Path $script:BackupFile)) {
        [System.Windows.Forms.MessageBox]::Show("Backup nao encontrado.", "Lynext", "OK", "Warning") | Out-Null
        return
    }
    Start-LynextTask -Name "NVIDIA Reset" -Code (Get-NvidiaResetCode)
})

$btnNvPower.Add_Click({
    $watts = Show-InputDialog -Title "Power Limit NVIDIA" -Label "Valor em Watts:" -DefaultValue "200"
    if ([string]::IsNullOrWhiteSpace($watts)) { return }

    if ($watts -notmatch '^\d+(\.\d+)?$') {
        [System.Windows.Forms.MessageBox]::Show("Valor invalido.", "Lynext", "OK", "Error") | Out-Null
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
    Start-LynextTask -Name "NVIDIA Power Limit Manual" -Code $code
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
    Start-LynextTask -Name "AMD Info" -Code $code
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
    Start-LynextTask -Name "Intel Info" -Code $code
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
    Set-Status "Guia rapido exibido." "ok"
})

$btnOpenFolder.Add_Click({
    Start-Process explorer.exe $script:LynextRoot
    Set-Status "Pasta Lynext aberta." "ok"
})

$btnOpenLogs.Add_Click({
    Start-Process explorer.exe $script:LogDir
    Set-Status "Pasta de logs aberta." "ok"
})

# =========================================================
# STATUS / FOOTER
# =========================================================
$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = "Status: Pronto"
$script:lblStatus.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$script:lblStatus.ForeColor = $okColor
$script:lblStatus.AutoSize = $true
$script:lblStatus.Location = New-Object System.Drawing.Point(24,725)

$script:prg = New-Object System.Windows.Forms.ProgressBar
$script:prg.Location = New-Object System.Drawing.Point(220,726)
$script:prg.Size = New-Object System.Drawing.Size(300,14)
$script:prg.Style = "Blocks"

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log: $script:LogFile"
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI",8)
$lblLog.ForeColor = $txtSoft
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(640,725)

$form.Controls.AddRange(@(
    $lblTitle,
    $lblSub,
    $lblCredit,
    $panelLeft,
    $panelOutput,
    $script:lblStatus,
    $script:prg,
    $lblLog
))

# =========================================================
# TIMER
# =========================================================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    Poll-LynextTask
})
$timer.Start()

Append-Output "Lynext Performance Center iniciado."
Append-Output "Log: $script:LogFile"
Set-Status "Pronto" "ok"
Write-LogLine "Lynext Performance Center iniciado"

[void]$form.ShowDialog()
