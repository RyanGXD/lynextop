# Lynext Desktop — início da reconstrução

A branch `rebuild/desktop-installer` contém a primeira base do novo aplicativo Windows.

## Incluído nesta etapa

- Projeto WPF para Windows x64.
- Interface inicial em tema escuro.
- Seletor dos cinco perfis: Gamer Ultra, Gamer, Lite, Empresarial e Economia.
- Detecção básica de processador, adaptadores gráficos e informações do Windows.
- Definição do instalador Inno Setup.
- Script de publicação self-contained.

## Ainda não implementado

- Motor de otimização.
- Catálogo verificado de ajustes.
- Alterações de serviços, processos, registro ou energia.
- Logs persistentes, backups e restauração.
- Benchmark automático antes/depois.

Esta versão é um esqueleto de desenvolvimento, não um otimizador pronto para distribuição. Consulte [docs/BUILDING.md](docs/BUILDING.md) para compilar.
