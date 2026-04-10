$bat = "$env:TEMP\lynext.bat"

Invoke-WebRequest "https://raw.githubusercontent.com/SEU-USUARIO/SEU-REPO/main/lynext.bat" -OutFile $bat

Start-Process $bat -Verb RunAs
