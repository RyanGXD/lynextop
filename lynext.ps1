Write-Host "================================="
Write-Host "     Lynext Network Tool PRO"
Write-Host "================================="
Write-Host ""

$destino = "$env:TEMP\lynext.bat"

Write-Host "[+] Baixando ferramenta..."

Invoke-WebRequest -Uri "https://raw.githubusercontent.com/RyanGXD/lynextop/main/TesteRyan.bat" -OutFile $destino

Write-Host "[+] Executando como administrador..."

Start-Process $destino -Verb RunAs
