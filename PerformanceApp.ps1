# ============================================
# LYNEXT - PerformanceApp.ps1
# Tema verde / revisado / mais estavel
# Created by Ryan
# ============================================

$Host.UI.RawUI.WindowTitle = "Lynext - Performance App"

# ============================================
# PATHS
# ============================================

$global:LynextRoot   = Join-Path $env:ProgramData "Lynext"
$global:BackupFile   = Join-Path $global:LynextRoot "performance_backup.json"
$global:LogFile      = Join-Path $global:LynextRoot "performance_log.txt"

if (-not (Test-Path $global:LynextRoot)) {
    New-Item -Path $global:LynextRoot -ItemType Directory -Force | Out-Null
}

# ============================================
# UI / TEMA
# ============================================

$global:ColorMain   = "Green"
$global:ColorSoft   = "DarkGreen"
$global:ColorTitle  = "Cyan"
$global:ColorInfo   = "Green"
$global:ColorWarn   = "Yellow"
$global:ColorError  = "Red"
$global:ColorOk     = "Green"

function Pause-Lynext {
    Write-Host ""
    Read-Host "Pressione ENTER para continuar" | Out-Null
}

function Show-Line {
    Write-Host "====================================================================" -ForegroundColor $global:ColorSoft
}

function Show-Header {
    param(
        [string]$Title = "PERFORMANCE APP"
    )

    Clear-Host
    Show-Line
    Write-Host "                            L Y N E X T" -ForegroundColor $global:ColorTitle
    Write-Host "                        $Title" -ForegroundColor $global:ColorMain
    Show-Line
    Write-Host ""
}

function Write-Ok {
    param([string]$Text)
    Write-Host "[OK]   $Text" -ForegroundColor $global:ColorOk
}

function Write-WarnL {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor $global:ColorWarn
}

function Write-ErrL {
    param([string]$Text)
    Write-Host "[ERRO] $Text" -ForegroundColor $global:ColorError
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor $global:ColorInfo
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ">> $Text" -ForegroundColor $global:ColorTitle
}

function Show-MenuTitle {
    param([string]$Text)
    Write-Host $Text -ForegroundColor $global:ColorTitle
    Write-Host ""
}

function Write-LogLine {
    param([string]$Text)

    try {
        $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
        Add-Content -Path $global:LogFile -Value $line -Encoding UTF8
    }
    catch {}
}

# ============================================
# ADMIN
# ============================================

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (-not (Test-IsAdministrator)) {
        Show-Header "PERFORMANCE APP"
        Write-ErrL "Execute este script como Administrador."
        Pause-Lynext
        exit
    }
}

# ============================================
# JSON
# ============================================

function Save-Json {
    param(
        [string]$Path,
        [object]$Data
    )

    $Data | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
}

function Load-Json {
    param([string]$Path)

    if (Test-Path $Path) {
        try {
            return Get-Content $Path -Raw | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }

    return $null
}

# ============================================
# REGISTRY
# ============================================

function Get-RegValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        return $null
    }
}

function Set-RegDword {
    param(
        [string]$Path,
        [string]$Name,
        [UInt32]$Value
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        $current = Get-RegValue -Path $Path -Name $Name
        if ($current -ne $Value) {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
        }

        Write-LogLine "REG SET $Path -> $Name = $Value"
        return $true
    }
    catch {
        Write-ErrL "Falha ao alterar registro: $Path -> $Name"
        Write-LogLine "REG FAIL $Path -> $Name = $Value"
        return $false
    }
}

function Remove-RegValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
            Write-LogLine "REG REMOVE $Path -> $Name"
        }
        return $true
    }
    catch {
        Write-ErrL "Falha ao remover registro: $Path -> $Name"
        return $false
    }
}

# ============================================
# SYSTEM INFO
# ============================================

function Get-ActivePowerSchemeGuid {
    $line = powercfg /getactivescheme
    if ($line -match '([a-fA-F0-9-]{36})') {
        return $Matches[1]
    }
    return $null
}

function Test-ModernStandby {
    try {
        $out = powercfg /a | Out-String
        if ($out -match "Standby \(S0 Low Power Idle\)") {
            return $true
        }
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
        if ($cs.PCSystemType -in 2,3,4,8,9,10,14) {
            return $true
        }
    }
    catch {}

    return $false
}

