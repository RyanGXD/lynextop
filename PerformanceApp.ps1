# ============================================
# LYNEXT - PerformanceApp.ps1
# Baseado em pesquisa com foco em:
# - powercfg
# - rollback / snapshot
# - Game Mode / Game DVR / HAGS
# - NVIDIA via nvidia-smi quando suportado
# - AMD como camada segura/manual
# ============================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Lynext - Performance App"

# ============================================
# CONFIG
# ============================================

$global:LynextRoot = Join-Path $env:ProgramData "Lynext"
$global:BackupFile = Join-Path $global:LynextRoot "performance_backup.json"
$global:StateFile  = Join-Path $global:LynextRoot "performance_state.json"

if (-not (Test-Path $global:LynextRoot)) {
    New-Item -Path $global:LynextRoot -ItemType Directory -Force | Out-Null
}

# ============================================
# UI
# ============================================

function Pause-Lynext {
    Write-Host ""
    Read-Host "Pressione ENTER para continuar"
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

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-WarnL($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-ErrL($msg) { Write-Host "[ERRO] $msg" -ForegroundColor Red }

# ============================================
# ADMIN
# ============================================

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (-not (Test-IsAdministrator)) {
        Show-Header "PERFORMANCE APP"
        Write-ErrL "Este modulo precisa ser executado como Administrador."
        Pause-Lynext
        exit
    }
}

# ============================================
# JSON / STATE
# ============================================

function Save-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )

    $Data | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
}

function Load-JsonFile {
    param(
        [string]$Path
    )

    if (Test-Path $Path) {
        try {
            return Get-Content $Path -Raw | ConvertFrom-Json
        } catch {
            return $null
        }
    }

    return $null
}

# ============================================
# SYSTEM DETECTION
# ============================================

function Get-WindowsInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
    $cpu = Get-CimInstance Win32_Processor | Select-Object Name

    [PSCustomObject]@{
        Caption        = $os.Caption
        Version        = $os.Version
        BuildNumber    = $os.BuildNumber
        Model          = $cs.Model
        Manufacturer   = $cs.Manufacturer
        PCSystemType   = $cs.PCSystemType
        CPU            = ($cpu | Select-Object -ExpandProperty Name -First 1)
        GPUs           = $gpu
        IsLaptop       = ($cs.PCSystemType -in 2,3,4,8,9,10,14)
    }
}

function Test-ModernStandby {
    try {
        $output = powercfg /a 2>&1 | Out-String
        if ($output -match "Standby \(S0 Low Power Idle\)") {
            return $true
        }
    } catch {}
    return $false
}

function Get-GpuVendor {
    $names = (Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join " | "
    if ($names -match "NVIDIA") { return "NVIDIA" }
    if ($names -match "AMD|Radeon") { return "AMD" }
    if ($names -match "Intel") { return "Intel" }
    return "Unknown"
}

function Show-SystemSummary {
    Show-Header "RESUMO DO SISTEMA"

    $info = Get-WindowsInfo
    $modernStandby = Test-ModernStandby
    $gpuVendor = Get-GpuVendor

    Write-Host "Windows:         $($info.Caption) build $($info.BuildNumber)"
    Write-Host "Modelo:          $($info.Model)"
    Write-Host "CPU:             $($info.CPU)"
    Write-Host "GPU principal:   $gpuVendor"
    Write-Host "Notebook:        $($info.IsLaptop)"
    Write-Host "Modern Standby:  $modernStandby"
    Write-Host ""
    Write-Host "GPUs detectadas:" -ForegroundColor Yellow
    foreach ($g in $info.GPUs) {
        Write-Host " - $($g.Name) | Driver: $($g.DriverVersion)"
    }

    Pause-Lynext
}

# ============================================
# BACKUP / SNAPSHOT
# ============================================

function Get-ActivePowerSchemeGuid {
    $line = powercfg /getactivescheme
    if ($line -match '([a-fA-F0-9-]{36})') {
        return $Matches[1]
    }
    throw "Nao foi possivel identificar o esquema ativo."
}

function Get-RegDwordValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    } catch {
        return $null
    }
}

