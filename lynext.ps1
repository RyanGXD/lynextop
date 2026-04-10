$batUrl = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/network_tool.bat"
$batPath = "$env:TEMP\network_tool.bat"

Write-Host "Baixando Lynext..."

Invoke-WebRequest $batUrl -OutFile $batPath

Write-Host "Executando Lynext..."

Start-Process $batPath -Verb RunAs
