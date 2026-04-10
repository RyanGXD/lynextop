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
echo.
echo  [0] SAIR
echo.

choice /c 123450 /n /m "Escolha: "

if errorlevel 6 exit
if errorlevel 5 goto info_menu
if errorlevel 4 goto competitivo_menu
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
echo ==================== REDE ====================
echo.
echo  [1] Renovar IP
echo  [2] Limpar DNS
echo  [3] Reset completo de rede
echo  [4] DNS AUTOMATICO
echo  [5] Mostrar interface ativa
echo.
echo  [0] Voltar
echo.

choice /c 123450 /n /m "Escolha: "

if errorlevel 6 goto menu
if errorlevel 5 goto mostrar_interface
if errorlevel 4 goto dns_auto
if errorlevel 3 goto reset_rede
if errorlevel 2 goto limpar_dns
if errorlevel 1 goto renovar_ip
goto rede_menu

:renovar_ip
cls
echo.
echo [*] Liberando IP...
ipconfig /release
echo.
echo [*] Renovando IP...
ipconfig /renew
echo.
call :log "Renovacao de IP executada"
pause
goto rede_menu

:limpar_dns
cls
echo.
echo [*] Limpando cache DNS...
ipconfig /flushdns
echo.
call :log "Flush DNS executado"
pause
goto rede_menu

:reset_rede
cls
echo.
echo [*] Resetando Winsock...
netsh winsock reset
echo.
echo [*] Resetando pilha IP...
netsh int ip reset
echo.
call :log "Reset completo de rede executado"
pause
goto rede_menu

:mostrar_interface
cls
echo.
echo ================= INTERFACE ATIVA =================
echo.
call :get_interface
if not defined interface (
    echo [!] Nenhuma interface ativa encontrada.
) else (
    echo Interface ativa: %interface%
)
echo.
pause
goto rede_menu

:: =========================
:: DNS AUTOMATICO
:: =========================
:dns_auto
cls
echo.
echo ======================================================
echo                TESTE AUTOMATICO DE DNS
echo ======================================================
echo.

call :get_interface
if not defined interface (
    echo [!] Nao foi possivel detectar interface ativa.
    pause
    goto rede_menu
)

echo Interface detectada: %interface%
echo.

call :test_ping 8.8.8.8 g "Google DNS"
call :test_ping 1.1.1.1 c "Cloudflare DNS"
call :test_ping 9.9.9.9 q "Quad9 DNS"

echo.
echo ==================== RESULTADOS ====================
echo  Google:      %g% ms
echo  Cloudflare:  %c% ms
echo  Quad9:       %q% ms
echo.

set "best=8.8.8.8"
set "bestv=%g%"

if %c% lss %bestv% (
    set "best=1.1.1.1"
    set "bestv=%c%"
)

if %q% lss %bestv% (
    set "best=9.9.9.9"
    set "bestv=%q%"
)

echo Melhor DNS encontrado: %best% (%bestv% ms)
echo.
echo [*] Aplicando DNS na interface...
netsh interface ip set dns name="%interface%" static %best% >nul 2>&1

if %errorlevel% equ 0 (
    echo [OK] DNS aplicado com sucesso.
    call :log "DNS automatico aplicado: %best% na interface %interface%"
) else (
    echo [ERRO] Falha ao aplicar DNS.
    call :log "Falha ao aplicar DNS automatico"
)

echo.
pause
goto rede_menu

:test_ping
setlocal
set "ip=%~1"
set "var=%~2"
set "nome=%~3"
set "temp=999"

echo Testando %nome%...

for /f "tokens=2 delims== " %%a in ('ping -n 3 %ip% ^| findstr /i "Average Media"') do (
    set "temp=%%a"
)

set "temp=%temp:ms=%"
set "temp=%temp: =%"

endlocal & set "%var%=%temp%"
echo %nome%: %temp% ms
echo.
goto :eof

:get_interface
set "interface="
for /f "skip=3 tokens=1,2,3,*" %%a in ('netsh interface show interface') do (
    if /i "%%a %%b"=="Enabled Connected" set "interface=%%d"
    if /i "%%a %%b"=="Habilitado Conectado" set "interface=%%d"
)
goto :eof

:: =========================
:: OTIMIZACAO
:: =========================
:opt_menu
cls
echo.
echo ================= OTIMIZACAO =================
echo.
echo  [1] Desempenho maximo
echo  [2] SFC
echo  [3] DISM
echo  [4] Limpar arquivos temporarios
echo.
echo  [0] Voltar
echo.

choice /c 12340 /n /m "Escolha: "

if errorlevel 5 goto menu
if errorlevel 4 goto limpar_temp
if errorlevel 3 goto dism
if errorlevel 2 goto sfc
if errorlevel 1 goto desempenho
goto opt_menu

:desempenho
cls
echo.
echo [*] Ativando plano de alto desempenho...
powercfg -setactive SCHEME_MIN
if %errorlevel% equ 0 (
    echo [OK] Plano ativado.
    call :log "Plano de desempenho maximo ativado"
) else (
    echo [ERRO] Nao foi possivel ativar o plano.
    call :log "Falha ao ativar desempenho maximo"
)
echo.
pause
goto opt_menu

:sfc
cls
echo.
echo [*] Executando SFC...
sfc /scannow
echo.
call :log "SFC executado"
pause
goto opt_menu

:dism
cls
echo.
echo [*] Executando DISM...
DISM /Online /Cleanup-Image /RestoreHealth
echo.
call :log "DISM executado"
pause
goto opt_menu

