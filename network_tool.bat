@echo off
setlocal EnableExtensions
title Lynext Network Tool PRO
color 0A
mode con: cols=70 lines=28

:: =========================
:: ADMIN
:: =========================
net session >nul 2>&1
if %errorlevel% neq 0 (
    cls
    echo.
    echo [!] Elevando privilegios...
    timeout /t 2 >nul
    powershell -Command "Start-Process '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"
    exit /b
)

:: =========================
:: VARIAVEIS GLOBAIS
:: =========================
set "LOG=%temp%\lynext_log.txt"
set "PS_APP=%temp%\DownloadsApp.ps1"
set "PS_URL=https://raw.githubusercontent.com/RyanGXD/lynextop/main/DownloadsApp.ps1"

:menu
cls
echo.
echo ======================================================
echo                    L Y N E X T
echo              Network Tool PRO - v1.0
echo ======================================================
echo.
echo  [1] REDE
echo  [2] OTIMIZACAO
echo  [3] TESTES
echo  [4] COMPETITIVO
echo  [5] INFORMACOES
echo  [6] DOWNLOADS
echo.
echo  [0] SAIR
echo.

choice /c 1234560 /n /m "Escolha uma opcao: "

if errorlevel 7 goto sair
if errorlevel 6 goto downloads
if errorlevel 5 goto informacoes
if errorlevel 4 goto competitivo
if errorlevel 3 goto testes
if errorlevel 2 goto otimizacao
if errorlevel 1 goto rede

:: =========================
:: MENU REDE
:: =========================
:rede
cls
echo.
echo ======================================================
echo                         REDE
echo ======================================================
echo.
echo  [1] Flush DNS
echo  [2] Reset Winsock
echo  [3] Reset IP
echo  [4] Reset Firewall
echo  [5] Limpeza completa de rede
echo.
echo  [0] Voltar
echo.

choice /c 123450 /n /m "Escolha uma opcao: "

if errorlevel 6 goto menu
if errorlevel 5 goto rede_completa
if errorlevel 4 goto rede_firewall
if errorlevel 3 goto rede_ip
if errorlevel 2 goto rede_winsock
if errorlevel 1 goto rede_flushdns

:rede_flushdns
cls
echo Executando Flush DNS...
ipconfig /flushdns
echo [%date% %time%] Flush DNS executado>>"%LOG%"
pause
goto rede

:rede_winsock
cls
echo Executando reset do Winsock...
netsh winsock reset
echo [%date% %time%] Reset Winsock executado>>"%LOG%"
pause
goto rede

:rede_ip
cls
echo Executando reset de IP...
netsh int ip reset
echo [%date% %time%] Reset IP executado>>"%LOG%"
pause
goto rede

:rede_firewall
cls
echo Executando reset do Firewall...
netsh advfirewall reset
echo [%date% %time%] Reset Firewall executado>>"%LOG%"
pause
goto rede

:rede_completa
cls
echo Executando limpeza completa de rede...
ipconfig /flushdns
ipconfig /release
ipconfig /renew
netsh winsock reset
netsh int ip reset
netsh advfirewall reset
nbtstat -R
nbtstat -RR
netsh interface ip delete arpcache
echo [%date% %time%] Limpeza completa de rede executada>>"%LOG%"
pause
goto rede

:: =========================
:: MENU OTIMIZACAO
:: =========================
:otimizacao
cls
echo.
echo ======================================================
echo                     OTIMIZACAO
echo ======================================================
echo.
echo  [1] SFC Scannow
echo  [2] DISM RestoreHealth
echo  [3] Plano Alto Desempenho
echo.
echo  [0] Voltar
echo.

choice /c 1230 /n /m "Escolha uma opcao: "

if errorlevel 4 goto menu
if errorlevel 3 goto plano_alto
if errorlevel 2 goto dism
if errorlevel 1 goto sfc

:sfc
cls
echo Executando SFC...
sfc /scannow
echo [%date% %time%] SFC executado>>"%LOG%"
pause
goto otimizacao

:dism
cls
echo Executando DISM...
DISM /Online /Cleanup-Image /RestoreHealth
echo [%date% %time%] DISM executado>>"%LOG%"
pause
goto otimizacao

:plano_alto
cls
echo Ativando plano Alto Desempenho...
powercfg -setactive SCHEME_MIN
echo [%date% %time%] Plano Alto Desempenho ativado>>"%LOG%"
pause
goto otimizacao

:: =========================
:: MENU TESTES
:: =========================
:testes
cls
echo.
echo ======================================================
echo                        TESTES
echo ======================================================
echo.
echo  [1] Ping Google
echo  [2] IPConfig
echo.
echo  [0] Voltar
echo.

choice /c 120 /n /m "Escolha uma opcao: "

if errorlevel 3 goto menu
if errorlevel 2 goto ver_ip
if errorlevel 1 goto ping_google

:ping_google
cls
ping google.com
echo [%date% %time%] Ping Google executado>>"%LOG%"
pause
goto testes

:ver_ip
cls
ipconfig /all
echo [%date% %time%] IPConfig executado>>"%LOG%"
pause
goto testes

:: =========================
:: MENU COMPETITIVO
:: =========================
:competitivo
cls
echo.
echo ======================================================
echo                     COMPETITIVO
echo ======================================================
echo.
echo  [1] TCP Global
echo  [2] Mostrar configuracoes TCP
echo.
echo  [0] Voltar
echo.

choice /c 120 /n /m "Escolha uma opcao: "

if errorlevel 3 goto menu
if errorlevel 2 goto mostrar_tcp
if errorlevel 1 goto tcp_global

:tcp_global
cls
echo Aplicando ajuste TCP global...
netsh int tcp set global autotuninglevel=normal
netsh int tcp set global rss=enabled
netsh int tcp set global chimney=enabled
echo [%date% %time%] Ajustes TCP globais aplicados>>"%LOG%"
pause
goto competitivo

:mostrar_tcp
cls
netsh int tcp show global
echo [%date% %time%] Configuracoes TCP exibidas>>"%LOG%"
pause
goto competitivo

:: =========================
:: MENU INFORMACOES
:: =========================
:informacoes
cls
echo.
echo ======================================================
echo                     INFORMACOES
echo ======================================================
echo.
echo  [1] Ver log
echo  [2] Informacoes do sistema
echo.
echo  [0] Voltar
echo.

choice /c 120 /n /m "Escolha uma opcao: "

if errorlevel 3 goto menu
if errorlevel 2 goto infos_sistema
if errorlevel 1 goto ver_log

:ver_log
cls
if exist "%LOG%" (
    type "%LOG%"
) else (
    echo Nenhum log encontrado.
)
pause
goto informacoes

:infos_sistema
cls
systeminfo
pause
goto informacoes

:: =========================
:: DOWNLOADS
:: =========================
:downloads
cls
echo.
echo ======================================================
echo                      DOWNLOADS
echo ======================================================
echo.
echo Baixando central de downloads...
echo.

del /f /q "%PS_APP%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri '%PS_URL%' -OutFile '%PS_APP%' -UseBasicParsing } catch { exit 1 }"

if not exist "%PS_APP%" (
    echo [X] Falha ao baixar o DownloadsApp.ps1
    echo.
    echo Verifique se o arquivo existe no GitHub:
    echo %PS_URL%
    echo.
    pause
    goto menu
)

echo Abrindo central de downloads...
echo [%date% %time%] Central de downloads aberta>>"%LOG%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_APP%"
goto menu

:sair
exit /b