function Show-SystemSummary {
    Show-Header "RESUMO DO SISTEMA"

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpus = Get-CimInstance Win32_VideoController
        $modernStandby = Test-ModernStandby
        $isLaptop = Get-IsLaptop
        $plan = Get-ActivePowerSchemeGuid

        Write-Host "Windows:         $($os.Caption) build $($os.BuildNumber)"
        Write-Host "CPU:             $($cpu.Name)"
        Write-Host "GPU vendor:      $(Get-GpuVendor)"
        Write-Host "Notebook:        $isLaptop"
        Write-Host "Modern Standby:  $modernStandby"
        Write-Host "Plano ativo:     $plan"
        Write-Host ""

        Write-Host "GPUs detectadas:" -ForegroundColor $global:ColorWarn
        foreach ($gpu in $gpus) {
            Write-Host " - $($gpu.Name) | Driver: $($gpu.DriverVersion)"
        }

        Write-Host ""
        Write-Host "Log atual: $global:LogFile" -ForegroundColor $global:ColorSoft
    }
    catch {
        Write-ErrL "Falha ao coletar informacoes do sistema."
    }

    Pause-Lynext
}

# ============================================
# BACKUP
# ============================================

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

function Backup-CurrentState {
    $data = @{
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
            DefaultPowerLimit = $null
        }
    }

    $nvidiaSmi = Get-NvidiaSmiPath
    if ($nvidiaSmi) {
        try {
            $pl = & $nvidiaSmi --query-gpu=power.default_limit --format=csv,noheader,nounits 2>$null
            if ($pl) {
                $plText = ($pl | Select-Object -First 1).ToString().Trim()
                if ($plText -match '^\d+(\.\d+)?$') {
                    $data.Nvidia.DefaultPowerLimit = [double]$plText
                }
            }
        }
        catch {}
    }

    Save-Json -Path $global:BackupFile -Data $data
    Write-Ok "Backup salvo em $global:BackupFile"
    Write-LogLine "Backup salvo"
}

function Ensure-BackupExists {
    if (-not (Test-Path $global:BackupFile)) {
        Backup-CurrentState
    }
}

# ============================================
# POWERCFG
# ============================================

function Set-PowerValueSafe {
    param(
        [string]$Subgroup,
        [string]$Setting,
        [int]$AcValue,
        [int]$DcValue
    )

    $ok = $true

    try { powercfg /setacvalueindex scheme_current $Subgroup $Setting $AcValue | Out-Null } catch { $ok = $false }
    try { powercfg /setdcvalueindex scheme_current $Subgroup $Setting $DcValue | Out-Null } catch { $ok = $false }
    try { powercfg /setactive scheme_current | Out-Null } catch { $ok = $false }

    if ($ok) {
        Write-Ok "$Setting aplicado (AC=$AcValue / DC=$DcValue)"
        Write-LogLine "POWER $Setting AC=$AcValue DC=$DcValue"
    }
    else {
        Write-WarnL "$Setting nao suportado ou indisponivel neste sistema."
        Write-LogLine "POWER SKIP $Setting"
    }
}

function Set-BalancedPlan {
    powercfg /setactive SCHEME_BALANCED | Out-Null
    Write-LogLine "Plano Balanceado ativado"
}

function Set-HighPerformancePlan {
    powercfg /setactive SCHEME_MIN | Out-Null
    Write-LogLine "Plano Alto Desempenho ativado"
}

function Try-UltimatePerformance {
    try {
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $result = powercfg -duplicatescheme $guid 2>&1 | Out-String

        if ($result -match '([a-fA-F0-9-]{36})') {
            $newGuid = $Matches[1]
            powercfg /changename $newGuid "Lynext Ultra Performance" | Out-Null
            powercfg /setactive $newGuid | Out-Null
            Write-LogLine "Plano Lynext Ultra Performance criado/ativado"
            return $true
        }
    }
    catch {}

    return $false
}

function Ensure-LitePlan {
    try {
        $list = powercfg /list | Out-String
        $match = [regex]::Match($list, '([a-fA-F0-9-]{36}).*Lynext Lite')

        if ($match.Success) {
            return $match.Groups[1].Value
        }

        $dup = powercfg -duplicatescheme SCHEME_BALANCED 2>&1 | Out-String
        if ($dup -match '([a-fA-F0-9-]{36})') {
            $guid = $Matches[1]
            powercfg /changename $guid "Lynext Lite" | Out-Null
            Write-LogLine "Plano Lynext Lite criado"
            return $guid
        }
    }
    catch {}

    return $null
}

function Activate-LitePlan {
    $guid = Ensure-LitePlan
    if ($guid) {
        powercfg /setactive $guid | Out-Null
        Write-LogLine "Plano Lynext Lite ativado"
        return $true
    }

    return $false
}

# ============================================
# CPU
# ============================================

