$loaderUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/lynext.ps1"
$baseUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main"
$installDir = Join-Path $env:TEMP "Lynext"
$files = @(
    "MainMenu.ps1",
    "DownloadsApp.ps1",
    "NetworkApp.ps1",
    "PerformanceApp.ps1"
)

function Test-LynextAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-LynextElevated {
    $command = "irm '$loaderUrl' | iex"

    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $command
    ) | Out-Null
}

function Initialize-LynextTls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {}
}

Write-Host "====================================="
Write-Host "            LYNEXT LOADER"
Write-Host "====================================="
Write-Host ""

if (-not (Test-LynextAdmin)) {
    Write-Host "Solicitando permissao de administrador..."
    Start-LynextElevated
    exit
}

try {
    Initialize-LynextTls

    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    foreach ($file in $files) {
        $url = "$baseUrl/$file"
        $dest = Join-Path $installDir $file

        Write-Host "Baixando $file..."
        Invoke-WebRequest -Uri $url -OutFile $dest
    }

    $mainMenu = Join-Path $installDir "MainMenu.ps1"

    if (-not (Test-Path $mainMenu)) {
        throw "MainMenu.ps1 nao foi encontrado apos o download."
    }

    Write-Host ""
    Write-Host "Download concluido com sucesso!"
    Write-Host "Abrindo menu principal..."
    Write-Host ""

    Set-Location $installDir
    & $mainMenu
}
catch {
    Write-Host ""
    Write-Host "Erro ao baixar ou executar o Lynext:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""
    Pause
}
