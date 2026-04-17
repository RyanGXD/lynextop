# ============================================
# LYNEXT - PerformanceApp.ps1
# Versao corrigida e mais estavel
# ============================================

$Host.UI.RawUI.WindowTitle = "Lynext - Performance App"

# ============================================
# PATHS
# ============================================

$global:LynextRoot = Join-Path $env:ProgramData "Lynext"
$global:BackupFile = Join-Path $global:LynextRoot "performance_backup.json"

if (-not (Test-Path $global:LynextRoot)) {
    New-Item -Path $global:LynextRoot -ItemType Directory -Force | Out-Null
}

# ============================================
# UI
# ============================================

function Pause-Lynext {
    Write-Host ""
    Read-Host "Pressione ENTER para continuar" | Out-Null
}

function Show-Header {
    param(
        [string]$Title = "PERFORMANCE APP"
    )

    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                        L Y N E X T" -ForegroundColor Cyan
    Write-Host "                    $Title" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Ok {
    param([string]$Text)
    Write-Host "[OK]   $Text" -ForegroundColor Green
}

function Write-WarnL {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Write-ErrL {
    param([string]$Text)
    Write-Host "[ERRO] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Cyan
}

# ============================================
# ADMIN
# ============================================

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LynextPowerShellPath {
    $systemPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $systemPowerShell) {
        return $systemPowerShell
    }

    return "powershell.exe"
}

function Ensure-Admin {
    if (-not (Test-IsAdministrator)) {
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

        if ($scriptPath) {
            Start-Process (Get-LynextPowerShellPath) -Verb RunAs -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $scriptPath
            ) | Out-Null
            exit
        }

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

    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Load-Json {
    param(
        [string]$Path
    )

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
        [object]$Value
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        $normalized = Convert-ToRegDwordValue -Value $Value
        $current = Get-RegValue -Path $Path -Name $Name

        if ($null -eq $current -or [uint32]$current -ne $normalized) {
            New-ItemProperty -Path $Path -Name $Name -Value ([uint32]$normalized) -PropertyType DWord -Force | Out-Null
        }

        return $true
    }
    catch {
        Write-ErrL "Falha ao alterar registro: $Path -> $Name"
        return $false
    }
}

function Convert-ToRegDwordValue {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($null -eq $Value) {
        throw "Valor nulo nao pode ser convertido para DWORD."
    }

    if ($Value -is [uint32]) {
        return $Value
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [sbyte]) {
        if ([int64]$Value -lt 0) {
            return [uint32]([int64]$Value -band 0xffffffffL)
        }

        return [uint32]$Value
    }

    if ($Value -is [string]) {
        $text = $Value.Trim()

        if ($text -match '^0x[0-9a-fA-F]+$') {
            return [uint32]::Parse($text.Substring(2), [System.Globalization.NumberStyles]::HexNumber)
        }

        if ($text -match '^[0-9a-fA-F]+h$') {
            return [uint32]::Parse($text.Substring(0, $text.Length - 1), [System.Globalization.NumberStyles]::HexNumber)
        }

        if ($text -match '^-?\d+$') {
            $parsed = [int64]$text
            if ($parsed -lt 0) {
                return [uint32]($parsed -band 0xffffffffL)
            }

            return [uint32]$parsed
        }
    }

    return [uint32]$Value
}

function Remove-RegValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        if (Test-Path $Path) {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
        }

        return $true
    }
    catch {
        Write-WarnL "Nao consegui remover $Name em $Path"
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

        Write-Host "Windows:         $($os.Caption) build $($os.BuildNumber)"
        Write-Host "CPU:             $($cpu.Name)"
        Write-Host "GPU vendor:      $(Get-GpuVendor)"
        Write-Host "Notebook:        $isLaptop"
        Write-Host "Modern Standby:  $modernStandby"
        Write-Host ""
        Write-Host "GPUs detectadas:" -ForegroundColor Yellow

        foreach ($gpu in $gpus) {
            Write-Host " - $($gpu.Name) | Driver: $($gpu.DriverVersion)"
        }
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
            AutoGameModeEnabled = Get-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled"
            AllowAutoGameMode   = Get-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode"
            AppCaptureEnabled   = Get-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled"
            GameDVR_Enabled     = Get-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled"
            HwSchMode           = Get-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode"
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
}

