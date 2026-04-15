$menuUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/MainMenu.ps1"
$menuPath = "$env:TEMP\MainMenu.ps1"

Write-Host "Baixando Lynext..."
Write-Host ""

try {
    Invoke-WebRequest -Uri $menuUrl -OutFile $menuPath -UseBasicParsing

    if (Test-Path $menuPath) {
        Write-Host "Download concluido com sucesso!"
        Write-Host "Executando Lynext..."
        Write-Host ""

        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$menuPath`"" -Verb RunAs
    }
    else {
        Write-Host "Erro: arquivo nao foi baixado."
    }
}
catch {
    Write-Host ""
    Write-Host "Erro ao baixar Lynext:"
    Write-Host $_.Exception.Message
}

Pause