function Apply-CPUUltra {
    param([switch]$Silent)

    if (-not $Silent) { Show-Header "CPU - ULTRA PERFORMANCE" }
    Ensure-BackupExists

    $modern = Test-ModernStandby
    $isLaptop = Get-IsLaptop

    if ($modern) {
        Write-WarnL "Modern Standby detectado. Vou manter plano compativel."
        Set-BalancedPlan
    }
    else {
        $ok = Try-UltimatePerformance
        if ($ok) {
            Write-Ok "Ultimate/Lynext Ultra ativado."
        }
        else {
            Set-HighPerformancePlan
            Write-WarnL "Ultimate indisponivel. Usando High Performance."
        }
    }

    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PROCTHROTTLEMIN"    -AcValue 100 -DcValue 50
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PROCTHROTTLEMAX"    -AcValue 100 -DcValue 100
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFEPP"            -AcValue 0   -DcValue 15
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFBOOSTMODE"      -AcValue 2   -DcValue 1
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "CPMINCORES"         -AcValue 100 -DcValue 50
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1   -DcValue 1
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "SYSCOOLPOL"         -AcValue 1   -DcValue 1

    if ($isLaptop) {
        Write-WarnL "Notebook detectado. Esse modo pode esquentar mais."
    }

    if (-not $Silent) { Pause-Lynext }
}

function Apply-CPULite {
    param([switch]$Silent)

    if (-not $Silent) { Show-Header "CPU - LYNEXT LITE" }
    Ensure-BackupExists

    $modern = Test-ModernStandby
    $isLaptop = Get-IsLaptop

    if ($modern -or $isLaptop) {
        Set-BalancedPlan
        Write-Ok "Balanced mantido por compatibilidade."
    }
    else {
        $liteOk = Activate-LitePlan
        if ($liteOk) {
            Write-Ok "Plano Lynext Lite ativado."
        }
        else {
            Set-BalancedPlan
            Write-WarnL "Nao consegui ativar Lynext Lite. Usando Balanced."
        }
    }

    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PROCTHROTTLEMIN"    -AcValue 5   -DcValue 5
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PROCTHROTTLEMAX"    -AcValue 100 -DcValue 100
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFEPP"            -AcValue 25  -DcValue 40
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFBOOSTMODE"      -AcValue 1   -DcValue 1
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "CPMINCORES"         -AcValue 50  -DcValue 25
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1   -DcValue 1
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "SYSCOOLPOL"         -AcValue 1   -DcValue 1

    if (-not $Silent) { Pause-Lynext }
}

function Apply-CPUThermal {
    Show-Header "CPU - TERMICO / QUIETO"
    Ensure-BackupExists

    Set-BalancedPlan
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PROCTHROTTLEMIN"    -AcValue 5  -DcValue 5
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PROCTHROTTLEMAX"    -AcValue 99 -DcValue 99
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFEPP"            -AcValue 60 -DcValue 80
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFBOOSTMODE"      -AcValue 0  -DcValue 0
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "CPMINCORES"         -AcValue 25 -DcValue 10
    Set-PowerValueSafe -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1  -DcValue 1

    Pause-Lynext
}

# ============================================
# WINDOWS
# ============================================

function Set-GameMode {
    param([string]$Mode)

    if ($Mode -eq "On") {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 | Out-Null
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode"  -Value 1 | Out-Null
    }
    else {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 0 | Out-Null
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode"  -Value 0 | Out-Null
    }
}

function Set-GameDVR {
    param([string]$Mode)

    if ($Mode -eq "On") {
        Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 1 | Out-Null
        Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 | Out-Null
    }
    else {
        Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 | Out-Null
        Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 | Out-Null
    }
}

function Set-Hags {
    param([string]$Mode)

    if ($Mode -eq "On") {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 | Out-Null
    }
    elseif ($Mode -eq "Off") {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 1 | Out-Null
    }
    else {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 0 | Out-Null
    }
}

function Set-PerfRegistryUltra {
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xffffffff | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 10 | Out-Null
    Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value 1 | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority" -Value 8 | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Value 6 | Out-Null
}

function Set-PerfRegistryLite {
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 10 | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 20 | Out-Null
    Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value 1 | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "GPU Priority" -Value 8 | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Name "Priority" -Value 6 | Out-Null
}

