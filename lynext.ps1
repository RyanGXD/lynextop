Write-Host "================================="
Write-Host "   Lynext Network Tool PRO"
Write-Host "================================="
Write-Host ""

# Caminho temporario
$destino = "$env:TEMP\lynext.bat"

Write-Host "[+] Preparando download..."

# URL correta do seu GitHub
$url = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/network_tool.bat"

try {
    Write-Host "[+] Baixando ferramenta..."
    Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing

    if (Test-Path $destino) {
        Write-Host "[+] Download concluido com sucesso!"
        Write-Host ""

        Write-Host "[+] Executando como administrador..."
        Start-Process -FilePath $destino -Verb RunAs
    }
    else {
        Write-Host "[ERRO] Arquivo nao foi baixado."
    }
}
catch {
    Write-Host "[ERRO] Falha ao baixar o arquivo."
    Write-Host "Verifique o link do GitHub."
}

Write-Host ""
Write-Host "Finalizado."
