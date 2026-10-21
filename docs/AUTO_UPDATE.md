# Atualização automática do Lynext

## Fluxo

O aplicativo consulta a endpoint pública de Releases estáveis do repositório RyanGXD/lynextop. Versões pré-lançamento, tags malformadas e versões iguais ou anteriores à instalada não são oferecidas pelo canal estável.

Quando uma versão mais recente existe, o Lynext exibe versão, notas, data e tamanho quando disponíveis. A ação Atualizar agora baixa o instalador e valida tamanho e SHA-256 antes de iniciar qualquer executável.

## Integridade e redirecionamentos

A aplicação usa o digest SHA-256 fornecido pela API de assets do GitHub quando ele é válido e também aceita um sidecar chamado Lynext-Setup-VERSION-x64.exe.sha256. Se ambos existem, os hashes precisam coincidir. O atualizador bloqueia Releases sem hash verificável.

Os downloads permitem apenas HTTPS nos hosts oficiais configurados para os ativos do GitHub. Os redirecionamentos são seguidos manualmente, têm limite e cada destino é validado. O instalador final é novamente conferido pelo componente auxiliar antes da execução.

SHA-256 detecta divergência em relação ao valor esperado; não substitui assinatura Authenticode. O repositório ainda não configura certificado de assinatura de código, portanto o projeto não declara que o instalador está assinado.

## Processo auxiliar e UAC

O build publica Lynext.Updater.exe junto do aplicativo. Antes de fechar, o Lynext copia esse componente para %LOCALAPPDATA%\Lynext\Updates, salva um manifesto local, a versão atual e o hash do executável instalado, então inicia o auxiliar. O auxiliar aguarda o processo principal sair, valida novamente o instalador e executa o setup normal do Inno Setup, permitindo sua interface e o pedido UAC.

Não é passado /DIR a partir do manifesto gravável. O AppId existente do Inno Setup e a preferência de pasta anterior são usados para localizar a instalação existente. O parâmetro personalizado /LYNEXTUPDATE=1 impede que o instalador lance uma segunda instância; depois do código de saída, o auxiliar confirma a versão instalada e inicia o Lynext uma vez.

Em falha ou cancelamento, a versão anterior só é reaberta quando o hash do executável e sua versão continuam iguais aos registrados. Se o instalador ainda estiver executando além do limite de espera, o auxiliar não abre outra instância em paralelo. O projeto não promete rollback completo do diretório quando o instalador interrompe depois de substituir parte dos arquivos.

## Limitação de bootstrap

Instalações antigas que não incluem Lynext.Updater.exe não podem executar o fluxo completo de atualização em-app. Para essas instalações de prévia, é necessária uma instalação manual única de uma build que contenha o auxiliar. Depois disso, o ciclo dentro do Lynext está disponível.

## Build e publicação

O script scripts/build-installer.ps1 publica o aplicativo e o auxiliar, compila o instalador Inno Setup e cria um sidecar SHA-256. Pushes à branch geram somente artefatos de CI. O workflow só publica uma Release quando recebe uma tag estável vMAJOR.MINOR.PATCH ou vMAJOR.MINOR.PATCH.REVISION.

## Testes e limitações atuais

A suíte tests/Lynext.UpdateTests cobre validação de tags, versões, nomes de assets, política HTTPS/hosts, digests e arquivos de checksum. Os testes de unidade não instalam um executável real nem alteram configurações do Windows.

Build/CI confirma compilação e empacotamento; não equivale a uma atualização funcional testada em um computador com instalação antiga, nem valida assinatura digital. O primeiro update real deve ser testado em VM ou máquina de teste e com uma Release de staging antes de anunciar o recurso como pronto para todos os usuários.

## Referências

- GitHub Releases API: https://docs.github.com/en/rest/releases/releases
- Inno Setup — parâmetros do instalador: https://jrsoftware.org/ishelp/index.php?topic=setupcmdline
- Microsoft — ProcessStartInfo: https://learn.microsoft.com/pt-br/dotnet/api/system.diagnostics.processstartinfo
- Microsoft — HttpClient: https://learn.microsoft.com/pt-br/dotnet/api/system.net.http.httpclient
