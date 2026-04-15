$baseUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main"
$installDir = Join-Path $env:TEMP "Lynext"

$files = @(
    "MainMenu.ps1",
    "DownloadsApp.ps1",
    "NetworkApp.ps1",
    "PerformanceApp.ps1"
)

Write-Host "Baixando Lynext..."
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
        Write-Host "Executando Lynext..."
        Write-Host ""

        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$mainMenu`""
    }
    else {
        Write-Host "Erro: MainMenu.ps1 nao foi encontrado."
    }
}
catch {
    Write-Host ""
    Write-Host "Erro ao baixar Lynext:"
    Write-Host $_.Exception.Message
}

Pause