:limpar_temp
cls
echo.
echo [*] Limpando arquivos temporarios...
del /f /s /q "%temp%\*" >nul 2>&1
echo [OK] Limpeza concluida.
call :log "Arquivos temporarios removidos"
echo.
pause
goto opt_menu

:: =========================
:: TESTES
:: =========================
:test_menu
cls
echo.
echo ==================== TESTES ====================
echo.
echo  [1] Ping Google
echo  [2] Ping Cloudflare
echo  [3] Teste de internet
echo.
echo  [0] Voltar
echo.

choice /c 1230 /n /m "Escolha: "

if errorlevel 4 goto menu
if errorlevel 3 goto teste_internet
if errorlevel 2 goto ping_cf
if errorlevel 1 goto ping_google
goto test_menu

:ping_google
cls
echo.
ping google.com
echo.
call :log "Ping Google executado"
pause
goto test_menu

:ping_cf
cls
echo.
ping 1.1.1.1
echo.
call :log "Ping Cloudflare executado"
pause
goto test_menu

:teste_internet
cls
echo.
echo [*] Testando conectividade...
ping 8.8.8.8 -n 2 >nul
if %errorlevel% equ 0 (
    echo [OK] Internet funcionando.
    call :log "Teste de internet: OK"
) else (
    echo [ERRO] Sem resposta da internet.
    call :log "Teste de internet: FALHA"
)
echo.
pause
goto test_menu

:: =========================
:: COMPETITIVO
:: =========================
:competitivo_menu
cls
echo.
echo ================= COMPETITIVO =================
echo.
echo  [1] Aplicar modo competitivo
echo  [2] Restaurar padrao
echo.
echo  [0] Voltar
echo.

choice /c 120 /n /m "Escolha: "

if errorlevel 3 goto menu
if errorlevel 2 goto competitivo_restore
if errorlevel 1 goto competitivo_apply
goto competitivo_menu

:competitivo_apply
cls
echo.
echo =========================================
echo         APLICANDO MODO COMPETITIVO
echo =========================================
echo.

echo [1/6] Desativando aceleracao do mouse...
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseSensitivity /t REG_SZ /d 10 /f >nul

echo [2/6] Ajustando teclado para resposta maxima...
reg add "HKCU\Control Panel\Keyboard" /v KeyboardDelay /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Keyboard" /v KeyboardSpeed /t REG_SZ /d 31 /f >nul

echo [3/6] Desativando Sticky Keys...
reg add "HKCU\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 506 /f >nul

echo [4/6] Desativando Toggle Keys...
reg add "HKCU\Control Panel\Accessibility\ToggleKeys" /v Flags /t REG_SZ /d 58 /f >nul

echo [5/6] Desativando Filter Keys...
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v Flags /t REG_SZ /d 122 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v DelayBeforeAcceptance /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v AutoRepeatDelay /t REG_SZ /d 200 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v AutoRepeatRate /t REG_SZ /d 20 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v BounceTime /t REG_SZ /d 0 /f >nul

echo [6/6] Desativando Mouse Keys e rastro do mouse...
reg add "HKCU\Control Panel\Accessibility\MouseKeys" /v Flags /t REG_SZ /d 0 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseTrails /t REG_SZ /d 0 /f >nul

echo.
echo =========================================
echo MODO COMPETITIVO APLICADO
echo =========================================
echo.
echo Recomenda-se sair da conta ou reiniciar o PC.
call :log "Modo competitivo aplicado"
pause
goto competitivo_menu

:competitivo_restore
cls
echo.
echo =========================================
echo         RESTAURANDO PADRAO
echo =========================================
echo.

echo [1/6] Restaurando mouse padrao...
reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 1 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 6 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 10 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseSensitivity /t REG_SZ /d 10 /f >nul

echo [2/6] Restaurando teclado padrao...
reg add "HKCU\Control Panel\Keyboard" /v KeyboardDelay /t REG_SZ /d 1 /f >nul
reg add "HKCU\Control Panel\Keyboard" /v KeyboardSpeed /t REG_SZ /d 31 /f >nul

echo [3/6] Restaurando Sticky Keys...
reg add "HKCU\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 510 /f >nul

echo [4/6] Restaurando Toggle Keys...
reg add "HKCU\Control Panel\Accessibility\ToggleKeys" /v Flags /t REG_SZ /d 62 /f >nul

echo [5/6] Restaurando Filter Keys...
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v Flags /t REG_SZ /d 126 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v DelayBeforeAcceptance /t REG_SZ /d 1000 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v AutoRepeatDelay /t REG_SZ /d 1000 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v AutoRepeatRate /t REG_SZ /d 500 /f >nul
reg add "HKCU\Control Panel\Accessibility\Keyboard Response" /v BounceTime /t REG_SZ /d 0 /f >nul

echo [6/6] Restaurando Mouse Keys e rastro do mouse...
reg add "HKCU\Control Panel\Accessibility\MouseKeys" /v Flags /t REG_SZ /d 62 /f >nul
reg add "HKCU\Control Panel\Mouse" /v MouseTrails /t REG_SZ /d 0 /f >nul

echo.
echo =========================================
echo PADRAO RESTAURADO
echo =========================================
echo.
echo Recomenda-se sair da conta ou reiniciar o PC.
call :log "Modo competitivo restaurado ao padrao"
pause
goto competitivo_menu

:: =========================
:: INFORMACOES
:: =========================
:info_menu
cls
echo.
echo ================== INFORMACOES ==================
echo.
call :get_interface
echo Interface ativa: %interface%
echo Computador: %computername%
echo Usuario: %username%
echo Log: %LOG%
echo.
pause
goto menu

:log
echo [%date% %time%] %~1>>"%LOG%"
goto :eof
