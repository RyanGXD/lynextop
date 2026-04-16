$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$baseUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main"
$installDir = Join-Path $env:TEMP "Lynext"

$files = @(
    "MainMenu.ps1",
    "DownloadsApp.ps1",
    "NetworkApp.ps1",
    "PerformanceApp.ps1"
)

Write-Host "====================================="
Write-Host "            LYNEXT LOADER"
Write-Host "====================================="
Write-Host ""

try {
    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    foreach ($file in $files) {
        $url = "$baseUrl/$file"
        $dest = Join-Path $installDir $file

        Write-Host "Baixando $file ..."
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }

    $mainMenu = Join-Path $installDir "MainMenu.ps1"

    if (Test-Path $mainMenu) {
        Write-Host ""
        Write-Host "Download concluido com sucesso!"
        Write-Host "Abrindo MainMenu.ps1..."
        Write-Host ""

        powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File $mainMenu
    }
    else {
        Write-Host "Erro: MainMenu.ps1 nao foi encontrado."
    }
}
catch {
    Write-Host ""
    Write-Host "Erro ao baixar ou executar Lynext:"
    Write-Host $_.Exception.Message
}

Write-Host ""
Pause
