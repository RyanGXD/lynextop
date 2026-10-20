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

A alteração funcional desta versão limita-se ao valor de registro documentado `AutoGameModeEnabled`, que corresponde à alternância Modo de Jogo em Configurações > Jogos > Modo de Jogo, no perfil atual do usuário do Windows. O Lynext salva os valores originais antes de alterar e inclui o botão **Voltar ao padrão**. A aplicação não mexe em serviços Xbox/Game Pass, Game DVR/capturas, Firewall, Defender, Windows Update, plano de energia, HAGS, RAM, SSD ou serviços do sistema.

A referência oficial do Windows 11 identifica `AutoGameModeEnabled` como o valor do Registro que corresponde à alternância Modo de Jogo em Configurações > Jogos > Modo de Jogo (https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11). O Lynext não altera o valor adicional `AllowAutoGameMode` porque não é necessário para aplicar essa opção documentada.\n\nA documentação PowerShell da Microsoft indica que `Checkpoint-Computer` é compatível com Windows cliente e não cria mais de um ponto a cada 24 horas. O Lynext precisa confirmar o resultado e mostrar a mensagem de falha sem alegar sucesso.

## Pesquisa consolidada: o que pode trazer benefício real

1. **Aplicativos de inicialização:** primeira candidata para a próxima versão. A Microsoft explica que o Gerenciador de Tarefas classifica impacto com base em CPU e disco durante a inicialização. O Lynext deve mostrar itens e permitir escolha individual, com reversão; não desativar todos automaticamente. Foco em programas de terceiros opcionais, sem alterar serviços.
2. **Otimizações gráficas do Windows 11:** a opção “Otimizações para jogos em janela” pode reduzir a latência de apresentação em jogos DirectX 10/11 compatíveis que usam janela/sem borda. É uma configuração dependente do jogo; a aplicação abre a página gráfica para revisão manual.
3. **NVIDIA Reflex / AMD Radeon Anti-Lag:** aplicar somente nas opções específicas do jogo ou painel de driver compatível. Reflex costuma ser preferível à configuração de baixa latência do driver quando o próprio jogo disponibiliza Reflex. Anti-Lag 2 exige integração do jogo. Não são tweaks universais de registro do Windows.
4. **Configurações de profissionais:** guias atuais de CS2 (947 jogadores profissionais analisados) e VALORANT (701) recomendam principalmente opções específicas de cada jogo e hardware. Isso não valida uma lista universal de serviços do Windows. Não copiar automaticamente a opção de lançamento -high, afinidade de CPU ou launch options: há relatos contraditórios e testes de comunidade que mostram resultado neutro ou pior em algumas máquinas.
5. **HAGS, VBS/Integridade da Memória, energia e política de CPU:** benchmarks publicados e relatos comunitários divergem por geração de CPU/GPU, jogo e versão do Windows. Não desativar recursos de segurança, nem forçar HAGS ou plano de energia, sem oferecer uma opção informada e demonstrar benefício reproduzível no hardware específico.
6. **Serviços do Windows:** sem desativação em massa. Não tocar em Xbox/Xbox Live, Gaming Services, Game Pass, Microsoft Store, Minecraft, Xbox Game Bar, Game DVR/capturas, Firewall, Defender, Windows Update, rede, áudio, drivers, impressão, Plug and Play ou RPC.
7. **RAM/SSD:** preservar arquivo de paginação, compressão de memória, TRIM e otimização programada. Diagnosticar falta de RAM, paginação ou atividade real de disco antes de propor mudança.
8. **Medição:** usar cenários repetíveis e múltiplas capturas. PresentMon e CapFrameX permitem analisar FPS, frametimes, percentis e tempo de apresentação. FPS médio sozinho não é suficiente; comparar 1% lows, distribuição/percentis de frametime e latência quando houver métrica adequada. Manter estado de HAGS e condições térmicas iguais entre testes; as métricas de atividade de GPU do PresentMon têm limitações específicas com HAGS ativado.

## Fontes comunitárias e de medição

- ProSettings — CS2, compilação de preferências de 947 profissionais: https://prosettings.net/guides/cs2-options/
- ProSettings — VALORANT, compilação de preferências de 701 profissionais: https://prosettings.net/guides/valorant-options/
- Reddit — discussão de launch options do CS2, incluindo relatos contraditórios sobre a opção de lançamento -high e outras opções: https://www.reddit.com/r/GlobalOffensive/comments/1gzljbg/which_cs2_launch_options_give_you_a_fps_boost/
- PresentMon — métricas de CPU/GPU/display frame duration e latência: https://github.com/GameTechDev/PresentMon
- CapFrameX — análise de frametimes, percentis e stutter, baseada no PresentMon: https://github.com/CXWorld/CapFrameX
- NVIDIA — guia de latência do sistema: https://www.nvidia.com/pt-br/geforce/guides/system-latency-optimization-guide/
- AMD — Radeon Anti-Lag, cenários GPU-limited e recursos que dependem do jogo: https://www.amd.com/en/resources/support-articles/faqs/DH3-033.html

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
