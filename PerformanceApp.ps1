#requires -version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Lynext - Performance Center'

# =========================================================
# Admin / paths
# =========================================================
$script:ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$script:LynextRoot = Join-Path $env:ProgramData 'Lynext'
$script:BackupFile = Join-Path $script:LynextRoot 'performance_backup.json'
$script:LogDir = Join-Path $script:LynextRoot 'Logs'
$null = New-Item -Path $script:LynextRoot -ItemType Directory -Force
$null = New-Item -Path $script:LogDir -ItemType Directory -Force
$script:LogFile = Join-Path $script:LogDir ("PerformanceApp_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Test-LynextAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LynextPowerShell {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $exe) { return $exe }
    return 'powershell.exe'
}

if (-not (Test-LynextAdmin)) {
    $exe = Get-LynextPowerShell
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script:ScriptPath`""
    exit
}

# =========================================================
# Theme
# =========================================================
$ui = @{
    Bg        = [Drawing.Color]::FromArgb(11, 15, 14)
    Panel     = [Drawing.Color]::FromArgb(18, 25, 22)
    Panel2    = [Drawing.Color]::FromArgb(24, 34, 30)
    Button    = [Drawing.Color]::FromArgb(22, 45, 35)
    ButtonHot = [Drawing.Color]::FromArgb(34, 70, 52)
    ButtonDn  = [Drawing.Color]::FromArgb(45, 92, 66)
    Text      = [Drawing.Color]::FromArgb(238, 244, 240)
    Muted     = [Drawing.Color]::FromArgb(165, 184, 172)
    Accent    = [Drawing.Color]::FromArgb(104, 226, 151)
    Border    = [Drawing.Color]::FromArgb(68, 117, 86)
    Warn      = [Drawing.Color]::FromArgb(255, 202, 92)
    Error     = [Drawing.Color]::FromArgb(255, 116, 116)
}

$font = @{
    Title = New-Object Drawing.Font('Segoe UI', 22, [Drawing.FontStyle]::Bold)
    H2    = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
    Text  = New-Object Drawing.Font('Segoe UI', 9)
    Btn   = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    Mono  = New-Object Drawing.Font('Consolas', 9)
}

$script:Task = $null
$script:IsBusy = $false
$script:LastModeCheck = [datetime]::MinValue

function Write-LynextLog {
    param([string]$Text)
    try {
        Add-Content -Path $script:LogFile -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text)
    }
    catch {}
}

function Add-Output {
    param([string]$Text, [switch]$Clear)
    if ($Clear) { $script:txtOutput.Clear() }
    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Trim().Length -gt 0) {
            $script:txtOutput.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $line))
        }
    }
    $script:txtOutput.SelectionStart = $script:txtOutput.TextLength
    $script:txtOutput.ScrollToCaret()
}

function Set-LynextStatus {
    param(
        [string]$Text,
        [ValidateSet('info','busy','ok','warn','error')]
        [string]$State = 'info'
    )
    $script:lblStatus.Text = "Status: $Text"
    switch ($State) {
        'busy'  { $script:lblStatus.ForeColor = $ui.Accent }
        'ok'    { $script:lblStatus.ForeColor = $ui.Accent }
        'warn'  { $script:lblStatus.ForeColor = $ui.Warn }
        'error' { $script:lblStatus.ForeColor = $ui.Error }
        default { $script:lblStatus.ForeColor = $ui.Text }
    }
}

function Escape-SingleQuote {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace "'", "''")
}

function Confirm-Lynext {
    param([string]$Message)
    $result = [Windows.Forms.MessageBox]::Show(
        $Message,
        'Lynext',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    )
    return ($result -eq [Windows.Forms.DialogResult]::Yes)
}

function Show-LynextInput {
    param([string]$Title, [string]$Label, [string]$DefaultValue = '')

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.Size = New-Object Drawing.Size(440, 170)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $ui.Bg
    $dialog.ForeColor = $ui.Text

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Location = New-Object Drawing.Point(16, 16)
    $lbl.Size = New-Object Drawing.Size(390, 24)
    $lbl.ForeColor = $ui.Text
    $lbl.Font = $font.Text

    $tb = New-Object Windows.Forms.TextBox
    $tb.Location = New-Object Drawing.Point(16, 48)
    $tb.Size = New-Object Drawing.Size(390, 25)
    $tb.Text = $DefaultValue
    $tb.BackColor = $ui.Panel2
    $tb.ForeColor = $ui.Text
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = $font.Text

    $ok = New-Object Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Location = New-Object Drawing.Point(238, 88)
    $ok.Size = New-Object Drawing.Size(78, 30)
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK

    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Cancelar'
    $cancel.Location = New-Object Drawing.Point(326, 88)
    $cancel.Size = New-Object Drawing.Size(80, 30)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel

    foreach ($button in @($ok, $cancel)) {
        $button.FlatStyle = 'Flat'
        $button.BackColor = $ui.Button
        $button.ForeColor = $ui.Text
        $button.FlatAppearance.BorderColor = $ui.Border
    }

    $dialog.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel

    if ($dialog.ShowDialog($script:Form) -eq [Windows.Forms.DialogResult]::OK) {
        return $tb.Text
    }
    return $null
}

# =========================================================
# Runtime used by background actions
# =========================================================
$script:Runtime = @'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$GuidBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GuidHigh = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GuidUltimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$PlanNames = @{
    Ultra   = 'Lynext Ultra Performance'
    Lite    = 'Lynext Lite'
    Thermal = 'Lynext Thermal'
}

$RegistryItems = @(
    @{ Id = 'AutoGameModeEnabled'; Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled' },
    @{ Id = 'AllowAutoGameMode'; Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AllowAutoGameMode' },
    @{ Id = 'AppCaptureEnabled'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled' },
    @{ Id = 'GameDVR_Enabled'; Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled' },
    @{ Id = 'HwSchMode'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode' },
    @{ Id = 'NetworkThrottlingIndex'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex' },
    @{ Id = 'SystemResponsiveness'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness' },
    @{ Id = 'PowerThrottlingOff'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; Name = 'PowerThrottlingOff' },
    @{ Id = 'GamesGpuPriority'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority' },
    @{ Id = 'GamesPriority'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority' }
)

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Test-RegValue {
    param([string]$Path, [string]$Name)
    try {
        $null = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Set-RegDwordSafe {
    param([string]$Path, [string]$Name, [UInt32]$Value)
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
    catch {
        "Aviso: nao consegui ajustar $Path\$Name ($($_.Exception.Message))"
    }
}

function Remove-RegValueSafe {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Get-ActivePowerSchemeGuid {
    $line = powercfg /getactivescheme | Out-String
    if ($line -match '([a-fA-F0-9-]{36})') { return $Matches[1] }
    return $null
}

function Get-PowerSchemes {
    $items = @()
    foreach ($line in ((powercfg /list | Out-String) -split "`r?`n")) {
        if ($line -match '([a-fA-F0-9-]{36})\s+\((.*?)\)(\s+\*)?') {
            $items += [pscustomobject]@{
                Guid = $Matches[1]
                Name = $Matches[2].Trim()
                IsActive = [bool]$Matches[3]
            }
        }
    }
    return $items
}

function Get-SchemeByName {
    param([string]$Name)
    Get-PowerSchemes | Where-Object { $_.Name -eq $Name }
}

function Remove-DuplicatePlans {
    param([string]$Name, [string]$KeepGuid)
    foreach ($plan in (Get-SchemeByName -Name $Name)) {
        if ($plan.Guid -ne $KeepGuid) {
            try { powercfg /delete $plan.Guid | Out-Null } catch {}
        }
    }
}

function Ensure-CustomPlan {
    param([string]$Name, [string]$PreferredBase, [string]$FallbackBase)

    $existing = Get-SchemeByName -Name $Name | Select-Object -First 1
    if ($existing) {
        Remove-DuplicatePlans -Name $Name -KeepGuid $existing.Guid
        return $existing.Guid
    }

    $base = $PreferredBase
    if (-not ((Get-PowerSchemes).Guid -contains $base)) { $base = $FallbackBase }

    $created = powercfg -duplicatescheme $base 2>&1 | Out-String
    if ($created -notmatch '([a-fA-F0-9-]{36})') {
        throw "Nao foi possivel criar o plano $Name."
    }

    $guid = $Matches[1]
    powercfg /changename $guid $Name | Out-Null
    Remove-DuplicatePlans -Name $Name -KeepGuid $guid
    return $guid
}

function Set-PowerValueSafe {
    param([string]$Scheme, [string]$Subgroup, [string]$Setting, [int]$Ac, [int]$Dc)
    try { powercfg /setacvalueindex $Scheme $Subgroup $Setting $Ac | Out-Null } catch {}
    try { powercfg /setdcvalueindex $Scheme $Subgroup $Setting $Dc | Out-Null } catch {}
}

function Set-PowerAliasSafe {
    param([string]$Scheme, [string]$Subgroup, [string]$Setting, [int]$Value)
    try { powercfg /setacvalueindex $Scheme $Subgroup $Setting $Value | Out-Null } catch {}
}

function Test-ModernStandby {
    try { return ((powercfg /a | Out-String) -match 'Standby \(S0 Low Power Idle\)') } catch { return $false }
}

function Get-IsLaptop {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        return ($cs.PCSystemType -in 2, 3, 4, 8, 9, 10, 14)
    }
    catch { return $false }
}

function Get-GpuVendor {
    try {
        $names = (Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -ExpandProperty Name) -join ' | '
        if ($names -match 'NVIDIA') { return 'NVIDIA' }
        if ($names -match 'AMD|Radeon') { return 'AMD' }
        if ($names -match 'Intel') { return 'Intel' }
    }
    catch {}
    return 'Unknown'
}

function Get-NvidiaSmiPath {
    $paths = @()
    if ($env:ProgramFiles) {
        $paths += (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')
    }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) {
        $paths += (Join-Path $pf86 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')
    }
    foreach ($path in $paths) {
        if ($path -and (Test-Path $path)) { return $path }
    }
    return $null
}

function Save-LynextBackup {
    param([string]$BackupFile)

    $registry = @{}
    foreach ($item in $RegistryItems) {
        $exists = Test-RegValue -Path $item.Path -Name $item.Name
        $registry[$item.Id] = @{
            Path = $item.Path
            Name = $item.Name
            Exists = $exists
            Value = if ($exists) { Get-RegValue -Path $item.Path -Name $item.Name } else { $null }
        }
    }

    $nvidiaPower = $null
    $smi = Get-NvidiaSmiPath
    if ($smi) {
        try {
            $raw = & $smi --query-gpu=power.default_limit --format=csv,noheader,nounits 2>$null
            $text = ($raw | Select-Object -First 1).ToString().Trim()
            if ($text -match '^\d+(\.\d+)?$') { $nvidiaPower = [double]$text }
        }
        catch {}
    }

    $data = @{
        CreatedAt = (Get-Date).ToString('s')
        PowerSchemeGuid = Get-ActivePowerSchemeGuid
        ModernStandby = Test-ModernStandby
        IsLaptop = Get-IsLaptop
        GpuVendor = Get-GpuVendor
        Registry = $registry
        Nvidia = @{ DefaultPowerLimit = $nvidiaPower }
    }

    $data | ConvertTo-Json -Depth 16 | Set-Content -Path $BackupFile -Encoding UTF8
    "Backup salvo em: $BackupFile"
}

function Restore-RegistryFromBackup {
    param([object]$Backup)

    if (-not $Backup.Registry) {
        'Backup sem bloco de registro.'
        return
    }

    foreach ($id in $Backup.Registry.PSObject.Properties.Name) {
        $entry = $Backup.Registry.$id
        if (-not $entry.Path -or -not $entry.Name) { continue }

        if ($entry.Exists -and $null -ne $entry.Value) {
            try {
                Set-RegDwordSafe -Path $entry.Path -Name $entry.Name -Value ([UInt32]$entry.Value)
                "Registro restaurado: $id"
            }
            catch {
                "Aviso: nao consegui restaurar $id"
            }
        }
        else {
            Remove-RegValueSafe -Path $entry.Path -Name $entry.Name
        }
    }
}

function Set-LynextPowerProfile {
    param([ValidateSet('Ultra','Lite','Thermal')] [string]$Profile)

    switch ($Profile) {
        'Ultra' {
            $guid = Ensure-CustomPlan -Name $PlanNames.Ultra -PreferredBase $GuidUltimate -FallbackBase $GuidHigh
            Set-PowerValueSafe $guid 'sub_processor' 'PROCTHROTTLEMIN' 100 100
            Set-PowerValueSafe $guid 'sub_processor' 'PROCTHROTTLEMAX' 100 100
            Set-PowerValueSafe $guid 'sub_processor' 'PERFEPP' 0 0
            Set-PowerValueSafe $guid 'sub_processor' 'PERFBOOSTMODE' 2 2
            Set-PowerValueSafe $guid 'sub_processor' 'CPMINCORES' 100 100
            Set-PowerAliasSafe $guid 'SUB_SLEEP' 'STANDBYIDLE' 0
            Set-PowerAliasSafe $guid 'SUB_SLEEP' 'HIBERNATEIDLE' 0
            Set-PowerAliasSafe $guid 'SUB_DISK' 'DISKIDLE' 0
            Set-PowerAliasSafe $guid 'SUB_VIDEO' 'VIDEOIDLE' 0
            Set-PowerAliasSafe $guid 'SUB_PCIEXPRESS' 'ASPM' 0
        }
        'Lite' {
            $guid = Ensure-CustomPlan -Name $PlanNames.Lite -PreferredBase $GuidBalanced -FallbackBase $GuidBalanced
            Set-PowerValueSafe $guid 'sub_processor' 'PROCTHROTTLEMIN' 5 5
            Set-PowerValueSafe $guid 'sub_processor' 'PROCTHROTTLEMAX' 100 100
            Set-PowerValueSafe $guid 'sub_processor' 'PERFEPP' 25 45
            Set-PowerValueSafe $guid 'sub_processor' 'PERFBOOSTMODE' 1 1
            Set-PowerValueSafe $guid 'sub_processor' 'CPMINCORES' 50 25
        }
        'Thermal' {
            $guid = Ensure-CustomPlan -Name $PlanNames.Thermal -PreferredBase $GuidBalanced -FallbackBase $GuidBalanced
            Set-PowerValueSafe $guid 'sub_processor' 'PROCTHROTTLEMIN' 5 5
            Set-PowerValueSafe $guid 'sub_processor' 'PROCTHROTTLEMAX' 99 99
            Set-PowerValueSafe $guid 'sub_processor' 'PERFEPP' 60 80
            Set-PowerValueSafe $guid 'sub_processor' 'PERFBOOSTMODE' 0 0
            Set-PowerValueSafe $guid 'sub_processor' 'CPMINCORES' 25 10
        }
    }

    try { powercfg /setactive $guid | Out-Null } catch {}
    "Plano ativo: $Profile ($guid)"
}

function Set-LynextWindowsProfile {
    param([ValidateSet('Ultra','Lite')] [string]$Profile)

    Set-RegDwordSafe 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-RegDwordSafe 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
    Set-RegDwordSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-RegDwordSafe 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-RegDwordSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
    Set-RegDwordSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
    Set-RegDwordSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8
    Set-RegDwordSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6

    if ($Profile -eq 'Ultra') {
        Set-RegDwordSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' ([UInt32]4294967295)
        Set-RegDwordSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
    }
    else {
        Set-RegDwordSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10
        Set-RegDwordSafe 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 20
    }

    "Windows $Profile aplicado. Reinicio recomendado para HAGS."
}

function Set-NvidiaProfile {
    param([ValidateSet('Ultra','Lite','Reset')] [string]$Profile, [string]$BackupFile)

    $smi = Get-NvidiaSmiPath
    if (-not $smi) {
        'nvidia-smi nao encontrado. Ajustes automaticos de NVIDIA ignorados.'
        return
    }

    if ($Profile -eq 'Ultra') {
        try {
            $limits = & $smi --query-gpu=power.min_limit,power.max_limit,power.default_limit --format=csv,noheader,nounits 2>$null
            $parts = ($limits | Select-Object -First 1).ToString().Split(',') | ForEach-Object { $_.Trim() }
            if ($parts.Count -ge 2 -and $parts[1] -match '^\d+(\.\d+)?$') {
                & $smi -pl ([double]$parts[1]) | Out-Null
                "Power limit NVIDIA ajustado para $($parts[1]) W"
            }
        }
        catch { 'Nao consegui ajustar o power limit NVIDIA.' }
        'Sugestao NVIDIA: prefer maximum performance, texture filtering high performance, Reflex quando o jogo suportar.'
        return
    }

    if ($Profile -eq 'Reset') {
        try { & $smi -rgc | Out-Null; 'Clocks NVIDIA resetados.' } catch { 'Reset de clocks indisponivel nessa GPU/driver.' }
    }

    if (Test-Path $BackupFile) {
        $backup = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json
        if ($backup.Nvidia.DefaultPowerLimit) {
            try {
                & $smi -pl ([double]$backup.Nvidia.DefaultPowerLimit) | Out-Null
                "Power limit NVIDIA restaurado para $($backup.Nvidia.DefaultPowerLimit) W"
            }
            catch { 'Nao consegui restaurar o power limit salvo.' }
        }
    }
}

function Restore-LynextBackup {
    param([string]$BackupFile)
    if (-not (Test-Path $BackupFile)) { throw 'Backup nao encontrado.' }
    $backup = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json

    if ($backup.PowerSchemeGuid) {
        try { powercfg /setactive $backup.PowerSchemeGuid | Out-Null; 'Plano de energia restaurado.' }
        catch { 'Nao consegui restaurar o plano de energia salvo.' }
    }
    Restore-RegistryFromBackup -Backup $backup
    Set-NvidiaProfile -Profile Reset -BackupFile $BackupFile
    'Reset geral concluido.'
}

function Show-LynextSummary {
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $os = $null }
    try { $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { $cpu = $null }
    try { $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop) } catch { $gpus = @() }

    if ($os) { 'Windows: ' + $os.Caption + ' build ' + $os.BuildNumber } else { 'Windows: nao identificado' }
    if ($cpu) { 'CPU: ' + $cpu.Name } else { 'CPU: nao identificada' }
    'GPU principal: ' + (Get-GpuVendor)
    'Notebook: ' + (Get-IsLaptop)
    'Modern Standby: ' + (Test-ModernStandby)
    $activePlan = Get-PowerSchemes | Where-Object { $_.IsActive } | Select-Object -First 1
    if ($activePlan) {
        'Plano ativo: ' + $activePlan.Name + ' | ' + $activePlan.Guid
        switch ($activePlan.Name) {
            'Lynext Ultra Performance' { 'Modo Lynext detectado: Ultra' }
            'Lynext Lite'              { 'Modo Lynext detectado: Lite' }
            'Lynext Thermal'           { 'Modo Lynext detectado: Termico / quieto' }
            default                    { 'Modo Lynext detectado: nenhum preset Lynext ativo' }
        }
    }
    else {
        'Plano ativo: nao identificado'
    }
    ''
    'Planos:'
    foreach ($plan in Get-PowerSchemes) {
        $mark = if ($plan.IsActive) { '*' } else { '-' }
        " $mark $($plan.Name) | $($plan.Guid)"
    }
    ''
    'GPUs:'
    if ($gpus.Count -eq 0) {
        ' - Nenhuma GPU listada por WMI/CIM.'
    }
    else {
        foreach ($gpu in $gpus) {
            " - $($gpu.Name) | Driver $($gpu.DriverVersion)"
        }
    }
}
'@

function New-TaskCode {
    param([string]$Body)
    return @"
try {
$($script:Runtime)

$Body

    exit 0
}
catch {
    [Console]::Error.WriteLine(`$_.Exception.Message)
    exit 1
}
"@
}

