# Lynext Installer

$u = "https://raw.githubusercontent.com/RyanGXD/lynextop/main/network_tool.bat"
$d = "$env:TEMP\lynext.bat"

# Bypass temporário (evita bloqueio)
Set-ExecutionPolicy Bypass -Scope Process -Force

try {
    Write-Host "[+] Baixando Lynext..."
    
    Invoke-WebRequest $u -OutFile $d

    if (Test-Path $d) {
        Write-Host "[OK] Executando..."

        Start-Process "cmd.exe" -ArgumentList "/c `"$d`"" -Verb RunAs
    }
    else {
        Write-Host "[ERRO] Download falhou."
    }
}
catch {
    Write-Host "[ERRO] Falha geral."
}