function Apply-WindowsUltra {
    param([switch]$Silent)

    if (-not $Silent) { Show-Header "WINDOWS - ULTRA PERFORMANCE" }
    Ensure-BackupExists

    Set-GameMode -Mode "On"
    Set-GameDVR -Mode "Off"
    Set-Hags -Mode "On"
    Set-PerfRegistryUltra

    Write-Ok "Game Mode ON"
    Write-Ok "Game DVR OFF"
    Write-Ok "HAGS ON"
    Write-Ok "Tweaks de latencia aplicados"

    if (-not $Silent) {
        Write-WarnL "Visual effects e VBS ficaram manuais por seguranca."
        Pause-Lynext
    }
}

function Apply-WindowsLite {
    param([switch]$Silent)

    if (-not $Silent) { Show-Header "WINDOWS - LYNEXT LITE" }
    Ensure-BackupExists

    Set-GameMode -Mode "On"
    Set-GameDVR -Mode "Off"
    Set-Hags -Mode "On"
    Set-PerfRegistryLite

    Write-Ok "Game Mode ON"
    Write-Ok "Game DVR OFF"
    Write-Ok "HAGS ON"
    Write-Ok "Tweaks leves aplicados"

    if (-not $Silent) { Pause-Lynext }
}

function Reset-WindowsFromBackup {
    Show-Header "WINDOWS - RESET"
    $backup = Load-Json -Path $global:BackupFile

    if (-not $backup) {
        Write-ErrL "Backup nao encontrado."
        Pause-Lynext
        return
    }

    if ($null -ne $backup.Registry.AutoGameModeEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value ([UInt32]$backup.Registry.AutoGameModeEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.AllowAutoGameMode) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value ([UInt32]$backup.Registry.AllowAutoGameMode) | Out-Null
    }

    if ($null -ne $backup.Registry.AppCaptureEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value ([UInt32]$backup.Registry.AppCaptureEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.GameDVR_Enabled) {
        Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value ([UInt32]$backup.Registry.GameDVR_Enabled) | Out-Null
    }

    if ($null -ne $backup.Registry.HwSchMode) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value ([UInt32]$backup.Registry.HwSchMode) | Out-Null
    }

    if ($null -ne $backup.Registry.SystemResponsiveness) {
        Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value ([UInt32]$backup.Registry.SystemResponsiveness) | Out-Null
    }

    if ($null -ne $backup.Registry.PowerThrottlingOff) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value ([UInt32]$backup.Registry.PowerThrottlingOff) | Out-Null
    }

    if ($null -ne $backup.Registry.NetworkThrottlingIndex) {
        try {
            $v = [UInt32]$backup.Registry.NetworkThrottlingIndex
            Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value $v | Out-Null
        }
        catch {
            Remove-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" | Out-Null
        }
    }

    Write-Ok "Windows restaurado pelo backup."
    Pause-Lynext
}

# ============================================
# REDE / NIC
# ============================================

function Get-ActiveNics {
    try {
        return Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" }
    }
    catch {
        return @()
    }
}

function Select-Nic {
    $nics = Get-ActiveNics

    if (-not $nics -or $nics.Count -eq 0) {
        Write-WarnL "Nenhuma NIC ativa encontrada."
        Pause-Lynext
        return $null
    }

    $i = 1
    foreach ($nic in $nics) {
        Write-Host "[$i] $($nic.Name)"
        $i++
    }

    Write-Host "[0] Voltar"
    Write-Host ""

    $choice = Read-Host "Escolha"
    if ($choice -eq "0") { return $null }

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $nics.Count) {
            return $nics[$idx]
        }
    }

    return $null
}

function Enable-RSS {
    Show-Header "NIC - RSS ON"
    $nic = Select-Nic
    if (-not $nic) { return }

    try {
        Enable-NetAdapterRss -Name $nic.Name -ErrorAction Stop
        Write-Ok "RSS habilitado em $($nic.Name)"
    }
    catch {
        Write-ErrL "Falha ao habilitar RSS."
    }

    Pause-Lynext
}

function Disable-InterruptModeration {
    Show-Header "NIC - INTERRUPT MODERATION OFF"
    $nic = Select-Nic
    if (-not $nic) { return }

    try {
        Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Interrupt Moderation" -DisplayValue "Disabled" -ErrorAction Stop
        Write-Ok "Interrupt Moderation desativado em $($nic.Name)"
    }
    catch {
        Write-ErrL "Falha ao alterar a propriedade. O nome pode variar pelo driver."
    }

    Pause-Lynext
}

function Reset-InterruptModeration {
    Show-Header "NIC - RESET INTERRUPT MODERATION"
    $nic = Select-Nic
    if (-not $nic) { return }

    try {
        Reset-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Interrupt Moderation" -ErrorAction Stop
        Write-Ok "Interrupt Moderation resetado em $($nic.Name)"
    }
    catch {
        Write-ErrL "Falha ao resetar a propriedade."
    }

    Pause-Lynext
}