function Ensure-BackupExists {
    if (-not (Test-Path $global:BackupFile)) {
        Backup-CurrentState
    }
}

# ============================================
# POWERCFG
# ============================================

function Set-PowerValue {
    param(
        [string]$Subgroup,
        [string]$Setting,
        [int]$AcValue,
        [int]$DcValue
    )

    $acOk = Invoke-PowerCfgSafe -Arguments @('/setacvalueindex', 'scheme_current', $Subgroup, $Setting, $AcValue) -Context "$Setting (AC)"
    $dcOk = Invoke-PowerCfgSafe -Arguments @('/setdcvalueindex', 'scheme_current', $Subgroup, $Setting, $DcValue) -Context "$Setting (DC)"

    if ($acOk -or $dcOk) {
        Invoke-PowerCfgSafe -Arguments @('/setactive', 'scheme_current') -Context "ativar plano atual" | Out-Null
    }
}

function Set-BalancedPlan {
    Invoke-PowerCfgSafe -Arguments @('/setactive', 'SCHEME_BALANCED') -Context "ativar Balanced" | Out-Null
}

function Set-HighPerformancePlan {
    Invoke-PowerCfgSafe -Arguments @('/setactive', 'SCHEME_MAX') -Context "ativar High Performance" | Out-Null
}

function Try-UltimatePerformance {
    try {
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $result = powercfg -duplicatescheme $guid 2>&1 | Out-String

        if ($result -match '([a-fA-F0-9-]{36})') {
            $newGuid = $Matches[1]
            return (Invoke-PowerCfgSafe -Arguments @('/setactive', $newGuid) -Context "ativar Ultimate Performance")
        }
    }
    catch {}

    return $false
}

function Invoke-PowerCfgSafe {
    param(
        [string[]]$Arguments,
        [string]$Context = "powercfg"
    )

    try {
        $output = & powercfg @Arguments 2>&1 | Out-String
        $hasInvalidParameters = $output -match 'Invalid Parameters'
        $hasErrorText = $output -match 'Unable to|cannot|failed|error'

        if ($LASTEXITCODE -ne 0 -or $hasInvalidParameters -or $hasErrorText) {
            $details = $output.Trim()
            if ($details) {
                Write-WarnL "powercfg ignorou '$Context': $details"
            }
            else {
                Write-WarnL "powercfg ignorou '$Context'."
            }

            return $false
        }

        return $true
    }
    catch {
        Write-WarnL "Falha ao executar powercfg em '$Context'."
        return $false
    }
}

# ============================================
# CPU
# ============================================

function Apply-CPUUltra {
    Show-Header "CPU - ULTRA PERFORMANCE"
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
            Write-Ok "Ultimate Performance ativado."
        }
        else {
            Set-HighPerformancePlan
            Write-WarnL "Ultimate indisponivel. Usando High Performance."
        }
    }

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFEPP" -AcValue 0 -DcValue 15
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFBOOSTMODE" -AcValue 2 -DcValue 1
    Set-PowerValue -Subgroup "sub_processor" -Setting "CPMINCORES" -AcValue 100 -DcValue 50
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1 -DcValue 1

    Write-Ok "Preset CPU Ultra aplicado."

    if ($isLaptop) {
        Write-WarnL "Notebook detectado. Esse modo pode esquentar mais."
    }

    Pause-Lynext
}

function Apply-CPUPerformance {
    Show-Header "CPU - PERFORMANCE"
    Ensure-BackupExists

    $modern = Test-ModernStandby
    $isLaptop = Get-IsLaptop

    if ($modern -or $isLaptop) {
        Set-BalancedPlan
        Write-Ok "Balanced mantido por compatibilidade."
    }
    else {
        Set-HighPerformancePlan
        Write-Ok "High Performance ativado."
    }

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFEPP" -AcValue 25 -DcValue 40
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFBOOSTMODE" -AcValue 4 -DcValue 3
    Set-PowerValue -Subgroup "sub_processor" -Setting "CPMINCORES" -AcValue 100 -DcValue 25
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1 -DcValue 1

    Write-Ok "Preset CPU Performance aplicado."
    Pause-Lynext
}

