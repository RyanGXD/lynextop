$global:LynextPlanName = "Lynext Ultra Performance"
$global:UltimatePerfGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"

function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )

    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] [$Type] $Message"
}

function Get-PowerSchemes {
    $schemes = @()
    $lines = powercfg /list 2>$null

    foreach ($line in $lines) {
        if ($line -match 'Power Scheme GUID:\s*([a-fA-F0-9\-]{36})\s*\((.*?)\)(\s+\*)?') {
            $schemes += [PSCustomObject]@{
                Guid     = $matches[1].Trim()
                Name     = $matches[2].Trim()
                IsActive = [bool]$matches[3]
            }
        }
    }

    return $schemes
}

function Get-SchemeByName {
    param([string]$Name)

    $schemes = Get-PowerSchemes
    return $schemes | Where-Object { $_.Name -eq $Name }
}

function Get-SchemeByGuid {
    param([string]$Guid)

    $schemes = Get-PowerSchemes
    return $schemes | Where-Object { $_.Guid -eq $Guid }
}

function Remove-DuplicateLynextPlans {
    param([string]$KeepGuid)

    $plans = Get-SchemeByName -Name $global:LynextPlanName

    foreach ($plan in $plans) {
        if ($plan.Guid -ne $KeepGuid) {
            try {
                powercfg /delete $plan.Guid | Out-Null
                Write-Log "Plano duplicado removido: $($plan.Guid)"
            }
            catch {
                Write-Log "Falha ao remover duplicado: $($plan.Guid)" "WARN"
            }
        }
    }
}

function Test-UltimatePerformanceAvailable {
    $ultimate = Get-SchemeByGuid -Guid $global:UltimatePerfGuid
    return ($null -ne $ultimate)
}

function New-LynextUltraPlan {
    $existing = Get-SchemeByName -Name $global:LynextPlanName | Select-Object -First 1
    if ($existing) {
        Remove-DuplicateLynextPlans -KeepGuid $existing.Guid
        return $existing.Guid
    }

    $baseGuid = $null

    if (Test-UltimatePerformanceAvailable) {
        $baseGuid = $global:UltimatePerfGuid
        Write-Log "Base escolhida: Ultimate Performance"
    }
    else {
        $baseGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" # High Performance
        Write-Log "Ultimate Performance indisponivel. Usando High Performance como base." "WARN"
    }

    try {
        $output = powercfg /duplicatescheme $baseGuid 2>&1

        $newGuid = $null
        foreach ($line in $output) {
            if ($line -match '([a-fA-F0-9\-]{36})') {
                $newGuid = $matches[1]
                break
            }
        }

        if (-not $newGuid) {
            Start-Sleep -Milliseconds 500
            $latest = Get-PowerSchemes | Sort-Object Name
            $candidate = $latest | Where-Object { $_.Name -ne "Balanced" -and $_.Name -ne "Power saver" -and $_.Name -ne "High performance" } | Select-Object -Last 1
            if ($candidate) {
                $newGuid = $candidate.Guid
            }
        }

        if (-not $newGuid) {
            throw "Nao foi possivel identificar o GUID do novo plano."
        }

        powercfg /changename $newGuid $global:LynextPlanName "Plano otimizado do Lynext para desempenho maximo" | Out-Null

        # Ajustes principais do plano
        # Monitor / disco / sleep / hibernate
        powercfg /setacvalueindex $newGuid SUB_VIDEO VIDEOIDLE 0       | Out-Null
        powercfg /setacvalueindex $newGuid SUB_DISK DISKIDLE 0         | Out-Null
        powercfg /setacvalueindex $newGuid SUB_SLEEP STANDBYIDLE 0     | Out-Null
        powercfg /setacvalueindex $newGuid SUB_SLEEP HIBERNATEIDLE 0   | Out-Null

        # PCI Express - Link State Power Management = Off
        powercfg /setacvalueindex $newGuid SUB_PCIEXPRESS ASPM 0       | Out-Null

        # USB selective suspend = Disabled
        powercfg /setacvalueindex $newGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null

        # Processador
        # Min CPU = 100 / Max CPU = 100 / Boost agressivo
        powercfg /setacvalueindex $newGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
        powercfg /setacvalueindex $newGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 | Out-Null

        # Processor performance boost mode (Aggressive)
        powercfg /setacvalueindex $newGuid SUB_PROCESSOR be337238-0d82-4146-a960-4f3749d470c7 2 | Out-Null

        Remove-DuplicateLynextPlans -KeepGuid $newGuid

        Write-Log "Plano $global:LynextPlanName criado com sucesso."
        return $newGuid
    }
    catch {
        Write-Log "Erro ao criar plano Lynext: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Set-ActiveSchemeSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Guid,

        [string]$ExpectedName = ""
    )

    try {
        powercfg /setactive $Guid | Out-Null
        Start-Sleep -Milliseconds 300

        $active = (Get-PowerSchemes | Where-Object { $_.IsActive } | Select-Object -First 1)

        if (-not $active) {
            throw "Nao foi possivel confirmar o plano ativo."
        }

        if ($active.Guid -ne $Guid) {
            throw "Plano ativo incorreto. Esperado: $Guid | Atual: $($active.Guid) ($($active.Name))"
        }

        if ($ExpectedName -and $active.Name -ne $ExpectedName) {
            Write-Log "GUID correto ativo, mas o nome difere: $($active.Name)" "WARN"
        }

        Write-Log "Plano ativo definido: $($active.Name)"
        return $true
    }
    catch {
        Write-Log $_.Exception.Message "ERROR"
        return $false
    }
}

function Apply-BalancedMode {
    Write-Log "Aplicando modo Equilibrado..."
    return (Set-ActiveSchemeSafe -Guid "381b4222-f694-41f0-9685-ff5bb260df2e" -ExpectedName "Balanced")
}

function Apply-HighPerformanceMode {
    Write-Log "Aplicando modo High Performance..."
    return (Set-ActiveSchemeSafe -Guid "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -ExpectedName "High performance")
}

function Apply-LynextUltraPerformanceMode {
    Write-Log "Aplicando modo Lynext Ultra Performance..."

    $plan = Get-SchemeByName -Name $global:LynextPlanName | Select-Object -First 1
    $guid = $null

    if ($plan) {
        $guid = $plan.Guid
        Remove-DuplicateLynextPlans -KeepGuid $guid
    }
    else {
        $guid = New-LynextUltraPlan
    }

    if (-not $guid) {
        Write-Log "Falha ao obter o plano Lynext. Nao vou cair automaticamente para Balanced." "ERROR"
        return $false
    }

    $ok = Set-ActiveSchemeSafe -Guid $guid -ExpectedName $global:LynextPlanName

    if (-not $ok) {
        Write-Log "Falha ao ativar o plano Lynext Ultra Performance." "ERROR"
        return $false
    }

    return $true
}

function Show-AvailablePowerPlans {
    $schemes = Get-PowerSchemes

    Write-Host ""
    Write-Host "=========== PLANOS DE ENERGIA ===========" -ForegroundColor Cyan
    foreach ($scheme in $schemes) {
        $mark = if ($scheme.IsActive) { "*" } else { " " }
        Write-Host " [$mark] $($scheme.Name) - $($scheme.Guid)"
    }
    Write-Host "========================================="
    Write-Host ""
}
