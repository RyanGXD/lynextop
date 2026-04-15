$batUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/network_tool.bat"
$batPath = "$env:TEMP\network_tool.bat"

Write-Host "Baixando Lynext..."
Write-Host ""

try {
    Invoke-WebRequest -Uri $batUrl -OutFile $batPath -UseBasicParsing

    if (Test-Path $batPath) {
        Write-Host "Download concluido com sucesso!"
        Write-Host "Executando Lynext..."
        Write-Host ""

        Start-Process $batPath -Verb RunAs
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