function Apply-CPUThermal {
    Show-Header "CPU - TERMICO / QUIETO"
    Ensure-BackupExists

    Set-BalancedPlan
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFEPP" -AcValue 60 -DcValue 80
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFBOOSTMODE" -AcValue 0 -DcValue 0
    Set-PowerValue -Subgroup "sub_processor" -Setting "CPMINCORES" -AcValue 25 -DcValue 10
    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1 -DcValue 1

    Write-Ok "Preset termico aplicado."
    Pause-Lynext
}

function Show-CPUEconomySkeleton {
    Show-Header "CPU - ECONOMIA (ESQUELETO)"
    Write-Host "Modo futuro reservado." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "- Plano Balanced"
    Write-Host "- EPP alto"
    Write-Host "- Boost mais conservador"
    Write-Host "- Core Parking mais agressivo"
    Pause-Lynext
}

# ============================================
# WINDOWS
# ============================================

function Set-GameMode {
    param([string]$Mode)

    if ($Mode -eq "On") {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 | Out-Null
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1 | Out-Null
    }
    else {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 0 | Out-Null
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 0 | Out-Null
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
    else {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 1 | Out-Null
    }

    Write-WarnL "Mudanca em HAGS pode exigir reinicializacao."
}

function Apply-WindowsUltra {
    Show-Header "WINDOWS - ULTRA PERFORMANCE"
    Ensure-BackupExists

    Set-GameMode -Mode "On"
    Set-GameDVR -Mode "Off"
    Set-Hags -Mode "On"
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xffffffff | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 10 | Out-Null
    Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value 1 | Out-Null

    Write-Ok "Game Mode ON"
    Write-Ok "Game DVR OFF"
    Write-Ok "HAGS ON"
    Write-Ok "NetworkThrottlingIndex = 0xffffffff"
    Write-WarnL "Visual Effects nao foram forcados por script."
    Pause-Lynext
}

function Apply-WindowsPerformance {
    Show-Header "WINDOWS - PERFORMANCE"
    Ensure-BackupExists

    Set-GameMode -Mode "On"
    Set-GameDVR -Mode "Off"
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 10 | Out-Null
    Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 20 | Out-Null
    Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value 1 | Out-Null

    Write-Ok "Game Mode ON"
    Write-Ok "Game DVR OFF"
    Write-WarnL "HAGS ficou manual nesse preset."
    Pause-Lynext
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
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value ([int]$backup.Registry.AutoGameModeEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.AllowAutoGameMode) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value $backup.Registry.AllowAutoGameMode | Out-Null
    }

    if ($null -ne $backup.Registry.AppCaptureEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value ([int]$backup.Registry.AppCaptureEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.GameDVR_Enabled) {
        Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value ([int]$backup.Registry.GameDVR_Enabled) | Out-Null
    }

    if ($null -ne $backup.Registry.HwSchMode) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value ([int]$backup.Registry.HwSchMode) | Out-Null
    }

    if ($null -ne $backup.Registry.SystemResponsiveness) {
        Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value $backup.Registry.SystemResponsiveness | Out-Null
    }

    if ($null -ne $backup.Registry.PowerThrottlingOff) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -Value $backup.Registry.PowerThrottlingOff | Out-Null
    }

    if ($null -ne $backup.Registry.NetworkThrottlingIndex) {
        Set-RegDword -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value $backup.Registry.NetworkThrottlingIndex | Out-Null
    }
    else {
        Remove-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" | Out-Null
    }

    Write-Ok "Windows restaurado pelo backup."
    Pause-Lynext
}

function Show-HagsHint {
    Show-Header "HAGS - CAMINHO OFICIAL"
    Write-Host "Configuracoes > Sistema > Tela > Graficos > Alterar configuracoes graficas padrao"
    Write-Host ""
    Write-Host "O script usa registro como fallback."
    Pause-Lynext
}

