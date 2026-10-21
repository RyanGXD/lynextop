<p align="center">
  <img src="https://yt3.ggpht.com/yti/APfAmoGOMyd1XqfD-A7GdH6ZROEQTHhlDXUCNLUysvZ9=s108-c-k-c0x00ffffff-no-rj" width="128" height="128"/>
</p>

# Lynext Optimizer

Ferramenta para Windows focada em diagnóstico, controle de configurações e otimização segura, com uma interface desktop em desenvolvimento.

## ⬇️ Download — Windows Beta

**[Abrir Downloads / Releases do Lynext](https://github.com/RyanGXD/lynextop/releases)**

Na versão Beta mais recente, abra **Assets** e baixe o instalador `Lynext-Setup-<versão>-x64.exe`. O arquivo `.sha256` ao lado contém o checksum para verificar a integridade do download.

**Importante:** não baixe `Source code.zip` ou `Source code.tar.gz` para instalar o aplicativo. Esses arquivos contêm o código-fonte, não o instalador. Se a versão mais recente ainda não mostrar o arquivo `.exe` em **Assets**, a publicação do instalador ainda não terminou ou essa Release não foi gerada corretamente.

Esta versão é Beta e deve ser testada com cautela. Revise as alterações antes de aplicá-las e mantenha cópia dos dados importantes.

## Sobre o projeto

O Lynext busca reunir ferramentas de diagnóstico, gerenciamento de energia e configurações do Windows em uma interface modular e fácil de usar.

O projeto mantém também módulos antigos em PowerShell, listados abaixo. Eles são distintos da nova aplicação desktop WPF.

## Estrutura PowerShell legada

- `lynext.ps1` — loader principal
- `MainMenu.ps1` — menu principal
- `NetworkApp.ps1` — módulo de rede
- `DownloadsApp.ps1` — módulo de downloads
- `PerformanceApp.ps1` — módulo de desempenho

Para executar o loader legado pelo PowerShell:

```powershell
irm https://raw.githubusercontent.com/RyanGXD/lynextop/main/lynext.ps1 | iex
```

O loader baixa os módulos para uma pasta temporária do Windows e abre o menu principal.