function Set-RegDword {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    $current = $null
    try { $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch {}

    if ($current -ne $Value) {
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
        return $true
    }

    return $false
}

function Backup-CurrentState {
    $backup = [ordered]@{
        CreatedAt = (Get-Date).ToString("s")
        System = @{
            ActivePowerScheme = $null
            ModernStandby     = $false
            GpuVendor         = $null
        }
        Registry = @{
            GameMode = @{
                Path  = "HKCU:\Software\Microsoft\GameBar"
                Name  = "AutoGameModeEnabled"
                Value = $null
            }
            GameDvrAppCapture = @{
                Path  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
                Name  = "AppCaptureEnabled"
                Value = $null
            }
            GameDvrEnabled = @{
                Path  = "HKCU:\System\GameConfigStore"
                Name  = "GameDVR_Enabled"
                Value = $null
            }
            Hags = @{
                Path  = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
                Name  = "HwSchMode"
                Value = $null
            }
        }
        NIC = @()
        Nvidia = @{
            PowerLimitDefault = $null
        }
    }

    try { $backup.System.ActivePowerScheme = Get-ActivePowerSchemeGuid } catch {}
    $backup.System.ModernStandby = Test-ModernStandby
    $backup.System.GpuVendor = Get-GpuVendor

    $backup.Registry.GameMode.Value =
        Get-RegDwordValue -Path $backup.Registry.GameMode.Path -Name $backup.Registry.GameMode.Name
    $backup.Registry.GameDvrAppCapture.Value =
        Get-RegDwordValue -Path $backup.Registry.GameDvrAppCapture.Path -Name $backup.Registry.GameDvrAppCapture.Name
    $backup.Registry.GameDvrEnabled.Value =
        Get-RegDwordValue -Path $backup.Registry.GameDvrEnabled.Path -Name $backup.Registry.GameDvrEnabled.Name
    $backup.Registry.Hags.Value =
        Get-RegDwordValue -Path $backup.Registry.Hags.Path -Name $backup.Registry.Hags.Name

    try {
        $nics = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq "Up" }
        foreach ($nic in $nics) {
            $rssEnabled = $null
            try {
                $rss = Get-NetAdapterRss -Name $nic.Name -ErrorAction Stop
                $rssEnabled = $rss.Enabled
            } catch {}

            $backup.NIC += @{
                Name       = $nic.Name
                RssEnabled = $rssEnabled
            }
        }
    } catch {}

    $nvidiaSmi = Get-NvidiaSmiPath
    if ($nvidiaSmi) {
        try {
            $pl = & $nvidiaSmi --query-gpu=power.default_limit --format=csv,noheader,nounits 2>$null
            if ($pl) {
                $num = ($pl | Select-Object -First 1).ToString().Trim()
                if ($num -match '^\d+(\.\d+)?$') {
                    $backup.Nvidia.PowerLimitDefault = [double]$num
                }
            }
        } catch {}
    }

    Save-JsonFile -Path $global:BackupFile -Data $backup
    return $backup
}

function Ensure-BackupExists {
    if (-not (Test-Path $global:BackupFile)) {
        Write-Info "Criando snapshot inicial..."
        Backup-CurrentState | Out-Null
        Write-Ok "Snapshot salvo em $global:BackupFile"
    }
}

# ============================================
# POWERCFG HELPERS
# ============================================

function Set-PowerValue {
    param(
        [Parameter(Mandatory)] [string]$Subgroup,
        [Parameter(Mandatory)] [string]$Setting,
        [Parameter(Mandatory)] [int]$AcValue,
        [int]$DcValue = $AcValue
    )

    & powercfg /setacvalueindex scheme_current $Subgroup $Setting $AcValue | Out-Null
    & powercfg /setdcvalueindex scheme_current $Subgroup $Setting $DcValue | Out-Null
    & powercfg /setactive scheme_current | Out-Null
}

function Try-EnableUltimatePerformance {
    try {
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $result = powercfg -duplicatescheme $guid 2>&1 | Out-String
        if ($result -match '([a-fA-F0-9-]{36})') {
            $newGuid = $Matches[1]
            powercfg /setactive $newGuid | Out-Null
            return $true
        }

        # caso já exista ou retorno seja diferente
        $plans = powercfg /list | Out-String
        if ($plans -match 'e9a42b02-d5df-448d-aa00-03f14749eb61') {
            powercfg /setactive $guid | Out-Null
            return $true
        }

        return $false
    } catch {
        return $false
    }
}

