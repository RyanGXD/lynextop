# Lynext Network Tool PRO - Installer

Write-Host ""
Write-Host "================================="
Write-Host "   Lynext Network Tool PRO"
Write-Host "================================="
Write-Host ""

# URL do seu .bat
$u = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/network_tool.bat"

# Caminho temporário
$d = "$env:TEMP\lynext.bat"

try {
    Write-Host "[+] Baixando ferramenta..."
    
    Invoke-WebRequest $u -OutFile $d -UseBasicParsing

    if (Test-Path $d) {
        Write-Host "[OK] Download concluido!"
        Write-Host "[+] Executando como administrador..."
        
        Start-Process $d -Verb RunAs
    }
    else {
        Write-Host "[ERRO] Falha ao salvar o arquivo."
    }
}
catch {
    Write-Host "[ERRO] Falha no download ou execucao."
}

Write-Host ""
