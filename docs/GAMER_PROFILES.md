# Perfis Gamer e Gamer Ultra — estado da implementação

**Estado:** primeira etapa implementada na branch `rebuild/desktop-installer`. A compilação e os testes do CI devem ser consultados para o commit atual; ainda não foi feita validação funcional em um PC físico nesta tarefa.

## O que está implementado

### Gamer
- Verifica o estado do Modo de Jogo do Windows para o usuário atual.
- Se o valor documentado `AutoGameModeEnabled` não estiver habilitado, salva o estado anterior e habilita o Modo de Jogo.
- Se ele já estiver habilitado, informa que não precisou modificar esse valor.
- Não altera o plano de energia.

### Gamer Ultra
- Inclui o comportamento do perfil Gamer.
- Oferece uma confirmação separada para tentar ativar o plano de energia Windows **Alto desempenho**, apenas se esse plano estiver listado no computador.
- Informa que o plano pode elevar consumo, temperatura e ruído e não promete ganho de FPS.
- Se o plano não estiver disponível, informa isso e mantém a configuração de energia inalterada.

## Persistência, verificação e reversão

Os dados do perfil são salvos em `%LOCALAPPDATA%\Lynext\Profiles\GamerUltra`. O histórico fica em `%LOCALAPPDATA%\Lynext\Logs\optimization-history.jsonl`.

- `backup.json`: valor anterior de `AutoGameModeEnabled`, incluindo se a entrada existia.
- `power-backup.json`: GUID do plano ativo antes da troca e GUID do plano ativado pelo Lynext.
- `active-profile.json`: nome do último perfil aplicado e informações de estado.

Os backups são gravados por arquivo temporário e renomeação. O código lê o estado depois da alteração; o sucesso do comando sozinho não basta. Antes da restauração, compara o estado atual com o original ou com o valor aplicado pelo Lynext. Se detectar uma mudança externa que não consegue distinguir com segurança, interrompe a reversão em vez de sobrescrever a escolha silenciosamente. Os backups só são apagados depois de confirmar a restauração dos ajustes gerenciados.

## Recursos explicitamente preservados

Esta fase não desativa nem altera Xbox, Xbox Live, Gaming Services, Xbox Identity Provider, Game Pass, Microsoft Store, Minecraft, Xbox Game Bar, Game DVR/capturas, Defender, Firewall, Windows Update, SmartScreen, UAC, VBS, Integridade da Memória, Secure Boot ou serviços essenciais. Também não altera BCD, HPET, timers, paginação, compressão de memória, afinidade/prioridade de processos, rede, overclock, undervolt, HAGS, configurações por jogo ou inicialização automática.

## Limitações da fase

- O plano Alto desempenho pode não estar instalado ou pode não ser aplicável à política de energia do computador.
- O perfil de energia só troca o plano ativo; não edita cada opção individual de energia.
- Os botões de configurações gráficas e aplicativos de inicialização abrem as páginas nativas do Windows. O Lynext não gerencia as entradas de inicialização automaticamente.
- Não há ainda benchmark automatizado ou alegação medida de melhoria de FPS, 1% lows, frametime ou latência.
- Lite, Empresarial e Economia ainda não têm aplicação de ajustes nesta fase.
- Compilação não equivale a teste funcional no hardware real. Verifique a execução em um ambiente Windows de teste antes de distribuir a versão.

## Teste manual sugerido

1. Use uma máquina de teste e confirme que Xbox, Minecraft, Game Pass, segurança, rede, áudio e periféricos continuam funcionando.
2. Registre o plano de energia ativo e o estado inicial do Modo de Jogo.
3. Ative Gamer e confirme a leitura posterior e o backup.
4. Se o plano Alto desempenho existir, teste Gamer Ultra optando por não o ativar e depois aceitando a opção.
5. Ative Gamer após Ultra e confirme que o plano original é restaurado se o estado ainda corresponder ao que o Lynext gerencia.
6. Use Voltar ao padrão e confirme que as configurações retornaram aos valores originais.
7. Altere manualmente o plano de energia depois de aplicar Ultra e confirme que o Lynext detecta o conflito e não o sobrescreve silenciosamente.
8. Revise o histórico e confirme que falhas e reversões parciais não são registradas como sucesso.

## Próxima etapa recomendada

Adicionar testes automatizados com dependências de sistema simuladas, abstraindo Registro e `powercfg`; depois, ampliar diagnóstico de energia/hardware e criar uma experiência de análise/previsão antes de pensar em benchmarks integrados ou novas otimizações.