function Set-BalancedPlan {
    powercfg /setactive SCHEME_BALANCED | Out-Null
}

function Set-HighPerformancePlan {
    powercfg /setactive SCHEME_MIN | Out-Null
}

# ============================================
# CPU / POWER PRESETS
# ============================================

function Apply-CPUUltraPerformance {
    Show-Header "CPU - ULTRA PERFORMANCE"
    Ensure-BackupExists

    $info = Get-WindowsInfo
    $modernStandby = Test-ModernStandby

    Write-Info "Aplicando preset agressivo de CPU..."
    Write-Host ""

    if ($modernStandby) {
        Write-WarnL "Modern Standby detectado. Vou evitar assumir High/Ultimate fixo."
        Set-BalancedPlan
    } else {
        $ultimateOk = Try-EnableUltimatePerformance
        if (-not $ultimateOk) {
            Write-WarnL "Ultimate Performance indisponivel. Usando High Performance."
            Set-HighPerformancePlan
        } else {
            Write-Ok "Ultimate Performance ativado."
        }
    }

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFEPP" -AcValue 0 -DcValue 15
    Write-Ok "EPP ajustado: AC=0 / DC=15"

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFBOOSTMODE" -AcValue 2 -DcValue 1
    Write-Ok "Boost mode ajustado: AC=2 / DC=1"

    Set-PowerValue -Subgroup "sub_processor" -Setting "CPMINCORES" -AcValue 100 -DcValue 50
    Write-Ok "Core Parking minimo ajustado: AC=100 / DC=50"

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1 -DcValue 1
    Write-Ok "Autonomous mode ajustado: AC=1 / DC=1"

    if ($info.IsLaptop) {
        Write-WarnL "Notebook detectado. Esse preset pode aumentar temperatura e consumo na tomada."
    }

    Pause-Lynext
}

function Apply-CPUPerformance {
    Show-Header "CPU - PERFORMANCE"
    Ensure-BackupExists

    $info = Get-WindowsInfo
    $modernStandby = Test-ModernStandby

    Write-Info "Aplicando preset equilibrado de CPU..."
    Write-Host ""

    if ($modernStandby -or $info.IsLaptop) {
        Set-BalancedPlan
        Write-Ok "Plano Balanced mantido por compatibilidade."
    } else {
        Set-HighPerformancePlan
        Write-Ok "Plano High Performance ativado."
    }

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFEPP" -AcValue 25 -DcValue 40
    Write-Ok "EPP ajustado: AC=25 / DC=40"

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFBOOSTMODE" -AcValue 4 -DcValue 3
    Write-Ok "Boost mode ajustado: AC=4 / DC=3"

    Set-PowerValue -Subgroup "sub_processor" -Setting "CPMINCORES" -AcValue 100 -DcValue 25
    Write-Ok "Core Parking minimo ajustado: AC=100 / DC=25"

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFAUTONOMOUSMODE" -AcValue 1 -DcValue 1
    Write-Ok "Autonomous mode ajustado."

    Pause-Lynext
}

function Apply-CPUThermal {
    Show-Header "CPU - TERMICO / QUIETO"
    Ensure-BackupExists

    Write-Info "Aplicando preset mais frio/silencioso..."
    Write-Host ""

    Set-BalancedPlan
    Write-Ok "Plano Balanced ativado."

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFEPP" -AcValue 60 -DcValue 80
    Write-Ok "EPP ajustado: AC=60 / DC=80"

    Set-PowerValue -Subgroup "sub_processor" -Setting "PERFBOOSTMODE" -AcValue 0 -DcValue 0
    Write-Ok "Boost mode desativado: AC=0 / DC=0"

    Set-PowerValue -Subgroup "sub_processor" -Setting "CPMINCORES" -AcValue 25 -DcValue 10
    Write-Ok "Core Parking mais conservador."

    Pause-Lynext
}

function Show-CPUEconomySkeleton {
    Show-Header "CPU - ECONOMIA (ESQUELETO)"
    Write-Host "Esqueleto reservado para o futuro modo Economia." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Sugestao futura:"
    Write-Host "- Balanced"
    Write-Host "- EPP alto (70-90)"
    Write-Host "- Boost mode eficiente ou off"
    Write-Host "- Core Parking mais conservador"
    Pause-Lynext
}

