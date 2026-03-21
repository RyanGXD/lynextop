@echo off
title Lynext Optimization
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

:: =========================
:: HEADER
:: =========================
:header
color 0B
echo ============================================
echo           LYNEXT OPTIMIZATION
echo        Network ^& System Toolkit
echo ============================================
color 0A
goto :eof

:menu
cls
call :header
echo.

color 0F
echo [1] 
color 0A
echo  REDE

color 0F
echo [2] 
color 0A
echo  OTIMIZACAO

color 0F
echo [3] 
color 0A
echo  TESTES

color 0F
echo [0] 
color 0A
echo  SAIR
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
call :header
echo ===== REDE =====
echo.

color 0F & echo [1] & color 0A & echo  Renovar IP
color 0F & echo [2] & color 0A & echo  Limpar DNS
color 0F & echo [3] & color 0A & echo  Reset completo
color 0F & echo [4] & color 0A & echo  MTU AUTOMATICO
color 0F & echo [5] & color 0A & echo  DNS AUTOMATICO
color 0F & echo [0] & color 0A & echo  Voltar
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
:: SELECIONAR INTERFACE
:: =========================
:select_interface
cls
call :header
echo SELECIONE A INTERFACE DE REDE
echo.

netsh interface ipv4 show interfaces

echo.
set /p idx=Digite o NUMERO (Idx): 

if "%idx%"=="" (
    echo [ERRO] Entrada invalida
    pause
    goto rede
)

set iface=

for /f "tokens=1,2,3*" %%a in ('netsh interface ipv4 show interfaces') do (
    if "%%a"=="%idx%" set iface=%%d
)

if "%iface%"=="" (
    echo [ERRO] Interface nao encontrada
    pause
    goto rede
)

echo Interface escolhida: "%iface%"
pause
goto :eof

:: =========================
:: MTU
:: =========================
:mtu
cls
call :header
echo BUSCANDO MTU IDEAL...
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

call :select_interface

echo Aplicando MTU...
netsh interface ipv4 set subinterface "%iface%" mtu=%final% store=persistent

echo Concluido!
pause
goto rede

:: =========================
:: DNS
:: =========================
:dns
cls
call :header
echo TESTE AUTOMATICO DNS
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

call :select_interface

echo Aplicando DNS...
netsh interface ip set dns name="%iface%" static %best%

echo Concluido!
pause
goto rede

:: =========================
:: PING
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
call :header
echo OTIMIZACAO
echo.

color 0F & echo [1] & color 0A & echo  Alto desempenho
color 0F & echo [2] & color 0A & echo  SFC
color 0F & echo [3] & color 0A & echo  DISM
color 0F & echo [0] & color 0A & echo  Voltar
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
call :header
echo TESTES
echo.

color 0F & echo [1] & color 0A & echo  Ping Google
color 0F & echo [2] & color 0A & echo  Ping Cloudflare
color 0F & echo [0] & color 0A & echo  Voltar
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
