# Gamer Ultra — pesquisa e política inicial de ajustes

Estado em 20/10/2026: primeira fatia funcional, limitada e reversível. O restante do catálogo continua em avaliação.

## Política obrigatória

- Não desativar nem alterar serviços Xbox, Xbox Live, Gaming Services, Game Pass, Microsoft Store, Minecraft, Xbox Game Bar ou captura Game DVR.
- Não desativar Firewall do Windows, Microsoft Defender, Windows Update, serviços essenciais de rede, áudio, drivers, impressão, Plug and Play ou RPC.
- Não forçar HAGS, VBS/Integridade da Memória, prioridades de processos, afinidade de CPU, HPET/BCD, NetworkThrottlingIndex, SystemResponsiveness, pagefile, compressão de memória, TRIM ou tarefas de manutenção do SSD sem teste específico que justifique a alteração.
- Não prometer ganho de FPS sem medição repetível. FPS médio sozinho não basta: medir frametime e 1% lows; latência deve ser medida quando o jogo/hardware disponibilizar métrica adequada.
- Todo ajuste precisa de pré-visualização, backup próprio do valor original, registro de alterações e reversão. Um ponto de restauração é apenas uma camada adicional de proteção, não substitui o backup específico do Lynext.

## O que foi colocado na primeira etapa

O perfil Gamer Ultra passa a tentar criar um ponto de restauração do Windows, verificando a criação através da consulta de pontos existentes. O usuário pode cancelar ou, após uma confirmação adicional, decidir continuar sem o ponto quando a tentativa falhar ou não for desejada.

A alteração funcional desta versão limita-se às duas opções específicas de ativação automática do Modo de Jogo no perfil atual do usuário do Windows. O Lynext salva os valores originais antes de alterar e inclui o botão **Voltar ao padrão**. A aplicação não mexe em serviços Xbox/Game Pass, Game DVR/capturas, Firewall, Defender, Windows Update, plano de energia, HAGS, RAM, SSD ou serviços do sistema.

A documentação PowerShell da Microsoft indica que `Checkpoint-Computer` é compatível com Windows cliente e não cria mais de um ponto a cada 24 horas. O Lynext precisa confirmar o resultado e mostrar a mensagem de falha sem alegar sucesso.

## Pesquisa e próximos candidatos

1. **Aplicativos de inicialização:** candidatos de alto valor quando realmente ficam residentes ou executam tarefas em segundo plano. Devem ser exibidos para escolha do usuário, não todos desativados automaticamente. A Microsoft descreve como verificar o impacto de inicialização no Gerenciador de Tarefas.
2. **Otimizações gráficas do Windows 11:** a opção “Otimizações para jogos em janela” beneficia certos jogos DirectX 10/11 em janela/sem borda e pode reduzir a latência de apresentação. Deve ser explicada e testada por jogo; nesta primeira etapa abrimos as Configurações gráficas para revisão manual.
3. **NVIDIA Reflex / AMD Radeon Anti-Lag:** usar de forma específica por jogo e apenas quando compatível. Reflex e Anti-Lag não são ajustes universais de registro do Windows.
4. **HAGS, energia e política de CPU:** não existe uma configuração universal comprovada para todo hardware. Deixar o padrão e coletar dados comparáveis antes de sugerir alteração.
5. **Serviços:** só considerar serviço opcional após identificar sua função, dependências e uso no PC. Uma lista popular de debloat não substitui teste de estabilidade.
6. **RAM/SSD:** preservar gerenciamento de memória, paginação, TRIM e otimização programada. Investigar atividade real de fundo ou falta de RAM antes de mexer.

## Fontes

- Microsoft — Configurar aplicativos de inicialização: https://support.microsoft.com/pt-br/windows/experience/startup-boot/configure-startup-applications-in-windows
- Microsoft — Dicas para melhorar o desempenho do PC no Windows: https://support.microsoft.com/pt-br/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows
- Microsoft — Otimizações para jogos em janela no Windows 11: https://support.microsoft.com/en-us/windows/hardware/display-graphics/optimizations-for-windowed-games-in-windows-11
- Microsoft DirectX — página de configurações gráficas e otimizações para jogos em janela: https://devblogs.microsoft.com/directx/navigating-the-redesigned-graphics-settings-page/
- Microsoft PowerShell — Checkpoint-Computer e a limitação diária: https://learn.microsoft.com/pt-br/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1
- NVIDIA — Guia de otimização de latência do sistema e Modo de Jogo: https://www.nvidia.com/pt-br/geforce/guides/system-latency-optimization-guide/
- AMD — Radeon Anti-Lag e Anti-Lag 2, com compatibilidade específica por jogo: https://www.amd.com/pt/products/software/adrenalin/radeon-software-anti-lag.html
- Reddit, r/OptimizedGaming — guia comunitário atualizado em abril de 2025; recomenda ponto de restauração e alerta para considerar recursos usados: https://www.reddit.com/r/OptimizedGaming/comments/su6cq7/windows_1011_optimization_guide/
- Reddit, r/OptimizedGaming — discussão sobre HAGS e Modo de Jogo; mostra que a recomendação de latência não é unânime: https://www.reddit.com/r/OptimizedGaming/comments/1hz4hzo/
- Microsoft Learn — o Firewall do Windows não deve ser desativado para tentar otimizar o PC: https://learn.microsoft.com/pt-br/windows/security/operating-system-security/network-security/windows-firewall/

## Método de validação para as próximas versões

- Registrar versão/build do Windows, CPU/GPU, RAM, drivers e estado anterior de cada ajuste.
- Repetir o mesmo cenário de jogo e as mesmas condições de energia/temperatura antes e depois.
- Acompanhar FPS médio, 1% lows, frametime p95/p99 e latência quando mensurável.
- Alterar poucas variáveis por rodada e reverter qualquer mudança sem benefício repetível ou que afete estabilidade/compatibilidade.