# ============================================
# WINDOWS / GAMING
# ============================================

function Set-GameMode {
    param([ValidateSet("On","Off")] [string]$Mode)

    $value = if ($Mode -eq "On") { 1 } else { 0 }
    Set-RegDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value $value | Out-Null
    Write-Ok "Game Mode: $Mode"
}

function Set-GameDvr {
    param([ValidateSet("On","Off")] [string]$Mode)

    $appCapture = if ($Mode -eq "On") { 1 } else { 0 }
    $gameDvr    = if ($Mode -eq "On") { 1 } else { 0 }

    Set-RegDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value $appCapture | Out-Null
    Set-RegDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value $gameDvr | Out-Null
    Write-Ok "Game DVR / captura: $Mode"
}

function Set-Hags {
    param([ValidateSet("On","Off")] [string]$Mode)

    $value = if ($Mode -eq "On") { 2 } else { 1 }
    Set-RegDword -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value $value | Out-Null
    Write-WarnL "HAGS alterado para $Mode. Reinicializacao recomendada."
}

function Open-GraphicsSettingsHint {
    Show-Header "HAGS / GRAPHICS SETTINGS"
    Write-Host "Caminho oficial do Windows para HAGS:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Configuracoes > Sistema > Tela > Graficos > Alterar configuracoes graficas padrao"
    Write-Host ""
    Write-Host "O script usa registro como fallback avancado."
    Pause-Lynext
}

function Apply-WindowsUltra {
    Show-Header "WINDOWS - ULTRA PERFORMANCE"
    Ensure-BackupExists

    Write-Info "Aplicando ajustes gamer do Windows..."
    Write-Host ""

    Set-GameMode -Mode "On"
    Set-GameDvr -Mode "Off"
    Set-Hags -Mode "On"

    Write-WarnL "Visual effects 'best performance' nao foi forçado por registro aqui."
    Write-WarnL "Melhor tratar isso como opcional/manual para nao baguncar preferencia visual."

    Pause-Lynext
}

function Apply-WindowsPerformance {
    Show-Header "WINDOWS - PERFORMANCE"
    Ensure-BackupExists

    Write-Info "Aplicando ajustes equilibrados do Windows..."
    Write-Host ""

    Set-GameMode -Mode "On"
    Set-GameDvr -Mode "Off"

    Write-WarnL "HAGS nao foi ligado automaticamente nesse preset."
    Write-WarnL "Use o menu dedicado se quiser testar, porque pode variar por driver/jogo."

    Pause-Lynext
}

function Apply-WindowsResetFromBackup {
    Show-Header "WINDOWS - RESET"
    $backup = Load-JsonFile -Path $global:BackupFile

    if (-not $backup) {
        Write-ErrL "Nenhum backup encontrado."
        Pause-Lynext
        return
    }

    Write-Info "Restaurando ajustes do Windows pelo snapshot..."
    Write-Host ""

    if ($null -ne $backup.Registry.GameMode.Value) {
        Set-RegDword -Path $backup.Registry.GameMode.Path -Name $backup.Registry.GameMode.Name -Value ([int]$backup.Registry.GameMode.Value) | Out-Null
        Write-Ok "Game Mode restaurado."
    }

    if ($null -ne $backup.Registry.GameDvrAppCapture.Value) {
        Set-RegDword -Path $backup.Registry.GameDvrAppCapture.Path -Name $backup.Registry.GameDvrAppCapture.Name -Value ([int]$backup.Registry.GameDvrAppCapture.Value) | Out-Null
        Write-Ok "AppCaptureEnabled restaurado."
    }

    if ($null -ne $backup.Registry.GameDvrEnabled.Value) {
        Set-RegDword -Path $backup.Registry.GameDvrEnabled.Path -Name $backup.Registry.GameDvrEnabled.Name -Value ([int]$backup.Registry.GameDvrEnabled.Value) | Out-Null
        Write-Ok "GameDVR_Enabled restaurado."
    }

    if ($null -ne $backup.Registry.Hags.Value) {
        Set-RegDword -Path $backup.Registry.Hags.Path -Name $backup.Registry.Hags.Name -Value ([int]$backup.Registry.Hags.Value) | Out-Null
        Write-WarnL "HAGS restaurado. Reinicializacao pode ser necessaria."
    }

    Pause-Lynext
}