function Disable-LSO {
    Show-Header "NIC - LSO OFF"
    $nic = Select-Nic
    if (-not $nic) { return }

    try {
        Disable-NetAdapterLso -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
        Write-Ok "LSO desativado em $($nic.Name)"
    }
    catch {
        Write-ErrL "Falha ao desativar LSO."
    }

    Pause-Lynext
}

function Enable-LSO {
    Show-Header "NIC - LSO ON"
    $nic = Select-Nic
    if (-not $nic) { return }

    try {
        Enable-NetAdapterLso -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
        Write-Ok "LSO habilitado em $($nic.Name)"
    }
    catch {
        Write-ErrL "Falha ao habilitar LSO."
    }

    Pause-Lynext
}

# ============================================
# NVIDIA
# ============================================

function Show-NvidiaSupportInfo {
    Show-Header "NVIDIA - SUPORTE"

    if ((Get-GpuVendor) -ne "NVIDIA") {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-WarnL "nvidia-smi nao encontrado."
        Pause-Lynext
        return
    }

    try {
        & $nvidiaSmi -q -d POWER,CLOCK
    }
    catch {
        Write-ErrL "Falha ao consultar nvidia-smi."
    }

    Pause-Lynext
}

function Set-NvidiaPowerLimit {
    param([double]$Watts)

    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-ErrL "nvidia-smi nao encontrado."
        return
    }

    try {
        & $nvidiaSmi -pl $Watts | Out-Null
        Write-Ok "Power limit ajustado para $Watts W"
        Write-LogLine "NVIDIA power limit = $Watts W"
    }
    catch {
        Write-ErrL "Falha ao ajustar power limit."
    }
}

function Reset-NvidiaClocks {
    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-ErrL "nvidia-smi nao encontrado."
        return
    }

    try {
        & $nvidiaSmi -rgc | Out-Null
        Write-Ok "Clocks resetados."
        Write-LogLine "NVIDIA clocks resetados"
    }
    catch {
        Write-WarnL "Sua GPU/driver pode nao suportar reset de clocks por nvidia-smi."
    }
}

function Lock-NvidiaClocks {
    Show-Header "NVIDIA - LOCK CLOCKS"

    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-ErrL "nvidia-smi nao encontrado."
        Pause-Lynext
        return
    }

    $min = Read-Host "Clock minimo"
    $max = Read-Host "Clock maximo"

    if (($min -match '^\d+$') -and ($max -match '^\d+$')) {
        try {
            & $nvidiaSmi -lgc "$min,$max" | Out-Null
            Write-Ok "Clocks travados em $min,$max"
            Write-LogLine "NVIDIA clocks travados $min,$max"
        }
        catch {
            Write-ErrL "Falha ao travar clocks."
        }
    }
    else {
        Write-WarnL "Valores invalidos."
    }

    Pause-Lynext
}

function Apply-NvidiaUltra {
    param([switch]$Silent)

    if (-not $Silent) { Show-Header "NVIDIA - ULTRA PERFORMANCE" }
    Ensure-BackupExists

    if ((Get-GpuVendor) -ne "NVIDIA") {
        Write-WarnL "GPU NVIDIA nao detectada."
        if (-not $Silent) { Pause-Lynext }
        return
    }

    Write-Section "Politica sugerida"
    Write-Host "- Prefer maximum performance"
    Write-Host "- Low Latency Ultra somente se o jogo NAO tiver Reflex"
    Write-Host "- Highest refresh rate"
    Write-Host "- Texture filtering: High performance"
    Write-Host "- DLSS ON quando fizer sentido"

    $nvidiaSmi = Get-NvidiaSmiPath
    if ($nvidiaSmi) {
        try {
            $limits = & $nvidiaSmi --query-gpu=power.min_limit,power.max_limit,power.default_limit --format=csv,noheader,nounits 2>$null
            if ($limits) {
                $parts = ($limits | Select-Object -First 1).ToString().Split(",") | ForEach-Object { $_.Trim() }
                if ($parts.Count -ge 2) {
                    $max = [double]$parts[1]
                    Set-NvidiaPowerLimit -Watts $max
                }
            }
        }
        catch {
            Write-WarnL "Nao consegui puxar limites de energia automaticamente."
        }
    }
    else {
        Write-WarnL "nvidia-smi nao encontrado. Sem power limit automatico."
    }

    if (-not $Silent) { Pause-Lynext }
}

