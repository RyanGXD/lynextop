# Lite, Empresarial e Economia

## Arquitetura e limites

Os três perfis agora têm telas próprias, um catálogo técnico separado de `OptimizationAuthorizationPolicy` e diagnósticos explicitamente disparados. O catálogo de features registra escopo, pré-condições, benefício esperado, riscos, consulta, ação, restauração e referência. As features novas declaram `ChangesWindows=false`: nenhuma delas entra na allowlist de mutações de Gamer/Gamer Ultra, e selecionar um perfil não executa coleta nem altera configuração. Os perfis existentes continuam usando a autorização fechada e os backups próprios.

Não há um botão “ativar” que alegue modificar o sistema sem aplicar algo, nem uma rotina de alterações gerais sem reversão. Os controles seguem a opção segura descrita no prompt: análise somente de leitura e encaminhamento à página nativa para o usuário escolher e reverter. O status distingue perfil selecionado de diagnóstico concluído. Relatórios sob demanda são a única gravação; ficam em `%LOCALAPPDATA%\Lynext\Reports`, sem envio externo.

## Lite

- Enumera itens nas chaves `Run` do usuário/máquina (incluindo visão 32-bit) e pastas Startup, sem editar/remover. Impacto é sempre “não medido”; falha de acesso não significa que não existam itens.
- Abre inicialização, acessibilidade/efeitos visuais, atividade de bateria em segundo plano e armazenamento nas Configurações do Windows.
- Não promete FPS por efeitos visuais, não encerra processos, não desativa aplicativos em massa e não limpa arquivos. Downloads, documentos e dados de aplicativos não são tocados.
- O Windows só expõe controle de atividade em segundo plano para apps compatíveis; restringir pode afetar notificações/sincronização.

## Empresarial

- Diagnóstico local mostra contagem/estado operacional dos adaptadores, sinal limitado de VPN PPP, impressoras WMI, estado reportado de Spooler e sinais locais de políticas Windows Update/inscrição.
- Não revela DNS, gateway, endereços IP, nome do computador, credenciais ou envia dados. WMI/acesso pode falhar e é apresentado como indisponível. Estado de Spooler e da impressora não prova impressão de ponta a ponta.
- A detecção de gerenciamento é indicativa, não prova ausência de MDM/GPO; quando há sinal, recomenda o administrador. Atualização, segurança, rede, VPN, políticas, serviços e impressão são somente consultados.
- Links abrem Startup e Windows Update, sem alteração automática.

## Economia

- Consulta bateria via `Win32_Battery`, fonte AC/DC e nível reportado via `GetSystemPowerStatus`, plano ativo por `powercfg /getactivescheme` e esquemas por `/list`. Ausência ou falha de consulta não é tratada como prova de desktop; o texto mantém limitação/estado desconhecido.
- Oferece Configurações nativas para modos e tempos por bateria/tomada. Não troca planos, não edita tempos, não altera suspensão/tampa e não inventa limites de carga.
- Relatórios HTML opcionais: `/batteryreport`, `/energy /duration 10` e `/sleepstudy /duration 3`, após confirmação. Os relatórios podem não existir em alguns equipamentos ou exigir privilégio. A geração não corrige os problemas encontrados.
- A execução de powercfg tem timeout de 30 s e saída explícita em pasta local do Lynext; não há reinicialização.

## Proteção e reversibilidade

As novas funções não escrevem Registro, serviços, pacotes AppX/MSIX, esquemas de energia ou configurações de segurança. Não podem alterar Store, licenciamento/AppX, Xbox/Gaming Services, Game Pass, Minecraft, UAC, Defender, SmartScreen, Firewall, Windows Update, rede ou impressoras. As opções encaminhadas para Configurações são aplicadas e restauradas manualmente pelo usuário, conforme os valores e capacidades do Windows no dispositivo. O catálogo usa consultas informativas; somente as operações preexistentes do Gamer/Gamer Ultra continuam autorizáveis para mudança.

## Pesquisa técnica

- [Inicialização no Windows](https://support.microsoft.com/pt-br/windows/experience/startup-boot/configure-startup-applications-in-windows): a página documenta configurações de inicialização e locais Run/Startup; também alerta para riscos de editar Registro. Sustenta enumeração e preferência por controle nativo.
- [Atividade em segundo plano](https://support.microsoft.com/pt-br/windows/experience/performance-optimization/manage-background-activity-for-apps-in-windows): só apps que oferecem suporte podem ser geridos; notificações/sincronização e bateria podem ser afetadas.
- [Energia no Windows 11](https://support.microsoft.com/pt-br/windows/experience/power-battery/power-settings-in-windows-11): modo de energia, economia, tela e suspensão variam por dispositivo e permitem revisão nativa.
- [URIs para abrir Configurações](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings): documenta os links `ms-settings:` para inicialização, energia e bateria, armazenamento e recomendações; também lista disponibilidade condicionada por versão/dispositivo.
- [GetSystemPowerStatus](https://learn.microsoft.com/pt-br/windows/win32/api/winbase/nf-winbase-getsystempowerstatus) e [SYSTEM_POWER_STATUS](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-system_power_status): suportam consulta do estado AC/DC e percentual; valor desconhecido é preservado como desconhecido.
- [Recomendações de energia](https://support.microsoft.com/pt-br/windows/experience/power-battery/learn-more-about-energy-recommendations): opções variam conforme hardware e alimentação; não se presume suporte universal.
- [Opções de linha de comando powercfg](https://learn.microsoft.com/pt-br/windows-hardware/design/device-experiences/powercfg-command-line-options): documenta `/list`, `/query`, `/batteryreport`, `/energy` e `/sleepstudy`; o Lynext limita-se a consultas e relatórios.
- [Políticas de cliente do Windows Update](https://learn.microsoft.com/pt-br/windows/deployment/update/waas-manage-updates-wufb): políticas podem ser geridas por Group Policy e MDM; justifica preservar controles administrativos e tratar sinais locais como indícios.
- [Proteção do Sistema](https://support.microsoft.com/pt-br/windows/experience/backup-recovery/system-protection): pontos de restauração são uma funcionalidade de recuperação distinta; este trabalho não os exige porque as novas features não alteram configurações.

## Fora do escopo nesta versão

- Desativar individualmente Run/Startup pelo Lynext: não implementado; mover/apagar valores e atalhos não é necessário, tem risco de atingir itens desconhecidos e conflitar com gestão de aplicativos. O Windows fornece a interface nativa.
- Alterar animações/transparência, limitar atividade de app, limpar temporários, escolher modo, alterar tempos e definir limite de carga: não automatizado. Compatibilidade/impacto variam, e o controle nativo ou firmware é a rota sustentada.
- Verificação ponta a ponta de impressão, gerenciamento completo de serviços, rede, Defender e atualizações: não suportada por uma triagem local simples; estados não conclusivos são identificados como tal.
- Alterações automáticas em lote e restauração de valores “padrão”: recusadas para esses perfis; não há backup/reversão que justifique essas escritas.

## Testes e validação

Testes unitários exercitam isolamento dos painéis/perfis, ausência de operações automáticas, separação das permissões Gamer, e metadados/precondições/restauração do catálogo. Ainda é necessário executar em Windows máquinas físicas com e sem bateria, impressora e rede/VPN reais; os testes não afirmam simular hardware. Build/Actions devem ser registrados no relatório de execução desta alteração.
