@echo off
title Lynext Network Tool PRO
color 0A

:: =========================
:: ADMIN
:: =========================
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo.
    echo [!] Elevando privilegios...
    timeout /t 2 >nul
    powershell -Command "Start-Process cmd -ArgumentList '/c %~s0' -Verb RunAs"
    exit
)

:menu
cls
echo.
echo =========================================
echo              L Y N E X T
echo =========================================
echo.
echo  [1] REDE
echo  [2] OTIMIZACAO
echo  [3] TESTES
echo.
echo  [0] SAIR
echo.

choice /c 1230 /n /m "Escolha: "

if errorlevel 4 exit
if errorlevel 3 goto test_menu
if errorlevel 2 goto opt_menu
if errorlevel 1 goto rede_menu
goto menu

:: =========================
:: REDE
:: =========================
:rede_menu
cls
echo.
echo ===== REDE =====
echo.
echo  [1] Renovar IP
echo  [2] Limpar DNS
echo  [3] Reset completo de rede
echo  [4] MTU AUTOMATICO
echo  [5] DNS AUTOMATICO
echo.
echo  [0] Voltar
echo.

choice /c 123450 /n /m "Escolha: "

if errorlevel 6 goto menu
if errorlevel 5 goto dns_auto
if errorlevel 4 goto mtu_auto
if errorlevel 3 goto reset_rede
if errorlevel 2 goto limpar_dns
if errorlevel 1 goto renovar_ip
goto rede_menu

:renovar_ip
ipconfig /release
ipconfig /renew
pause
goto rede_menu

:limpar_dns
ipconfig /flushdns
pause
goto rede_menu

:reset_rede
netsh winsock reset
netsh int ip reset
pause
goto rede_menu

:: =========================
:: MTU AUTOMATICO (PRECISO)
:: =========================
:mtu_auto
cls
echo.
echo =========================================
echo        BUSCANDO MTU IDEAL
echo =========================================
echo.

set target=google.com
set mtu=1472

:: =========================
:: FASE 1 - BUSCA RAPIDA
:: =========================
echo [FASE 1] BUSCA RAPIDA...

:fast_search
ping %target% -f -l %mtu% -n 1 >nul
echo Testando: %mtu%

if errorlevel 1 (
    set /a mtu=%mtu%-10
    goto fast_search
)

:: =========================
:: FASE 2 - AJUSTE FINO
:: =========================
echo.
echo [FASE 2] AJUSTE FINO...

set /a mtu=%mtu%+10

:fine_search
set /a mtu=%mtu%-1
ping %target% -f -l %mtu% -n 1 >nul
echo Refinando: %mtu%

if errorlevel 1 goto fine_search

set /a final=%mtu%+28

echo.
echo =========================================
echo MTU IDEAL: %final%
echo =========================================
echo.

:: aplicar
for /f "tokens=2 delims=:" %%i in ('netsh interface show interface ^| findstr /i "Connected"') do set interface=%%i
set interface=%interface:~1%

echo Interface: %interface%
echo Aplicando MTU...
netsh interface ipv4 set subinterface "%interface%" mtu=%final% store=persistent >nul 2>&1

echo MTU aplicado com sucesso.
pause
goto rede_menu

:: =========================
:: DNS AUTOMATICO
:: =========================
:dns_auto
cls
echo.
echo =========================================
echo        TESTE AUTOMATICO DE DNS
echo =========================================
echo.

call :get_ping 8.8.8.8 g Google
call :get_ping 1.1.1.1 c Cloudflare
call :get_ping 9.9.9.9 q Quad9

echo.
echo RESULTADOS:
echo Google:      %g% ms
echo Cloudflare:  %c% ms
echo Quad9:       %q% ms
echo.

set best=8.8.8.8
set bestv=%g%

if %c% LSS %bestv% (
    set best=1.1.1.1
    set bestv=%c%
)

if %q% LSS %bestv% (
    set best=9.9.9.9
    set bestv=%q%
)

echo Melhor DNS: %best% (%bestv% ms)

for /f "tokens=2 delims=:" %%i in ('netsh interface show interface ^| findstr /i "Connected"') do set interface=%%i
set interface=%interface:~1%

echo Aplicando DNS...
netsh interface ip set dns name="%interface%" static %best% >nul 2>&1

echo DNS aplicado com sucesso.
pause
goto rede_menu

:get_ping
set ip=%1
set var=%2
set nome=%3

echo Testando %nome%...

set temp=999
for /f "tokens=6 delims== " %%a in ('ping -n 2 %ip% ^| findstr /i "Average Média"') do set temp=%%a

set temp=%temp:ms=%
set %var%=%temp%

echo %nome%: %temp% ms
echo.
goto :eof

:: =========================
:: OTIMIZACAO
:: =========================
:opt_menu
cls
echo.
echo ===== OTIMIZACAO =====
echo.
echo  [1] Desempenho maximo
echo  [2] SFC
echo  [3] DISM
echo.
echo  [0] Voltar
echo.

choice /c 1230 /n /m "Escolha: "

if errorlevel 4 goto menu
if errorlevel 3 goto dism
if errorlevel 2 goto sfc
if errorlevel 1 goto desempenho
goto opt_menu

:desempenho
powercfg -setactive SCHEME_MIN
pause
goto opt_menu

:sfc
sfc /scannow
pause
goto opt_menu

:dism
DISM /Online /Cleanup-Image /RestoreHealth
pause
goto opt_menu

:: =========================
:: TESTES
:: =========================
:test_menu
cls
echo.
echo ===== TESTES =====
echo.
echo  [1] Ping Google
echo  [2] Ping Cloudflare
echo.
echo  [0] Voltar
echo.

choice /c 120 /n /m "Escolha: "

if errorlevel 3 goto menu
if errorlevel 2 goto ping_cf
if errorlevel 1 goto ping_google
goto test_menu

:ping_google
ping google.com
pause
goto test_menu

:ping_cf
ping 1.1.1.1
pause
goto test_menu