function Apply-NvidiaLite {
    param([switch]$Silent)

    if (-not $Silent) { Show-Header "NVIDIA - LYNEXT LITE" }
    Ensure-BackupExists

    if ((Get-GpuVendor) -ne "NVIDIA") {
        Write-WarnL "GPU NVIDIA nao detectada."
        if (-not $Silent) { Pause-Lynext }
        return
    }

    Write-Section "Politica sugerida"
    Write-Host "- Optimal / Driver controlled"
    Write-Host "- Low Latency ON"
    Write-Host "- Highest refresh rate"
    Write-Host "- Sem forcar clocks agressivos"

    $nvidiaSmi = Get-NvidiaSmiPath
    if ($nvidiaSmi) {
        try {
            $defaults = Load-Json -Path $global:BackupFile
            if ($defaults -and $defaults.Nvidia.DefaultPowerLimit) {
                Set-NvidiaPowerLimit -Watts ([double]$defaults.Nvidia.DefaultPowerLimit)
            }
            else {
                Write-WarnL "Sem power limit padrao salvo."
            }
        }
        catch {
            Write-WarnL "Nao consegui restaurar o power limit salvo."
        }
    }

    if (-not $Silent) { Pause-Lynext }
}

function Reset-NvidiaFromBackup {
    Show-Header "NVIDIA - RESET"
    $backup = Load-Json -Path $global:BackupFile

    if ((Get-GpuVendor) -ne "NVIDIA") {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    Reset-NvidiaClocks

    if ($backup -and $backup.Nvidia -and $backup.Nvidia.DefaultPowerLimit) {
        Set-NvidiaPowerLimit -Watts ([double]$backup.Nvidia.DefaultPowerLimit)
    }
    else {
        Write-WarnL "Power limit padrao nao encontrado no backup."
    }

    Write-WarnL "Os ajustes do painel NVIDIA devem voltar ao padrao manualmente."
    Pause-Lynext
}

# ============================================
# AMD / INTEL
# ============================================

function Show-AmdInfo {
    Show-Header "AMD - INFORMACOES"

    if ((Get-GpuVendor) -ne "AMD") {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    try {
        Get-CimInstance Win32_VideoController |
            Where-Object { $_.Name -match "AMD|Radeon" } |
            Select-Object Name, DriverVersion, VideoProcessor |
            Format-List
    }
    catch {
        Write-ErrL "Falha ao coletar informacoes AMD."
    }

    Pause-Lynext
}

function Show-IntelInfo {
    Show-Header "INTEL - INFORMACOES"

    if ((Get-GpuVendor) -ne "Intel") {
        Write-WarnL "GPU Intel nao detectada."
        Pause-Lynext
        return
    }

    try {
        Get-CimInstance Win32_VideoController |
            Where-Object { $_.Name -match "Intel" } |
            Select-Object Name, DriverVersion, VideoProcessor |
            Format-List
    }
    catch {
        Write-ErrL "Falha ao coletar informacoes Intel."
    }

    Pause-Lynext
}

# ============================================
# FULL MODES
# ============================================

function Confirm-AggressiveMode {
    Show-Header "CONFIRMACAO - ULTRA"
    Write-WarnL "O modo Ultra e agressivo."
    Write-WarnL "Pode aumentar temperatura, consumo e ruido."
    Write-Host ""
    $confirm = Read-Host "Digite SIM para continuar"
    return ($confirm -eq "SIM")
}

function Apply-LynextUltraFull {
    if (-not (Confirm-AggressiveMode)) {
        return
    }

    Show-Header "LYNEXT ULTRA PERFORMANCE"
    Backup-CurrentState

    Write-Section "CPU"
    Apply-CPUUltra -Silent

    Write-Section "WINDOWS"
    Apply-WindowsUltra -Silent

    if ((Get-GpuVendor) -eq "NVIDIA") {
        Write-Section "NVIDIA"
        Apply-NvidiaUltra -Silent
    }
    else {
        Write-Section "GPU"
        Write-WarnL "Ajuste automatico agressivo de GPU foi mantido focado em NVIDIA por enquanto."
    }

    Write-Section "FINAL"
    Write-Ok "Lynext Ultra Performance concluido."
    Write-WarnL "Reinicie o PC se quiser aplicar tudo de forma mais limpa, especialmente HAGS."
    Pause-Lynext
}

function Apply-LynextLiteFull {
    Show-Header "LYNEXT LITE"
    Backup-CurrentState

    Write-Section "CPU"
    Apply-CPULite -Silent

    Write-Section "WINDOWS"
    Apply-WindowsLite -Silent

    if ((Get-GpuVendor) -eq "NVIDIA") {
        Write-Section "NVIDIA"
        Apply-NvidiaLite -Silent
    }
    else {
        Write-Section "GPU"
        Write-Info "Modo Lite aplicado no sistema. GPU fica mais guiada/manual fora de NVIDIA por enquanto."
    }

    Write-Section "FINAL"
    Write-Ok "Lynext Lite concluido."
    Pause-Lynext
}

function Reset-AllFromBackup {
    Show-Header "RESET GERAL"

    $backup = Load-Json -Path $global:BackupFile
    if (-not $backup) {
        Write-ErrL "Backup nao encontrado."
        Pause-Lynext
        return
    }

    try {
        if ($backup.PowerSchemeGuid) {
            powercfg /setactive $backup.PowerSchemeGuid | Out-Null
            Write-Ok "Plano de energia restaurado."
        }
        else {
            Set-BalancedPlan
            Write-WarnL "GUID do plano nao encontrado. Voltando para Balanced."
        }
    }
    catch {
        Set-BalancedPlan
        Write-WarnL "Falha ao restaurar GUID exato. Voltando para Balanced."
    }

    $oldPause = $global:BackupPauseHack
    $global:BackupPauseHack = $true
    Reset-WindowsFromBackup
    $global:BackupPauseHack = $oldPause

    if ((Get-GpuVendor) -eq "NVIDIA") {
        $backupNv = Load-Json -Path $global:BackupFile
        Reset-NvidiaClocks
        if ($backupNv -and $backupNv.Nvidia -and $backupNv.Nvidia.DefaultPowerLimit) {
            Set-NvidiaPowerLimit -Watts ([double]$backupNv.Nvidia.DefaultPowerLimit)
        }
    }

    Write-Ok "Reset geral concluido."
    Write-WarnL "Reinicie o PC se voce mexeu em HAGS."
    Pause-Lynext
}

# Evita pausa dupla no Reset-WindowsFromBackup quando chamado por Reset-AllFromBackup
Set-Item -Path Function:\Reset-WindowsFromBackup -Value {
    Show-Header "WINDOWS - RESET"
    $backup = Load-Json -Path $global:BackupFile

    if (-not $backup) {
        Write-ErrL "Backup nao encontrado."
        if (-not $global:BackupPauseHack) { Pause-Lynext }
        return
    }

    if ($null -ne $backup.Registry.AutoGameModeEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value ([UInt32]$backup.Registry.AutoGameModeEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.AllowAutoGameMode) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value ([UInt32]$backup.Registry.AllowAutoGameMode) | Out-Null
    }

    if ($null -ne $backup.Registry.AppCaptureEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value ([UInt32]$backup.Registry.AppCaptureEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.GameDVR_Enabled) {
        Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value ([UInt32]$backup.Registry.GameDVR_Enabled) | Out-Null
    }

    if ($null -ne $backup.Registry.HwSchMode) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value ([UInt32]$backup.Registry.HwSchMode) | Out-Null
    }

    if ($null -ne $backup.Registry.SystemResponsiveness) {
        Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value ([UInt32]$backup.Registry.SystemResponsiveness) | Out-Null
    }

    if ($null -ne $backup.Registry.PowerThrottlingOff) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value ([UInt32]$backup.Registry.PowerThrottlingOff) | Out-Null
    }

    if ($null -ne $backup.Registry.NetworkThrottlingIndex) {
        try {
            $v = [UInt32]$backup.Registry.NetworkThrottlingIndex
            Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value $v | Out-Null
        }
        catch {
            Remove-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" | Out-Null
        }
    }

    Write-Ok "Windows restaurado pelo backup."
    if (-not $global:BackupPauseHack) { Pause-Lynext }
}

# ============================================
# MENUS
# ============================================

function Menu-CPU {
    do {
        Show-Header "CPU / ENERGIA"
        Write-Host "[1] Lynext Ultra Performance"
        Write-Host "[2] Lynext Lite"
        Write-Host "[3] Termico / Quieto"
        Write-Host "[0] Voltar"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice) {
            "1" { Apply-CPUUltra }
            "2" { Apply-CPULite }
            "3" { Apply-CPUThermal }
            "0" { return }
            default {
                Write-WarnL "Opcao invalida."
                Pause-Lynext
            }
        }
    } while ($true)
}

