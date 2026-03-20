@echo off
title Lynext Network Tool PRO
color 0A

:: =========================
:: 🔒 ADMIN
:: =========================
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo [!] Elevando privilegios...
    timeout /t 2 >nul
    powershell -Command "Start-Process cmd -ArgumentList '/c %~s0' -Verb RunAs"
    exit
)

:menu
cls
echo ================================
echo        L Y N E X T
echo ================================
echo.
echo 1 - REDE
echo 2 - OTIMIZACAO
echo 3 - TESTES
echo 0 - SAIR
echo.
set /p escolha=Escolha: 

if "%escolha%"=="1" goto rede_menu
if "%escolha%"=="2" goto opt_menu
if "%escolha%"=="3" goto test_menu
if "%escolha%"=="0" exit
goto menu

:: =========================
:: 🌐 REDE
:: =========================
:rede_menu
cls
echo ===== REDE =====
echo 1 - Reset completo de rede
echo 2 - Renovar IP
echo 3 - Limpar DNS
echo 4 - DNS Google
echo 5 - DNS Cloudflare
echo 6 - MTU AUTOMATICO
echo 0 - Voltar
echo.
set /p escolha=

if "%escolha%"=="1" goto reset_rede
if "%escolha%"=="2" goto renovar_ip
if "%escolha%"=="3" goto limpar_dns
if "%escolha%"=="4" goto dns_google
if "%escolha%"=="5" goto dns_cf
if "%escolha%"=="6" goto mtu_auto
if "%escolha%"=="0" goto menu
goto rede_menu

:reset_rede
call :loading Resetando rede
netsh winsock reset
netsh int ip reset
netcfg -d
call :ok
goto rede_menu

:renovar_ip
call :loading Renovando IP
ipconfig /release
ipconfig /renew
call :ok
goto rede_menu

:limpar_dns
call :loading Limpando DNS
ipconfig /flushdns
call :ok
goto rede_menu

:dns_google
call :loading Aplicando DNS Google
netsh interface ip set dns name="Ethernet" static 8.8.8.8
netsh interface ip add dns name="Ethernet" 8.8.4.4 index=2
call :ok
goto rede_menu

:dns_cf
call :loading Aplicando DNS Cloudflare
netsh interface ip set dns name="Ethernet" static 1.1.1.1
netsh interface ip add dns name="Ethernet" 1.0.0.1 index=2
call :ok
goto rede_menu

:: 🔥 MTU AUTOMATICO
:mtu_auto
cls
echo ========================================
echo     BUSCANDO MTU IDEAL...
echo ========================================
echo.

set target=google.com
set mtu=1472

:mtu_test
ping %target% -f -l %mtu% >nul

if errorlevel 1 (
    set /a mtu=%mtu%-1
    goto mtu_test
)

set /a final_mtu=%mtu%+28

echo MTU IDEAL: %final_mtu%
echo.

:: Detectar interface ativa
for /f "tokens=1,2*" %%a in ('netsh interface show interface ^| findstr /I "Connected"') do (
    set interface=%%c
)

echo Interface detectada: %interface%
echo Aplicando MTU...
echo.

netsh interface ipv4 set subinterface "%interface%" mtu=%final_mtu% store=persistent

call :ok
goto rede_menu

:: =========================
:: ⚡ OTIMIZACAO
:: =========================
:opt_menu
cls
echo ===== OTIMIZACAO =====
echo 1 - Desempenho maximo
echo 2 - Reparar Windows (SFC)
echo 3 - Reparo completo (DISM)
echo 4 - Limpar arquivos temporarios
echo 0 - Voltar
echo.
set /p escolha=

if "%escolha%"=="1" goto desempenho
if "%escolha%"=="2" goto sfc
if "%escolha%"=="3" goto dism
if "%escolha%"=="4" goto temp
if "%escolha%"=="0" goto menu
goto opt_menu

:desempenho
call :loading Ativando desempenho maximo
powercfg -setactive SCHEME_MIN
call :ok
goto opt_menu

:sfc
cls
echo ========================================
echo   VERIFICANDO ARQUIVOS DO SISTEMA...
echo ========================================
echo.
sfc /scannow
pause
goto opt_menu

:dism
cls
echo ========================================
echo   REPARANDO IMAGEM DO WINDOWS...
echo ========================================
echo.
DISM /Online /Cleanup-Image /RestoreHealth
pause
goto opt_menu

:temp
call :loading Limpando arquivos temporarios
del /q /f /s %temp%\* >nul 2>&1
del /q /f /s C:\Windows\Temp\* >nul 2>&1
call :ok
goto opt_menu

:: =========================
:: 🧪 TESTES
:: =========================
:test_menu
cls
echo ===== TESTES =====
echo 1 - Ping Google
echo 2 - Ping Cloudflare
echo 0 - Voltar
echo.
set /p escolha=

if "%escolha%"=="1" goto ping_google
if "%escolha%"=="2" goto ping_cf
if "%escolha%"=="0" goto menu
goto test_menu

:ping_google
ping google.com
pause
goto test_menu

:ping_cf
ping 1.1.1.1
pause
goto test_menu

:: =========================
:: 🔄 LOADING
:: =========================
:loading
cls
echo %~1...
echo.
echo [#         ]
timeout /t 1 >nul
cls
echo %~1...
echo.
echo [#####     ]
timeout /t 1 >nul
cls
echo %~1...
echo.
echo [##########]
timeout /t 1 >nul
goto :eof

:: =========================
:: ✅ OK
:: =========================
:ok
echo.
echo ========================================
echo   [OK] CONCLUIDO COM SUCESSO
echo ========================================
echo.
pause
goto :eof
