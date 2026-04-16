<p align="center">
<img src="https://yt3.ggpht.com/yti/APfAmoGOMyd1XqfD-A7GdH6ZROEQTHhlDXUCNLUysvZ9=s108-c-k-c0x00ffffff-no-rj" width="128" height="128"/>
</p>
<p align="center">

# Lynext

Uma ferramenta modular para Windows focada em **rede**, **downloads**, **diagnostico** e **otimizacao**, com interface propria em PowerShell.

---

## Author

**Created by Ryan**

---

## Sobre o projeto

O **Lynext** foi criado para reunir ferramentas uteis em um so lugar, com uma interface mais limpa e facil de usar.

A proposta do projeto e ser uma central de suporte e ajustes para Windows, trazendo recursos de:
- rede
- reparo
- diagnostico
- downloads
- desempenho

Tudo organizado em modulos separados, deixando o projeto mais bonito, escalavel e profissional.

---

## Estrutura atual

Atualmente o Lynext funciona com uma estrutura modular:

- `lynext.ps1` -> loader principal
- `MainMenu.ps1` -> menu principal
- `NetworkApp.ps1` -> modulo de rede
- `DownloadsApp.ps1` -> modulo de downloads
- `PerformanceApp.ps1` -> modulo de desempenho

---

## Como usar

### Executar pelo PowerShell
Use o comando abaixo:

```powershell
irm https://raw.githubusercontent.com/RyanGXD/lynextop/main/lynext.ps1 | iex
