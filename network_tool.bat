@echo off
title Lynext Network Tool PRO
color 0A

:: =========================
:: ADMIN
:: =========================
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Elevando privilegios...
    powershell -Command "Start-Process cmd -ArgumentList '/c %~s0' -Verb RunAs"
    exit
)

:menu
cls
echo =====================================
echo              L Y N E X T
echo =====================================
echo.
echo 1 - REDE
echo 2 - OTIMIZACAO
echo 3 - TESTES
echo 0 - SAIR
echo.

choice /c 1230 /n /m "Escolha: "

if errorlevel 4 exit
if errorlevel 3 goto testes
if errorlevel 2 goto otim
if errorlevel 1 goto rede
goto menu

:: =========================
:: REDE
:: =========================
:rede
cls
echo ===== REDE =====
echo.
echo 1 - Renovar IP
echo 2 - Limpar DNS
echo 3 - Reset completo
echo 4 - MTU AUTOMATICO
echo 5 - DNS AUTOMATICO
echo 0 - Voltar
echo.

choice /c 123450 /n

if errorlevel 6 goto menu
if errorlevel 5 goto dns
if errorlevel 4 goto mtu
if errorlevel 3 goto reset
if errorlevel 2 goto flush
if errorlevel 1 goto renovar
goto rede

:renovar
ipconfig /release
ipconfig /renew
pause
goto rede

:flush
ipconfig /flushdns
pause
goto rede

:reset
netsh winsock reset
netsh int ip reset
pause
goto rede

:: =========================
:: MTU AUTOMATICO (PRECISO)
:: =========================
:mtu
cls
echo =====================================
echo      BUSCANDO MTU IDEAL
echo =====================================
echo.

set target=google.com
set mtu=1472

:mtu_loop
echo Testando: %mtu%
ping %target% -f -l %mtu% -n 1 >nul

if errorlevel 1 (
    set /a mtu=%mtu%-1
    goto mtu_loop
)

set /a final=%mtu%+28

echo.
echo MTU IDEAL: %final%
echo.

for /f "tokens=2 delims=:" %%i in ('netsh interface show interface ^| findstr /i "Connected"') do set iface=%%i
set iface=%iface:~1%

echo Aplicando MTU...
netsh interface ipv4 set subinterface "%iface%" mtu=%final% store=persistent

echo Concluido!
pause
goto rede

:: =========================
:: DNS AUTOMATICO (CORRETO)
:: =========================
:dns
cls
echo =====================================
echo       TESTE AUTOMATICO DNS
echo =====================================
echo.

call :ping 8.8.8.8 g Google
call :ping 1.1.1.1 c Cloudflare
call :ping 9.9.9.9 q Quad9

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
echo.

for /f "tokens=2 delims=:" %%i in ('netsh interface show interface ^| findstr /i "Connected"') do set iface=%%i
set iface=%iface:~1%

echo Aplicando DNS...
netsh interface ip set dns name="%iface%" static %best%

echo Concluido!
pause
goto rede

:: =========================
:: FUNCAO PING
:: =========================
:ping
set ip=%1
set var=%2

set val=999
for /f "tokens=6 delims== " %%a in ('ping -n 2 %ip% ^| findstr /i "Average Média"') do set val=%%a

set val=%val:ms=%
set %var%=%val%

echo %3: %val% ms
goto :eof

:: =========================
:: OTIMIZACAO
:: =========================
:otim
cls
echo ===== OTIMIZACAO =====
echo.
echo 1 - Alto desempenho
echo 2 - SFC
echo 3 - DISM
echo 0 - Voltar
echo.

choice /c 1230 /n

if errorlevel 4 goto menu
if errorlevel 3 goto dism
if errorlevel 2 goto sfc
if errorlevel 1 goto perf
goto otim

:perf
powercfg -setactive SCHEME_MIN
pause
goto otim

:sfc
sfc /scannow
pause
goto otim

:dism
DISM /Online /Cleanup-Image /RestoreHealth
pause
goto otim

:: =========================
:: TESTES
:: =========================
:testes
cls
echo ===== TESTES =====
echo.
echo 1 - Ping Google
echo 2 - Ping Cloudflare
echo 0 - Voltar
echo.

choice /c 120 /n

if errorlevel 3 goto menu
if errorlevel 2 goto ping_cf
if errorlevel 1 goto ping_google
goto testes

:ping_google
ping google.com
pause
goto testes

:ping_cf
ping 1.1.1.1
pause
goto testes