function Menu-Windows {
    do {
        Show-Header "WINDOWS / JOGOS"
        Write-Host "[1] Windows Ultra"
        Write-Host "[2] Windows Lite"
        Write-Host "[3] Reset pelo backup"
        Write-Host "[4] HAGS ON"
        Write-Host "[5] HAGS OFF"
        Write-Host "[0] Voltar"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice) {
            "1" { Apply-WindowsUltra }
            "2" { Apply-WindowsLite }
            "3" { Reset-WindowsFromBackup }
            "4" {
                Show-Header "HAGS ON"
                Ensure-BackupExists
                Set-Hags -Mode "On"
                Write-Ok "HAGS ON aplicado."
                Write-WarnL "Pode exigir reinicio."
                Pause-Lynext
            }
            "5" {
                Show-Header "HAGS OFF"
                Ensure-BackupExists
                Set-Hags -Mode "Off"
                Write-Ok "HAGS OFF aplicado."
                Write-WarnL "Pode exigir reinicio."
                Pause-Lynext
            }
            "0" { return }
            default {
                Write-WarnL "Opcao invalida."
                Pause-Lynext
            }
        }
    } while ($true)
}

function Menu-Network {
    do {
        Show-Header "REDE / LATENCIA"
        Write-Host "[1] RSS ON"
        Write-Host "[2] Interrupt Moderation OFF"
        Write-Host "[3] Reset Interrupt Moderation"
        Write-Host "[4] LSO OFF"
        Write-Host "[5] LSO ON"
        Write-Host "[0] Voltar"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice) {
            "1" { Enable-RSS }
            "2" { Disable-InterruptModeration }
            "3" { Reset-InterruptModeration }
            "4" { Disable-LSO }
            "5" { Enable-LSO }
            "0" { return }
            default {
                Write-WarnL "Opcao invalida."
                Pause-Lynext
            }
        }
    } while ($true)
}

