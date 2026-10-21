# Compilar o Lynext Desktop

Esta branch inicia a reconstrução do Lynext como aplicativo desktop WPF para Windows. O código atual é uma base inicial: mostra a interface, identifica CPU/GPU via WMI e permite selecionar perfis demonstrativos. **Ainda não aplica otimizações.**

## Requisitos para desenvolvimento

- Windows 10/11 x64
- .NET 8 SDK
- Inno Setup 6 para gerar o instalador `.setup.exe`

## Gerar o aplicativo e o instalador

Na raiz do repositório, abra o PowerShell e execute:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\build-installer.ps1
```

O script publica uma versão self-contained para Windows x64 e tenta criar o instalador com Inno Setup. O resultado esperado é:

- `artifacts/publish/Lynext.exe`
- `artifacts/Lynext-Setup-0.1.0-x64.exe`

O runtime .NET é incluído na publicação self-contained, então o usuário final não precisa instalar o .NET separadamente. Para compilar e empacotar, o desenvolvedor ainda precisa dos requisitos acima.

## Princípios de segurança

- O aplicativo inicia sem privilégios elevados.
- Nenhuma otimização é aplicada nesta versão inicial.
- Não baixar e executar scripts mutáveis da branch `main` durante a inicialização.
- Solicitar elevação somente para ações específicas que realmente precisem de administrador.
- Antes de cada alteração futura, mostrar efeito esperado, risco, estado atual, compatibilidade e estratégia de restauração.
- Mudanças irreversíveis ou cuja restauração não possa ser garantida devem ser identificadas claramente.