# ============================================
# NIC / LATENCY
# ============================================

function Get-ActivePhysicalNics {
    try {
        return Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq "Up" }
    } catch {
        return @()
    }
}

function Show-NicList {
    $nics = Get-ActivePhysicalNics
    if (-not $nics -or $nics.Count -eq 0) {
        Write-WarnL "Nenhuma NIC fisica ativa encontrada."
        return $null
    }

    $index = 1
    foreach ($nic in $nics) {
        Write-Host "[$index] $($nic.Name) - $($nic.InterfaceDescription)"
        $index++
    }

    Write-Host "[0] Voltar"
    Write-Host ""
    $choice = Read-Host "Escolha a NIC"

    if ($choice -eq "0") { return $null }

    if ($choice -as [int]) {
        $i = [int]$choice - 1
        if ($i -ge 0 -and $i -lt $nics.Count) {
            return $nics[$i]
        }
    }

    return $null
}

function Enable-RssForNic {
    Show-Header "NIC - RSS ON"
    Ensure-BackupExists

    $nic = Show-NicList
    if (-not $nic) { return }

    try {
        Enable-NetAdapterRss -Name $nic.Name -ErrorAction Stop
        Write-Ok "RSS habilitado em $($nic.Name)"
    } catch {
        Write-ErrL "Falha ao habilitar RSS: $($_.Exception.Message)"
    }

    Pause-Lynext
}

function Disable-InterruptModerationForNic {
    Show-Header "NIC - INTERRUPT MODERATION OFF"
    Ensure-BackupExists

    $nic = Show-NicList
    if (-not $nic) { return }

    Write-WarnL "Isso e opcao de teste/diagnostico. Pode aumentar uso de CPU."
    try {
        Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Interrupt Moderation" -DisplayValue "Disabled" -ErrorAction Stop
        Write-Ok "Interrupt Moderation desativado em $($nic.Name)"
    } catch {
        Write-ErrL "Falha ao alterar a propriedade. O nome pode variar conforme o driver/NIC."
    }

    Pause-Lynext
}

function Reset-InterruptModerationForNic {
    Show-Header "NIC - RESET INTERRUPT MODERATION"

    $nic = Show-NicList
    if (-not $nic) { return }

    try {
        Reset-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Interrupt Moderation" -ErrorAction Stop
        Write-Ok "Interrupt Moderation resetado em $($nic.Name)"
    } catch {
        Write-ErrL "Falha ao resetar. O nome pode variar conforme o driver/NIC."
    }

    Pause-Lynext
}

function Disable-LsoForNic {
    Show-Header "NIC - LSO OFF (DIAGNOSTICO)"
    $nic = Show-NicList
    if (-not $nic) { return }

    Write-WarnL "LSO OFF deve ser usado como diagnostico, nao preset padrao."
    try {
        Disable-NetAdapterLso -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
        Write-Ok "LSO desativado em $($nic.Name)"
    } catch {
        Write-ErrL "Falha ao desativar LSO."
    }

    Pause-Lynext
}

function Enable-LsoForNic {
    Show-Header "NIC - LSO ON"
    $nic = Show-NicList
    if (-not $nic) { return }

    try {
        Enable-NetAdapterLso -Name $nic.Name -IPv4 -IPv6 -ErrorAction Stop
        Write-Ok "LSO habilitado em $($nic.Name)"
    } catch {
        Write-ErrL "Falha ao habilitar LSO."
    }

    Pause-Lynext
}

# ============================================
# NVIDIA
# ============================================

function Get-NvidiaSmiPath {
    $paths = @(
        (Join-Path $env:ProgramFiles "NVIDIA Corporation\NVSMI\nvidia-smi.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "NVIDIA Corporation\NVSMI\nvidia-smi.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }

    return ($paths | Select-Object -First 1)
}

function Test-NvidiaPresent {
    return (Get-GpuVendor) -eq "NVIDIA"
}

function Show-NvidiaSupportInfo {
    Show-Header "NVIDIA - SUPORTE"

    if (-not (Test-NvidiaPresent)) {
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
    } catch {
        Write-ErrL "Falha ao consultar nvidia-smi."
    }

    Pause-Lynext
}

function Set-NvidiaPowerLimit {
    param(
        [double]$Watts
    )

    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-ErrL "nvidia-smi nao encontrado."
        return
    }

    try {
        & $nvidiaSmi -pl $Watts | Out-Null
        Write-Ok "Power limit ajustado para $Watts W"
    } catch {
        Write-ErrL "Falha ao ajustar power limit."
    }
}

