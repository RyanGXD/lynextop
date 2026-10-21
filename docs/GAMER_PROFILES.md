# Perfis Gamer e Gamer Ultra — estado da implementação

**Estado:** perfis isolados na branch `rebuild/desktop-installer`. Os controles existentes continuam limitados a Game Mode e à opção condicional de plano Alto desempenho. Nenhuma alteração automática em processos, serviços, inicialização ou GPU foi adicionada.

## Separação de perfis e estado apresentado

- A seleção de perfil muda somente a view. O catálogo declara os IDs permitidos por perfil; Lite, Empresarial e Economia não têm operações e mostram apenas o aviso de planejamento.
- Gamer e Gamer Ultra têm painéis e botões de ativação distintos. Game Mode é consultado no Windows. A interface diferencia o valor ativo no Windows da aplicação registrada pelo Lynext.
- Quando a leitura falha ou o conteúdo não é um DWORD 0/1 válido, o estado aparece como não confirmado/desconhecido. Gamer Ultra também reconsulta o plano de energia se o Lynext registrou que o aplicou.
- Se houver um plano Ultra ainda gerenciado, a ativação de Gamer falha com instrução para restaurá-lo primeiro. Assim Gamer não altera nem incorpora silenciosamente o ajuste Ultra.
- Os links de gráficos e inicialização abrem as configurações nativas para revisão manual; não gravam preferências gráficas nem alteram entradas de inicialização.

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



### Política de energia e bateria

A troca automática para o plano Alto desempenho só é tentada quando a consulta WMI `Win32_Battery` confirma que não há bateria. Se uma bateria for detectada ou a consulta falhar, a energia não é alterada; se existir uma mudança de energia previamente gerenciada pelo Lynext, ele tenta voltar ao plano original desde que o estado atual ainda corresponda ao estado que o Lynext gerencia. Isso evita apresentar a troca do plano ativo como se alterasse apenas o comportamento quando o computador está conectado à tomada.

## Limitações da fase

- O plano Alto desempenho pode não estar instalado ou pode não ser aplicável à política de energia do computador.
- O perfil de energia só troca o plano ativo; não edita cada opção individual de energia.
- Os botões de configurações gráficas e aplicativos de inicialização abrem as páginas nativas do Windows. O Lynext não gerencia as entradas de inicialização automaticamente.
- Os testes cobrem o isolamento declarativo e a navegação pura do catálogo; ainda não substituem testes de aplicação/restauração com interfaces simuladas ou validação em hardware Windows real.
- Não há ainda benchmark automatizado ou alegação medida de melhoria de FPS, 1% lows, frametime ou latência.
- Lite, Empresarial e Economia ainda não têm aplicação de ajustes nesta fase.
- Compilação não equivale a teste funcional no hardware real. Verifique a execução em um ambiente Windows de teste antes de distribuir a versão.

## Teste manual sugerido

1. Use uma máquina de teste e confirme que Xbox, Minecraft, Game Pass, segurança, rede, áudio e periféricos continuam funcionando.
2. Registre o plano de energia ativo e o estado inicial do Modo de Jogo.
3. Ative Gamer e confirme a leitura posterior e o backup.
4. Se o plano Alto desempenho existir, teste Gamer Ultra optando por não o ativar e depois aceitando a opção.
5. Ative Gamer após Ultra com um plano gerenciado pendente e confirme que o Lynext bloqueia a operação; selecione Gamer Ultra e restaure explicitamente antes de tentar Gamer.
6. Use Voltar ao padrão e confirme que as configurações retornaram aos valores originais.
7. Altere manualmente o plano de energia depois de aplicar Ultra e confirme que o Lynext detecta o conflito e não o sobrescreve silenciosamente.
8. Revise o histórico e confirme que falhas e reversões parciais não são registradas como sucesso.

## Próxima etapa recomendada

Ampliar a suíte com abstrações simuláveis de Registro e `powercfg`, validar os fluxos em uma VM Windows e considerar outras opções somente após comprovar compatibilidade, reversão e benefício mensurável.