function Get-LocalActivePowerPlan {
    try {
        $line = powercfg /getactivescheme | Out-String
        if ($line -match '([a-fA-F0-9-]{36})\s+\((.*?)\)') {
            return [pscustomobject]@{ Guid = $Matches[1]; Name = $Matches[2].Trim() }
        }
    }
    catch {}
    return $null
}

function Get-LocalActiveModeText {
    $plan = Get-LocalActivePowerPlan
    if (-not $plan) { return 'Modo ativo: nao identificado' }

    switch -Regex ($plan.Name) {
        '^Lynext Ultra Performance$' { return 'Modo ativo: Ultra' }
        '^Lynext Lite$'              { return 'Modo ativo: Lite' }
        '^Lynext Thermal$'           { return 'Modo ativo: Termico' }
        'High performance|Alto desempenho' { return 'Modo ativo: Alto desempenho do Windows' }
        'Balanced|Equilibrado'       { return 'Modo ativo: Equilibrado do Windows' }
        default                      { return "Modo ativo: $($plan.Name)" }
    }
}

function Update-ActiveModeLabel {
    if (-not $script:lblMode) { return }
    $text = Get-LocalActiveModeText
    $script:lblMode.Text = $text
    if ($text -match 'Ultra|Lite|Termico') {
        $script:lblMode.ForeColor = $ui.Accent
    }
    elseif ($text -match 'nao identificado') {
        $script:lblMode.ForeColor = $ui.Warn
    }
    else {
        $script:lblMode.ForeColor = $ui.Muted
    }
}