function Set-NvidiaLockedClocks {
    param(
        [int]$MinClock,
        [int]$MaxClock
    )

    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-ErrL "nvidia-smi nao encontrado."
        return
    }

    try {
        & $nvidiaSmi -lgc "$MinClock,$MaxClock" | Out-Null
        Write-Ok "Clocks travados em $MinClock,$MaxClock MHz"
    } catch {
        Write-ErrL "Falha ao travar clocks. Nem toda GPU/driver suporta isso."
    }
}

function Reset-NvidiaLockedClocks {
    $nvidiaSmi = Get-NvidiaSmiPath
    if (-not $nvidiaSmi) {
        Write-ErrL "nvidia-smi nao encontrado."
        return
    }

    try {
        & $nvidiaSmi -rgc | Out-Null
        Write-Ok "Clocks da GPU resetados."
    } catch {
        Write-ErrL "Falha ao resetar clocks."
    }
}

function Apply-NvidiaUltraPolicy {
    Show-Header "NVIDIA - ULTRA PERFORMANCE"
    Ensure-BackupExists

    if (-not (Test-NvidiaPresent)) {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica sugerida pelo app para painel NVIDIA:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "- Power Management Mode: Prefer maximum performance"
    Write-Host "- Low Latency Mode: Ultra somente se o jogo NAO tiver Reflex"
    Write-Host "- Texture Filtering Quality: High performance"
    Write-Host "- Shader Cache Size: grande, mas finito"
    Write-Host "- G-SYNC / VRR: manter se o monitor suportar"
    Write-Host "- Reflex tem prioridade sobre ULLM"
    Write-Host "- DLSS ON e RT baixo/off quando o objetivo for FPS"
    Write-Host ""

    $opt = Read-Host "Deseja aplicar power limit manual agora? (s/n)"
    if ($opt -match '^(s|S)$') {
        $watts = Read-Host "Digite o limite em Watts"
        if ($watts -match '^\d+(\.\d+)?$') {
            Set-NvidiaPowerLimit -Watts ([double]$watts)
        } else {
            Write-WarnL "Valor invalido."
        }
    }

    Pause-Lynext
}

function Apply-NvidiaPerformancePolicy {
    Show-Header "NVIDIA - PERFORMANCE"
    Ensure-BackupExists

    if (-not (Test-NvidiaPresent)) {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica sugerida pelo app para painel NVIDIA:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "- Power Management Mode: Adaptive ou Driver controlled"
    Write-Host "- Low Latency Mode: On, ou Off se o jogo tiver Reflex"
    Write-Host "- Texture Filtering Quality: Performance"
    Write-Host "- Shader Cache Size: 5 a 10 GB"
    Write-Host "- DLSS Balanced/Quality conforme o jogo"
    Write-Host "- RT medio apenas se houver folga"
    Write-Host ""

    Pause-Lynext
}

function Apply-NvidiaReset {
    Show-Header "NVIDIA - RESET"

    $backup = Load-JsonFile -Path $global:BackupFile
    if (-not (Test-NvidiaPresent)) {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    Reset-NvidiaLockedClocks

    if ($backup -and $backup.Nvidia -and $backup.Nvidia.PowerLimitDefault) {
        Set-NvidiaPowerLimit -Watts ([double]$backup.Nvidia.PowerLimitDefault)
    } else {
        Write-WarnL "Nao encontrei o power limit padrao no backup."
        Write-WarnL "Se necessario, confira o valor real com nvidia-smi -q -d POWER,CLOCK."
    }

    Write-Host ""
    Write-Host "Para settings 3D do painel:" -ForegroundColor Yellow
    Write-Host "- devolva os parametros ao default no NVIDIA Control Panel"
    Write-Host "- o app NAO usa registro privado para isso de proposito"
    Pause-Lynext
}

function Show-NvidiaClockMenu {
    Show-Header "NVIDIA - CLOCK LOCK"

    if (-not (Test-NvidiaPresent)) {
        Write-WarnL "GPU NVIDIA nao detectada."
        Pause-Lynext
        return
    }

    $min = Read-Host "Clock minimo (MHz)"
    $max = Read-Host "Clock maximo (MHz)"

    if (($min -match '^\d+$') -and ($max -match '^\d+$')) {
        Set-NvidiaLockedClocks -MinClock ([int]$min) -MaxClock ([int]$max)
    } else {
        Write-WarnL "Valores invalidos."
    }

    Pause-Lynext
}

# ============================================
# AMD
# ============================================

function Test-AmdPresent {
    return (Get-GpuVendor) -eq "AMD"
}

function Show-AmdPolicyUltra {
    Show-Header "AMD - ULTRA PERFORMANCE"

    if (-not (Test-AmdPresent)) {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica sugerida para AMD Adrenalin / helper futuro:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "- Anti-Lag: ON"
    Write-Host "- Chill: OFF"
    Write-Host "- Boost: ON com resolucao minima mais agressiva"
    Write-Host "- Image Sharpening: ON moderado"
    Write-Host "- Tessellation: override reduzido"
    Write-Host "- Enhanced Sync: somente se nao houver black screen/stutter"
    Write-Host "- RSR/FSR: ON quando fizer sentido"
    Write-Host ""
    Write-Host "Observacao:"
    Write-Host "A parte avancada da AMD deve idealmente usar ADLX/helper .NET."
    Pause-Lynext
}

function Show-AmdPolicyPerformance {
    Show-Header "AMD - PERFORMANCE"

    if (-not (Test-AmdPresent)) {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Politica sugerida para AMD Adrenalin / helper futuro:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "- Anti-Lag: ON"
    Write-Host "- Chill: OFF"
    Write-Host "- Boost: moderado ou OFF"
    Write-Host "- Image Sharpening: leve/moderado"
    Write-Host "- Tessellation: app controlled ou override leve"
    Write-Host "- Enhanced Sync: opcional por jogo"
    Write-Host "- RSR/FSR: ON quando faltar GPU"
    Pause-Lynext
}

function Show-AmdResetPolicy {
    Show-Header "AMD - RESET"

    if (-not (Test-AmdPresent)) {
        Write-WarnL "GPU AMD nao detectada."
        Pause-Lynext
        return
    }

    Write-Host "Reset AMD recomendado:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "- Voltar os toggles ao default no Adrenalin"
    Write-Host "- Se necessario, usar reinstalacao limpa do driver"
    Write-Host "- Fluxos automáticos mais corretos exigem ADLX/helper"
    Pause-Lynext
}

# ============================================
# GLOBAL RESET
# ============================================

function Reset-AllFromBackup {
    Show-Header "RESET GLOBAL"

    $backup = Load-JsonFile -Path $global:BackupFile
    if (-not $backup) {
        Write-ErrL "Nenhum backup encontrado para rollback."
        Pause-Lynext
        return
    }

    Write-Info "Restaurando estado salvo..."
    Write-Host ""

    try {
        if ($backup.System.ActivePowerScheme) {
            powercfg /setactive $backup.System.ActivePowerScheme | Out-Null
            Write-Ok "Plano de energia restaurado."
        }
    } catch {
        Write-ErrL "Falha ao restaurar o plano de energia."
    }

    foreach ($entry in @(
        $backup.Registry.GameMode,
        $backup.Registry.GameDvrAppCapture,
        $backup.Registry.GameDvrEnabled,
        $backup.Registry.Hags
    )) {
        if ($null -ne $entry.Value) {
            try {
                Set-RegDword -Path $entry.Path -Name $entry.Name -Value ([int]$entry.Value) | Out-Null
                Write-Ok "$($entry.Name) restaurado."
            } catch {
                Write-ErrL "Falha ao restaurar $($entry.Name)."
            }
        }
    }

    if ($backup.NIC) {
        foreach ($nic in $backup.NIC) {
            if ($null -ne $nic.RssEnabled) {
                try {
                    if ([bool]$nic.RssEnabled) {
                        Enable-NetAdapterRss -Name $nic.Name -ErrorAction Stop
                    } else {
                        Disable-NetAdapterRss -Name $nic.Name -ErrorAction Stop
                    }
                    Write-Ok "RSS restaurado para $($nic.Name)"
                } catch {
                    Write-WarnL "Nao foi possivel restaurar RSS para $($nic.Name)"
                }
            }
        }
    }

    if ((Get-GpuVendor) -eq "NVIDIA") {
        Reset-NvidiaLockedClocks
        if ($backup.Nvidia -and $backup.Nvidia.PowerLimitDefault) {
            Set-NvidiaPowerLimit -Watts ([double]$backup.Nvidia.PowerLimitDefault)
        }
    }

    Write-WarnL "Se voce alterou HAGS, reinicie o PC para finalizar o rollback."
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
            "1" { Apply-CPUUltraPerformance }
            "2" { Apply-CPUPerformance }
            "3" { Apply-CPUThermal }
            "4" { Show-CPUEconomySkeleton }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($true)
}

function Show-NvidiaMenu {
    do {
        Show-Header "NVIDIA"

        Write-Host "[1] Ultra Performance (politica + power limit opcional)"
        Write-Host "[2] Performance (politica)"
        Write-Host "[3] Reset"
        Write-Host "[4] Consultar suporte / clocks / power"
        Write-Host "[5] Travar clocks manualmente"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Apply-NvidiaUltraPolicy }
            "2" { Apply-NvidiaPerformancePolicy }
            "3" { Apply-NvidiaReset }
            "4" { Show-NvidiaSupportInfo }
            "5" { Show-NvidiaClockMenu }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($true)
}

function Show-AmdMenu {
    do {
        Show-Header "AMD"

        Write-Host "[1] Ultra Performance (politica)"
        Write-Host "[2] Performance (politica)"
        Write-Host "[3] Reset (politica)"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Show-AmdPolicyUltra }
            "2" { Show-AmdPolicyPerformance }
            "3" { Show-AmdResetPolicy }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($true)
}

function Show-WindowsMenu {
    do {
        Show-Header "WINDOWS / JOGOS"

        Write-Host "[1] Ultra Performance"
        Write-Host "[2] Performance"
        Write-Host "[3] Reset do Windows pelo backup"
        Write-Host "[4] Abrir orientacao oficial de HAGS"
        Write-Host "[5] HAGS ON (fallback avancado)"
        Write-Host "[6] HAGS OFF (fallback avancado)"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Apply-WindowsUltra }
            "2" { Apply-WindowsPerformance }
            "3" { Apply-WindowsResetFromBackup }
            "4" { Open-GraphicsSettingsHint }
            "5" {
                Ensure-BackupExists
                Show-Header "HAGS ON"
                Set-Hags -Mode "On"
                Pause-Lynext
            }
            "6" {
                Ensure-BackupExists
                Show-Header "HAGS OFF"
                Set-Hags -Mode "Off"
                Pause-Lynext
            }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($true)
}

function Show-NetworkMenu {
    do {
        Show-Header "REDE / LATENCIA"

        Write-Host "[1] RSS ON"
        Write-Host "[2] Interrupt Moderation OFF (teste)"
        Write-Host "[3] Reset Interrupt Moderation"
        Write-Host "[4] LSO OFF (diagnostico)"
        Write-Host "[5] LSO ON"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" { Enable-RssForNic }
            "2" { Disable-InterruptModerationForNic }
            "3" { Reset-InterruptModerationForNic }
            "4" { Disable-LsoForNic }
            "5" { Enable-LsoForNic }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($true)
}

function Show-BackupMenu {
    do {
        Show-Header "BACKUP / RESET"

        Write-Host "[1] Criar / atualizar snapshot"
        Write-Host "[2] Ver caminho do backup"
        Write-Host "[3] Reset global pelo backup"
        Write-Host "[0] Voltar"
        Write-Host ""

        $opt = Read-Host "Escolha"

        switch ($opt) {
            "1" {
                Backup-CurrentState | Out-Null
                Write-Ok "Snapshot atualizado com sucesso."
                Pause-Lynext
            }
            "2" {
                Write-Host "Backup atual:" -ForegroundColor Yellow
                Write-Host $global:BackupFile
                Pause-Lynext
            }
            "3" {
                Reset-AllFromBackup
            }
            "0" { break }
            default {
                Write-WarnL "Opcao invalida."
                Start-Sleep -Milliseconds 700
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

        $choice = Read-Host "Escolha uma opcao"

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
                Start-Sleep -Milliseconds 700
            }
        }
    } while ($true)
}

Start-PerformanceApp