function Menu-Nvidia {
    do {
        Show-Header "NVIDIA"
        Write-Host "[1] Mostrar suporte / estado"
        Write-Host "[2] Ultra Performance"
        Write-Host "[3] Lynext Lite"
        Write-Host "[4] Travar clocks manualmente"
        Write-Host "[5] Reset NVIDIA"
        Write-Host "[0] Voltar"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice) {
            "1" { Show-NvidiaSupportInfo }
            "2" { Apply-NvidiaUltra }
            "3" { Apply-NvidiaLite }
            "4" { Lock-NvidiaClocks }
            "5" { Reset-NvidiaFromBackup }
            "0" { return }
            default {
                Write-WarnL "Opcao invalida."
                Pause-Lynext
            }
        }
    } while ($true)
}

function Menu-Backup {
    do {
        Show-Header "BACKUP / RESET"
        Write-Host "[1] Criar / atualizar backup"
        Write-Host "[2] Mostrar caminho do backup"
        Write-Host "[3] Reset geral pelo backup"
        Write-Host "[0] Voltar"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice) {
            "1" {
                Show-Header "BACKUP"
                Backup-CurrentState
                Pause-Lynext
            }
            "2" {
                Show-Header "CAMINHOS"
                Write-Host "Backup: $global:BackupFile" -ForegroundColor $global:ColorWarn
                Write-Host "Log:    $global:LogFile" -ForegroundColor $global:ColorWarn
                Pause-Lynext
            }
            "3" { Reset-AllFromBackup }
            "0" { return }
            default {
                Write-WarnL "Opcao invalida."
                Pause-Lynext
            }
        }
    } while ($true)
}

function Menu-Main {
    do {
        Show-Header "PERFORMANCE APP"
        Write-Host "[1] Aplicar Lynext Ultra Performance"
        Write-Host "[2] Aplicar Lynext Lite"
        Write-Host "[3] CPU / Energia"
        Write-Host "[4] Windows / Jogos"
        Write-Host "[5] Rede / Latencia"
        Write-Host "[6] NVIDIA"
        Write-Host "[7] AMD"
        Write-Host "[8] Intel"
        Write-Host "[9] Resumo do sistema"
        Write-Host "[B] Backup / Reset"
        Write-Host "[0] Sair"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice.ToUpper()) {
            "1" { Apply-LynextUltraFull }
            "2" { Apply-LynextLiteFull }
            "3" { Menu-CPU }
            "4" { Menu-Windows }
            "5" { Menu-Network }
            "6" { Menu-Nvidia }
            "7" { Show-AmdInfo }
            "8" { Show-IntelInfo }
            "9" { Show-SystemSummary }
            "B" { Menu-Backup }
            "0" { return }
            default {
                Write-WarnL "Opcao invalida."
                Pause-Lynext
            }
        }
    } while ($true)
}

# ============================================
# START
# ============================================

Ensure-Admin
Menu-Main