function Start-LynextTask {
    param(
        [string]$Name,
        [string]$Body,
        [switch]$Confirm,
        [string]$ConfirmMessage = 'Confirmar execucao?'
    )

    if ($script:IsBusy) {
        Set-LynextStatus 'Aguarde a tarefa atual terminar.' 'warn'
        return
    }

    if ($Confirm -and -not (Confirm-Lynext $ConfirmMessage)) { return }

    $outFile = Join-Path $script:LogDir ("task_out_{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $errFile = Join-Path $script:LogDir ("task_err_{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $taskFile = Join-Path $script:LogDir ("task_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    New-TaskCode $Body | Set-Content -Path $taskFile -Encoding UTF8

    Add-Output ">>> $Name" -Clear
    Set-LynextStatus "Executando: $Name" 'busy'
    Write-LynextLog "START: $Name"

    $script:Progress.Style = [Windows.Forms.ProgressBarStyle]::Marquee
    $script:IsBusy = $true

    $proc = Start-Process -FilePath (Get-LynextPowerShell) `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$taskFile`"" `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError $errFile `
        -WindowStyle Hidden `
        -PassThru

    $script:Task = [pscustomobject]@{
        Name = $Name
        Process = $proc
        OutFile = $outFile
        ErrFile = $errFile
        TaskFile = $taskFile
        LastOutLen = 0
        LastErrLen = 0
    }
}

function Read-TaskDelta {
    param([string]$Path, [int]$Offset)
    if (-not (Test-Path $Path)) { return @{ Text = ''; Length = 0 } }
    $text = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $text) { $text = '' }
    if ($text.Length -gt $Offset) {
        return @{ Text = $text.Substring($Offset); Length = $text.Length }
    }
    return @{ Text = ''; Length = $text.Length }
}

function Poll-LynextTask {
    if (-not $script:Task) { return }
    $task = $script:Task
    try { $task.Process.Refresh() } catch {}

    $out = Read-TaskDelta -Path $task.OutFile -Offset $task.LastOutLen
    if ($out.Text) { Add-Output $out.Text.TrimEnd() }
    $task.LastOutLen = $out.Length

    $err = Read-TaskDelta -Path $task.ErrFile -Offset $task.LastErrLen
    if ($err.Text) { Add-Output ("ERRO:`r`n" + $err.Text.TrimEnd()) }
    $task.LastErrLen = $err.Length
    $script:Task = $task

    if (-not $task.Process.HasExited) { return }

    try {
        $task.Process.Refresh()
        $exit = $task.Process.ExitCode
    }
    catch {
        $exit = $null
    }

    $hasErrorText = ((Test-Path $task.ErrFile) -and (Get-Item $task.ErrFile).Length -gt 0)
    if ($null -eq $exit -and -not $hasErrorText) {
        $exit = 0
    }

    if ($exit -eq 0 -and $hasErrorText) {
        Set-LynextStatus "$($task.Name) concluido com avisos." 'warn'
        Write-LynextLog "WARN: $($task.Name)"
    }
    elseif ($exit -eq 0) {
        Set-LynextStatus "$($task.Name) concluido." 'ok'
        Write-LynextLog "OK: $($task.Name)"
    }
    else {
        Set-LynextStatus "$($task.Name) falhou. Veja a saida." 'error'
        Write-LynextLog "FAIL: $($task.Name) ExitCode=$exit"
    }

    $script:Progress.Style = [Windows.Forms.ProgressBarStyle]::Blocks
    $script:IsBusy = $false
    $script:Task = $null
    Update-ActiveModeLabel
}

# =========================================================
# UI helpers
# =========================================================
function New-Label {
    param([string]$Text, [Drawing.Font]$Font, [Drawing.Color]$Color)
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Font = $Font
    $lbl.ForeColor = $Color
    $lbl.AutoSize = $true
    return $lbl
}

function New-ActionButton {
    param(
        [string]$Text,
        [string]$Hint,
        [scriptblock]$OnClick,
        [int]$Width = 250
    )

    $btn = New-Object Windows.Forms.Button
    $btn.Text = $Text
    $btn.Size = New-Object Drawing.Size($Width, 42)
    $btn.Margin = New-Object Windows.Forms.Padding(6)
    $btn.BackColor = $ui.Button
    $btn.ForeColor = $ui.Text
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = $ui.Border
    $btn.FlatAppearance.MouseOverBackColor = $ui.ButtonHot
    $btn.FlatAppearance.MouseDownBackColor = $ui.ButtonDn
    $btn.Font = $font.Btn
    $btn.Cursor = [Windows.Forms.Cursors]::Hand
    $btn.UseVisualStyleBackColor = $false
    $btn.Add_Click({
        try {
            & $OnClick
        }
        catch {
            Add-Output ("Falha ao executar acao: " + $_.Exception.Message) -Clear
            Set-LynextStatus 'Acao falhou. Veja a saida.' 'error'
            Write-LynextLog ("UI ERROR: " + $_.Exception.Message)
        }
    }.GetNewClosure())
    if ($Hint) { $script:Tip.SetToolTip($btn, $Hint) }
    return $btn
}

function New-Tab {
    param([string]$Title, [string]$Header, [string]$Description)
    $tab = New-Object Windows.Forms.TabPage
    $tab.Text = $Title
    $tab.BackColor = $ui.Panel
    $tab.ForeColor = $ui.Text
    $tab.Padding = New-Object Windows.Forms.Padding(14)

    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    $layout.BackColor = $ui.Panel
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 48))) | Out-Null
    $layout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null

    $title = New-Label $Header $font.H2 $ui.Text
    $desc = New-Label $Description $font.Text $ui.Muted
    $desc.MaximumSize = New-Object Drawing.Size(540, 44)

    $flow = New-Object Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'
    $flow.AutoScroll = $true
    $flow.WrapContents = $true
    $flow.BackColor = $ui.Panel

    $layout.Controls.Add($title, 0, 0)
    $layout.Controls.Add($desc, 0, 1)
    $layout.Controls.Add($flow, 0, 2)
    $tab.Controls.Add($layout)

    return [pscustomobject]@{ Page = $tab; Flow = $flow }
}

# =========================================================
# Form
# =========================================================
$script:Form = New-Object Windows.Forms.Form
$script:Form.Text = 'Lynext - Performance Center'
$script:Form.MinimumSize = New-Object Drawing.Size(980, 640)
$script:Form.Size = New-Object Drawing.Size(1160, 720)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.BackColor = $ui.Bg
$script:Form.ForeColor = $ui.Text

$root = New-Object Windows.Forms.TableLayoutPanel
$root.Dock = 'Fill'
$root.BackColor = $ui.Bg
$root.ColumnCount = 1
$root.RowCount = 3
$root.Padding = New-Object Windows.Forms.Padding(18)
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 72))) | Out-Null
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$root.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 34))) | Out-Null

$header = New-Object Windows.Forms.TableLayoutPanel
$header.Dock = 'Fill'
$header.ColumnCount = 2
$header.RowCount = 2
$header.BackColor = $ui.Bg
$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$header.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 170))) | Out-Null

$title = New-Label 'Lynext' $font.Title $ui.Accent
$subtitle = New-Label 'Performance Center compacto para energia, Windows e GPU' $font.Text $ui.Muted
$credit = New-Label 'Created by Ryan' $font.Text $ui.Muted
$credit.TextAlign = 'MiddleRight'
$credit.Dock = 'Fill'

$header.Controls.Add($title, 0, 0)
$header.Controls.Add($subtitle, 0, 1)
$header.Controls.Add($credit, 1, 0)
$header.SetRowSpan($credit, 2)

$split = New-Object Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$split.SplitterDistance = 560
$split.Panel1MinSize = 520
$split.Panel2MinSize = 320
$split.BackColor = $ui.Bg
$split.Panel1.BackColor = $ui.Panel
$split.Panel2.BackColor = $ui.Panel

function Resize-LynextSplit {
    if (-not $split -or $split.Width -le 900) { return }
    $split.SplitterDistance = [Math]::Max($split.Panel1MinSize, $split.Width - 340)
}

$script:Tip = New-Object Windows.Forms.ToolTip
$script:Tip.AutoPopDelay = 9000
$script:Tip.InitialDelay = 250
$script:Tip.ReshowDelay = 100

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Font = $font.Text
$tabs.DrawMode = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.ItemSize = New-Object Drawing.Size(140, 30)
$tabs.SizeMode = 'Fixed'
$tabs.Add_DrawItem({
    param($sender, $e)
    $tab = $sender.TabPages[$e.Index]
    $selected = (($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0)
    $back = if ($selected) { $ui.Panel } else { $ui.Panel2 }
    $fore = if ($selected) { $ui.Accent } else { $ui.Text }
    $brush = New-Object Drawing.SolidBrush($back)
    $textBrush = New-Object Drawing.SolidBrush($fore)
    $e.Graphics.FillRectangle($brush, $e.Bounds)
    $e.Graphics.DrawString($tab.Text, $font.Text, $textBrush, ($e.Bounds.X + 10), ($e.Bounds.Y + 7))
    $brush.Dispose()
    $textBrush.Dispose()
})

$tabPresets = New-Tab 'Presets' 'Presets principais' 'Use estes botoes para aplicar um pacote pronto. Ultra prioriza FPS e resposta; Lite equilibra desempenho e consumo; Termico reduz calor e ruido.'
$tabTuning = New-Tab 'Energia + Windows' 'Ajustes separados' 'Aqui voce mexe em uma parte por vez: plano de energia da CPU ou ajustes de jogos do Windows.'
$tabGpu = New-Tab 'GPU' 'GPU e politicas' 'NVIDIA usa nvidia-smi quando disponivel. AMD e Intel ficam com diagnostico e recomendacoes para evitar tuning arriscado.'
$tabBackup = New-Tab 'Backup' 'Backup, reset e logs' 'Salve o estado atual antes dos presets. O reset volta energia, Windows e NVIDIA para o que foi salvo.'
$tabs.TabPages.AddRange(@($tabPresets.Page, $tabTuning.Page, $tabGpu.Page, $tabBackup.Page))
function Resize-LynextTabs {
    if (-not $tabs -or $tabs.TabCount -le 0) { return }
    $width = [Math]::Max(120, [Math]::Floor(($tabs.ClientSize.Width - 8) / $tabs.TabCount))
    $tabs.ItemSize = New-Object Drawing.Size($width, 30)
    $tabs.Invalidate()
}
$tabs.Add_Resize({ Resize-LynextTabs })
Resize-LynextTabs
$split.Panel1.Controls.Add($tabs)

$outPanel = New-Object Windows.Forms.TableLayoutPanel
$outPanel.Dock = 'Fill'
$outPanel.BackColor = $ui.Panel
$outPanel.Padding = New-Object Windows.Forms.Padding(12)
$outPanel.RowCount = 2
$outPanel.ColumnCount = 1
$outPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
$outPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null

$outTitle = New-Label 'Saida' $font.H2 $ui.Text
$script:txtOutput = New-Object Windows.Forms.TextBox
$script:txtOutput.Dock = 'Fill'
$script:txtOutput.Multiline = $true
$script:txtOutput.ScrollBars = 'Vertical'
$script:txtOutput.ReadOnly = $true
$script:txtOutput.BackColor = $ui.Panel2
$script:txtOutput.ForeColor = $ui.Text
$script:txtOutput.BorderStyle = 'FixedSingle'
$script:txtOutput.Font = $font.Mono

$outPanel.Controls.Add($outTitle, 0, 0)
$outPanel.Controls.Add($script:txtOutput, 0, 1)
$split.Panel2.Controls.Add($outPanel)

$footer = New-Object Windows.Forms.TableLayoutPanel
$footer.Dock = 'Fill'
$footer.ColumnCount = 4
$footer.RowCount = 1
$footer.BackColor = $ui.Bg
$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 250))) | Out-Null
$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 240))) | Out-Null
$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 260))) | Out-Null
$footer.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null

$script:lblStatus = New-Label 'Status: Pronto' $font.Btn $ui.Accent
$script:lblStatus.Dock = 'Fill'
$script:lblMode = New-Label 'Modo ativo: verificando...' $font.Btn $ui.Warn
$script:lblMode.Dock = 'Fill'
$script:Progress = New-Object Windows.Forms.ProgressBar
$script:Progress.Dock = 'Fill'
$script:Progress.Margin = New-Object Windows.Forms.Padding(0, 7, 12, 7)
$script:Progress.Style = 'Blocks'
$logLabel = New-Label ("Log: $script:LogFile") $font.Text $ui.Muted
$logLabel.Dock = 'Fill'

$footer.Controls.Add($script:lblStatus, 0, 0)
$footer.Controls.Add($script:lblMode, 1, 0)
$footer.Controls.Add($script:Progress, 2, 0)
$footer.Controls.Add($logLabel, 3, 0)

$root.Controls.Add($header, 0, 0)
$root.Controls.Add($split, 0, 1)
$root.Controls.Add($footer, 0, 2)
$script:Form.Controls.Add($root)
$script:Form.Add_Shown({ Resize-LynextSplit; Resize-LynextTabs })
$script:Form.Add_Resize({ Resize-LynextSplit; Resize-LynextTabs })

# =========================================================
# Actions
# =========================================================
$backupPath = Escape-SingleQuote $script:BackupFile

$tabPresets.Flow.Controls.Add((New-ActionButton 'Ultra completo' 'Maximo desempenho: cria/ativa plano Ultra, desliga DVR, liga Game Mode/HAGS e tenta elevar limite NVIDIA.' {
    Start-LynextTask 'Ultra completo' @"
if (-not (Test-Path '$backupPath')) { Save-LynextBackup -BackupFile '$backupPath' }
Set-LynextPowerProfile -Profile Ultra
Set-LynextWindowsProfile -Profile Ultra
if ((Get-GpuVendor) -eq 'NVIDIA') { Set-NvidiaProfile -Profile Ultra -BackupFile '$backupPath' } else { 'GPU nao NVIDIA: ajuste automatico pesado ignorado.' }
'Ultra completo aplicado.'
"@ -Confirm -ConfirmMessage 'O modo Ultra e mais agressivo e pode aumentar consumo/temperatura. Deseja continuar?'
}))

$tabPresets.Flow.Controls.Add((New-ActionButton 'Lite equilibrado' 'Perfil diario: bom desempenho com consumo menor, Windows otimizado e NVIDIA voltando ao limite salvo.' {
    Start-LynextTask 'Lite equilibrado' @"
if (-not (Test-Path '$backupPath')) { Save-LynextBackup -BackupFile '$backupPath' }
Set-LynextPowerProfile -Profile Lite
Set-LynextWindowsProfile -Profile Lite
if ((Get-GpuVendor) -eq 'NVIDIA') { Set-NvidiaProfile -Profile Lite -BackupFile '$backupPath' } else { 'GPU nao NVIDIA: mantendo politica conservadora.' }
'Lite equilibrado aplicado.'
"@
}))

$tabPresets.Flow.Controls.Add((New-ActionButton 'Termico / quieto' 'Para notebook quente ou barulhento: reduz boost agressivo e prioriza temperatura/estabilidade.' {
    Start-LynextTask 'Termico / quieto' "Set-LynextPowerProfile -Profile Thermal"
}))

$tabPresets.Flow.Controls.Add((New-ActionButton 'Resumo do sistema' 'Mostra Windows, CPU, GPUs, plano ativo e qual preset Lynext esta em uso.' {
    Start-LynextTask 'Resumo do sistema' 'Show-LynextSummary'
}))

$tabTuning.Flow.Controls.Add((New-ActionButton 'Energia Ultra' 'Somente energia: CPU sempre em alta performance e suspensoes economicas reduzidas.' {
    Start-LynextTask 'Energia Ultra' "Set-LynextPowerProfile -Profile Ultra"
}))

$tabTuning.Flow.Controls.Add((New-ActionButton 'Energia Lite' 'Somente energia: mantem resposta boa sem travar tudo no maximo o tempo todo.' {
    Start-LynextTask 'Energia Lite' "Set-LynextPowerProfile -Profile Lite"
}))

$tabTuning.Flow.Controls.Add((New-ActionButton 'Energia Termica' 'Somente energia: reduz boost e ajuda a controlar temperatura, ruido e bateria.' {
    Start-LynextTask 'Energia Termica' "Set-LynextPowerProfile -Profile Thermal"
}))

$tabTuning.Flow.Controls.Add((New-ActionButton 'Windows Ultra' 'Somente Windows: Game Mode/HAGS ligados, DVR desligado e prioridades de jogos mais agressivas.' {
    Start-LynextTask 'Windows Ultra' "Set-LynextWindowsProfile -Profile Ultra"
}))

$tabTuning.Flow.Controls.Add((New-ActionButton 'Windows Lite' 'Somente Windows: remove gravacao em segundo plano e usa prioridades mais moderadas.' {
    Start-LynextTask 'Windows Lite' "Set-LynextWindowsProfile -Profile Lite"
}))

$tabTuning.Flow.Controls.Add((New-ActionButton 'Reset Windows' 'Volta apenas os ajustes de registro do Windows usando o backup salvo.' {
    if (-not (Test-Path $script:BackupFile)) {
        [Windows.Forms.MessageBox]::Show('Backup nao encontrado.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }
    Start-LynextTask 'Reset Windows' @"
`$backup = Get-Content -Path '$backupPath' -Raw | ConvertFrom-Json
Restore-RegistryFromBackup -Backup `$backup
'Windows restaurado pelo backup.'
"@
}))

$tabGpu.Flow.Controls.Add((New-ActionButton 'NVIDIA estado' 'Mostra limites de energia e clocks reportados pelo nvidia-smi.' {
    Start-LynextTask 'NVIDIA estado' @"
`$smi = Get-NvidiaSmiPath
if (-not `$smi) { 'nvidia-smi nao encontrado.'; return }
& `$smi -q -d POWER,CLOCK
"@
}))

$tabGpu.Flow.Controls.Add((New-ActionButton 'NVIDIA Ultra' 'Tenta aplicar o maior power limit permitido pela GPU/driver.' {
    Start-LynextTask 'NVIDIA Ultra' "Set-NvidiaProfile -Profile Ultra -BackupFile '$backupPath'"
}))

$tabGpu.Flow.Controls.Add((New-ActionButton 'NVIDIA Reset/Lite' 'Reseta clocks e volta ao power limit padrao guardado no backup.' {
    if (-not (Test-Path $script:BackupFile)) {
        [Windows.Forms.MessageBox]::Show('Backup nao encontrado.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }
    Start-LynextTask 'NVIDIA Reset/Lite' "Set-NvidiaProfile -Profile Reset -BackupFile '$backupPath'"
}))

$tabGpu.Flow.Controls.Add((New-ActionButton 'Power limit manual' 'Digite um limite em Watts. Use apenas valores suportados pela sua GPU.' {
    $watts = Show-LynextInput -Title 'Power limit NVIDIA' -Label 'Valor em Watts:' -DefaultValue '200'
    if ([string]::IsNullOrWhiteSpace($watts)) { return }
    if ($watts -notmatch '^\d+(\.\d+)?$') {
        [Windows.Forms.MessageBox]::Show('Valor invalido.', 'Lynext', 'OK', 'Error') | Out-Null
        return
    }
    $safeWatts = Escape-SingleQuote $watts
    Start-LynextTask 'Power limit manual' @"
`$smi = Get-NvidiaSmiPath
if (-not `$smi) { throw 'nvidia-smi nao encontrado.' }
& `$smi -pl ([double]'$safeWatts') | Out-Null
'Power limit ajustado para $safeWatts W'
"@
}))

$tabGpu.Flow.Controls.Add((New-ActionButton 'AMD / Intel guia' 'Mostra GPU detectada e politicas seguras para AMD/Intel.' {
    Add-Output @"
AMD:
- Anti-Lag ON
- Chill OFF
- Boost moderado
- Sharpening leve a moderado

Intel:
- Driver atualizado
- Plano de energia correto
- Ajustes conservadores para estabilidade

O tuning automatico pesado fica limitado a NVIDIA por depender do nvidia-smi.
"@ -Clear
    Set-LynextStatus 'Guia AMD / Intel exibido.' 'ok'
}))

$tabBackup.Flow.Controls.Add((New-ActionButton 'Criar / atualizar backup' 'Guarda o estado atual para conseguir voltar depois com Reset geral.' {
    Start-LynextTask 'Criar / atualizar backup' "Save-LynextBackup -BackupFile '$backupPath'"
}))

$tabBackup.Flow.Controls.Add((New-ActionButton 'Reset geral' 'Volta plano de energia, registros do Windows e ajustes NVIDIA para o backup.' {
    if (-not (Test-Path $script:BackupFile)) {
        [Windows.Forms.MessageBox]::Show('Backup nao encontrado.', 'Lynext', 'OK', 'Warning') | Out-Null
        return
    }
    Start-LynextTask 'Reset geral' "Restore-LynextBackup -BackupFile '$backupPath'" -Confirm -ConfirmMessage 'Deseja restaurar os ajustes pelo backup salvo?'
}))

$tabBackup.Flow.Controls.Add((New-ActionButton 'Abrir pasta Lynext' 'Abre ProgramData\Lynext.' {
    Start-Process explorer.exe $script:LynextRoot
    Set-LynextStatus 'Pasta Lynext aberta.' 'ok'
}))

$tabBackup.Flow.Controls.Add((New-ActionButton 'Abrir logs' 'Abre a pasta de logs.' {
    Start-Process explorer.exe $script:LogDir
    Set-LynextStatus 'Pasta de logs aberta.' 'ok'
}))

$tabBackup.Flow.Controls.Add((New-ActionButton 'Mostrar caminhos' 'Mostra caminhos de backup e log atual.' {
    Add-Output @"
Backup: $script:BackupFile
Log: $script:LogFile
Pasta: $script:LynextRoot
"@ -Clear
    Set-LynextStatus 'Caminhos exibidos.' 'ok'
}))

# =========================================================
# Timer / start
# =========================================================
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    Poll-LynextTask
    if (-not $script:IsBusy -and ((Get-Date) - $script:LastModeCheck).TotalSeconds -ge 5) {
        $script:LastModeCheck = Get-Date
        Update-ActiveModeLabel
    }
})
$timer.Start()

Add-Output 'Lynext Performance Center iniciado.'
Add-Output "Backup: $script:BackupFile"
Add-Output "Log: $script:LogFile"
Set-LynextStatus 'Pronto' 'ok'
Update-ActiveModeLabel
Write-LynextLog 'Lynext Performance Center iniciado'

[void]$script:Form.ShowDialog()
