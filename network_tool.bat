@echo off
title Lynext Optimization
setlocal EnableDelayedExpansion

:: ADMIN
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c %~s0' -Verb RunAs"
    exit
)

:: =========================
:: MENU PRINCIPAL
:: =========================
:menu
cls
echo =====================================
echo         LYNEXT OPTIMIZATION
echo =====================================
echo.
echo 1 - REDE
echo 2 - OTIMIZACAO
echo 3 - TESTES
echo 0 - SAIR
echo.

choice /c 1230 /n

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
echo 4 - MTU
echo 5 - DNS AUTOMATICO
echo 0 - Voltar
echo.

choice /c 123450 /n

if errorlevel 6 goto menu
if errorlevel 5 goto dns
if errorlevel 4 goto mtu_menu
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
:: MTU MENU
:: =========================
:mtu_menu
cls
echo ===== MTU =====
echo.
echo 1 - MTU ANALYZER
echo 2 - MTU ALTERAR
echo 0 - Voltar
echo.

choice /c 120 /n

if errorlevel 3 goto rede
if errorlevel 2 goto mtu_set
if errorlevel 1 goto mtu_analyzer
goto mtu_menu

:: =========================
:: MTU ANALYZER
:: =========================
:mtu_analyzer
cls
echo ===============================
echo        MTU ANALYZER
echo ===============================
echo.

for /f "skip=3 tokens=1,2,3,4,*" %%a in ('netsh interface show interface') do (
    if /i "%%b"=="Connected" (
        echo %%e | findstr /i "Loopback" >nul
        if errorlevel 1 (
            call :test_mtu "%%e"
        )
    )
)

echo.
echo Analise concluida!
pause
goto mtu_menu

:: =========================
:: TESTE DE MTU INDIVIDUAL
:: =========================
:test_mtu
set iface=%~1

echo -------------------------------
echo Interface: %iface%
echo -------------------------------

set target=google.com
set mtu=1472

:loop_mtu
ping %target% -f -l %mtu% -n 1 >nul

if errorlevel 1 (
    set /a mtu-=1
    goto loop_mtu
)

set /a final=%mtu%+28

echo MTU ideal: %final%
echo.

goto :eof

:: =========================
:: MTU ALTERAR
:: =========================
:mtu_set
cls
echo ===============================
echo        ALTERAR MTU
echo ===============================
echo.

echo Interfaces disponiveis:
netsh interface ipv4 show interfaces

echo.
set /p iface=Digite o nome da interface: 
set /p mtu=Digite a MTU desejada: 

echo.
echo Aplicando...

netsh interface ipv4 set subinterface "%iface%" mtu=%mtu% store=persistent

echo.
echo Concluido!
pause
goto mtu_menu

:: =========================
:: DNS AUTOMATICO
:: =========================
:dns
cls
echo ===== TESTE DE DNS =====
echo.

call :ping 8.8.8.8 g Google
call :ping 1.1.1.1 c Cloudflare
call :ping 9.9.9.9 q Quad9

echo.
echo RESULTADOS:
echo Google: %g% ms
echo Cloudflare: %c% ms
echo Quad9: %q% ms

set best=8.8.8.8
set bestv=%g%

if %c% LSS %bestv% (set best=1.1.1.1 & set bestv=%c%)
if %q% LSS %bestv% (set best=9.9.9.9 & set bestv=%q%)

echo.
echo Melhor DNS: %best%

echo.
echo Aplicando DNS em Ethernet...
netsh interface ip set dns name="Ethernet" static %best% >nul 2>&1

echo Aplicando DNS em Wi-Fi...
netsh interface ip set dns name="Wi-Fi" static %best% >nul 2>&1

echo.
echo DNS aplicado!
pause
goto rede

:: =========================
:: PING
:: =========================
:ping
set ip=%1
set var=%2

set val=999

for /f "tokens=6 delims== " %%a in ('ping -n 1 %ip% ^| findstr /i "time="') do (
    set val=%%a
)

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