# ============================================
# REDE
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
    Show-Header "NVIDIA - ULTRA PERFORMANCE"
    Ensure-BackupExists

    if ((Get-GpuVendor) -ne "NVIDIA") {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica recomendada:" -ForegroundColor Yellow
    Write-Host "- Prefer maximum performance"
    Write-Host "- ULLM Ultra somente se o jogo NAO tiver Reflex"
    Write-Host "- Texture filtering: High performance"
    Write-Host "- Shader cache grande"
    Write-Host "- DLSS ON / RT baixo ou OFF"
    Write-Host ""

    $resp = Read-Host "Deseja aplicar power limit manual? (s/n)"
    if ($resp -match '^(s|S)$') {
        $watts = Read-Host "Digite o valor em Watts"
        if ($watts -match '^\d+(\.\d+)?$') {
            Set-NvidiaPowerLimit -Watts ([double]$watts)
        }
        else {
            Write-WarnL "Valor invalido."
        }
    }

    Pause-Lynext
}

function Apply-NvidiaPerformance {
    Show-Header "NVIDIA - PERFORMANCE"

    if ((Get-GpuVendor) -ne "NVIDIA") {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica recomendada:" -ForegroundColor Yellow
    Write-Host "- Adaptive / Driver controlled"
    Write-Host "- ULLM On, ou Off se houver Reflex"
    Write-Host "- Texture filtering: Performance"
    Write-Host "- DLSS Balanced/Quality"
    Write-Host "- RT moderado"
    Pause-Lynext
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
# AMD
# ============================================

function Apply-AmdUltra {
    Show-Header "AMD - ULTRA PERFORMANCE"

    if ((Get-GpuVendor) -ne "AMD") {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica recomendada AMD:" -ForegroundColor Yellow
    Write-Host "- Anti-Lag ON"
    Write-Host "- Chill OFF"
    Write-Host "- Boost ON"
    Write-Host "- Image Sharpening ON moderado"
    Write-Host "- Tessellation override reduzido"
    Write-Host "- Enhanced Sync somente se nao houver problemas"
    Write-Host "- RSR/FSR quando fizer sentido"
    Write-Host ""
    Write-WarnL "Automacao real da AMD idealmente deve usar helper com ADLX."
    Pause-Lynext
}

function Apply-AmdPerformance {
    Show-Header "AMD - PERFORMANCE"

    if ((Get-GpuVendor) -ne "AMD") {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica recomendada AMD:" -ForegroundColor Yellow
    Write-Host "- Anti-Lag ON"
    Write-Host "- Chill OFF"
    Write-Host "- Boost moderado ou OFF"
    Write-Host "- Image Sharpening leve/moderado"
    Write-Host "- Tessellation leve"
    Pause-Lynext
}

function Reset-AmdPolicy {
    Show-Header "AMD - RESET"

    if ((Get-GpuVendor) -ne "AMD") {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Reset recomendado AMD:" -ForegroundColor Yellow
    Write-Host "- Voltar os toggles no Adrenalin"
    Write-Host "- Se necessario, reinstalar driver limpo"
    Pause-Lynext
}

# ============================================
# GLOBAL RESET
# ============================================

function Reset-AllFromBackup {
    Show-Header "RESET GLOBAL"

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
    }
    catch {
        Write-ErrL "Falha ao restaurar plano de energia."
    }

    if ($null -ne $backup.Registry.AutoGameModeEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value ([int]$backup.Registry.AutoGameModeEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.AppCaptureEnabled) {
        Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value ([int]$backup.Registry.AppCaptureEnabled) | Out-Null
    }

    if ($null -ne $backup.Registry.GameDVR_Enabled) {
        Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value ([int]$backup.Registry.GameDVR_Enabled) | Out-Null
    }

    if ($null -ne $backup.Registry.HwSchMode) {
        Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value ([int]$backup.Registry.HwSchMode) | Out-Null
    }

    if ((Get-GpuVendor) -eq "NVIDIA") {
        Reset-NvidiaClocks

        if ($backup.Nvidia -and $backup.Nvidia.DefaultPowerLimit) {
            Set-NvidiaPowerLimit -Watts ([double]$backup.Nvidia.DefaultPowerLimit)
        }
    }

    Write-Ok "Rollback global aplicado."
    Write-WarnL "Reinicie o PC se voce mexeu em HAGS."
    Pause-Lynext
}

# ============================================
# MENUS
# ============================================

function Show-CPUMenu {
    do {
        Show-Header "CPU / ENERGIA"
        Write-Host "[1] Ultra Performance"
        Write-Host "[2] Performance"
        Write-Host "[3] Termico / Quieto"
        Write-Host "[4] Economia (esqueleto)"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Apply-CPUUltra }
            "2" { Apply-CPUPerformance }
            "3" { Apply-CPUThermal }
            "4" { Show-CPUEconomySkeleton }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

function Show-NvidiaMenu {
    do {
        Show-Header "NVIDIA"
        Write-Host "[1] Ultra Performance"
        Write-Host "[2] Performance"
        Write-Host "[3] Reset"
        Write-Host "[4] Consultar suporte / clocks / power"
        Write-Host "[5] Lock clocks manual"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Apply-NvidiaUltra }
            "2" { Apply-NvidiaPerformance }
            "3" { Reset-NvidiaFromBackup }
            "4" { Show-NvidiaSupportInfo }
            "5" { Lock-NvidiaClocks }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

function Show-AmdMenu {
    do {
        Show-Header "AMD"
        Write-Host "[1] Ultra Performance"
        Write-Host "[2] Performance"
        Write-Host "[3] Reset"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Apply-AmdUltra }
            "2" { Apply-AmdPerformance }
            "3" { Reset-AmdPolicy }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

function Show-WindowsMenu {
    do {
        Show-Header "WINDOWS / JOGOS"
        Write-Host "[1] Ultra Performance"
        Write-Host "[2] Performance"
        Write-Host "[3] Reset pelo backup"
        Write-Host "[4] HAGS ON"
        Write-Host "[5] HAGS OFF"
        Write-Host "[6] Caminho oficial HAGS"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Apply-WindowsUltra }
            "2" { Apply-WindowsPerformance }
            "3" { Reset-WindowsFromBackup }
            "4" {
                Ensure-BackupExists
                Show-Header "HAGS ON"
                Set-Hags -Mode "On"
                Pause-Lynext
            }
            "5" {
                Ensure-BackupExists
                Show-Header "HAGS OFF"
                Set-Hags -Mode "Off"
                Pause-Lynext
            }
            "6" { Show-HagsHint }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

function Show-NetworkMenu {
    do {
        Show-Header "REDE / LATENCIA"
        Write-Host "[1] RSS ON"
        Write-Host "[2] Interrupt Moderation OFF"
        Write-Host "[3] Reset Interrupt Moderation"
        Write-Host "[4] LSO OFF"
        Write-Host "[5] LSO ON"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Enable-RSS }
            "2" { Disable-InterruptModeration }
            "3" { Reset-InterruptModeration }
            "4" { Disable-LSO }
            "5" { Enable-LSO }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

function Show-BackupMenu {
    do {
        Show-Header "BACKUP / RESET"
        Write-Host "[1] Criar / atualizar backup"
        Write-Host "[2] Mostrar caminho do backup"
        Write-Host "[3] Reset global pelo backup"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" {
                Backup-CurrentState
                Pause-Lynext
            }
            "2" {
                Write-Host $global:BackupFile -ForegroundColor Yellow
                Pause-Lynext
            }
            "3" {
                Reset-AllFromBackup
            }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

function Start-PerformanceApp {
    Ensure-Admin

    do {
        Show-Header "PERFORMANCE APP"
        Write-Host "[1] Resumo do Sistema"
        Write-Host "[2] CPU / Energia"
        Write-Host "[3] NVIDIA"
        Write-Host "[4] AMD"
        Write-Host "[5] Windows / Jogos"
        Write-Host "[6] Rede / Latencia"
        Write-Host "[7] Backup / Reset"
        Write-Host "[0] Sair"
        Write-Host ""

        $choice = Read-Host "Escolha"

        switch ($choice) {
            "1" { Show-SystemSummary }
            "2" { Show-CPUMenu }
            "3" { Show-NvidiaMenu }
            "4" { Show-AmdMenu }
            "5" { Show-WindowsMenu }
            "6" { Show-NetworkMenu }
            "7" { Show-BackupMenu }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 600
            }
        }
    } while ($true)
}

Start-PerformanceApp

