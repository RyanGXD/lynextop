using System.Windows;
using System.Windows.Controls;
using System.IO;
using System.Windows.Media.Imaging;
using System.Diagnostics;

namespace Lynext;

public partial class MainWindow : Window
{
    private HardwareSnapshot? _hardware;
    private UpdateInfo? _availableUpdate;
    private bool _isCheckingUpdates;
    private bool _isUpdating;
    private CancellationTokenSource? _updateCancellation;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            LoadOptionalBrandImage();
            RefreshHardware();
            if (OptimizationService.ActiveProfileName is "Gamer" or "Gamer Ultra")
            {
                ProfileTitle.Text = OptimizationService.ActiveProfileName;
                ProfileDescription.Text = OptimizationService.ActiveProfileName == "Gamer Ultra"
                    ? "Perfil competitivo ampliado restaurado da sessão anterior. Revise o estado atual das configurações antes de continuar."
                    : "Perfil competitivo equilibrado restaurado da sessão anterior. O estado é lido novamente ao abrir o aplicativo.";
            }
            UpdateOptimizationUiState();
            // Check quietly at startup; only notify the user when a newer stable release exists.
            await CheckForUpdatesAsync(showWhenUnavailable: false, automatic: true);
        };
    }

    private void LoadOptionalBrandImage()
    {
        var imagePath = Path.Combine(AppContext.BaseDirectory, "Branding", "LynextLogo.png");
        if (!File.Exists(imagePath))
            return;

        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(imagePath, UriKind.Absolute);
            image.EndInit();
            image.Freeze();
            BrandImage.Source = image;
            BrandImage.Visibility = Visibility.Visible;
            BrandPlaceholder.Visibility = Visibility.Collapsed;
        }
        catch
        {
            // Keep the vector placeholder if the optional image is missing or invalid.
        }
    }

    private void RefreshHardware_Click(object sender, RoutedEventArgs e) => RefreshHardware();

    private void RefreshHardware()
    {
        try
        {
            _hardware = HardwareInfoService.Read();
            CpuText.Text = $"Processador: {_hardware.Processor}";
            GpuText.Text = "Placa(s) de vídeo: " + string.Join(" • ", _hardware.GraphicsAdapters.Select(g =>
                $"{g.Name} (driver {g.DriverVersion}, data {g.DriverDate})"));
            RamText.Text = $"Memória RAM instalada: {(_hardware.InstalledMemoryGb > 0 ? $"{_hardware.InstalledMemoryGb:N1} GB" : "não identificada")} • Núcleos físicos: {(_hardware.PhysicalCores > 0 ? _hardware.PhysicalCores.ToString() : "indisponível")}";
            SystemText.Text = $"Windows: {_hardware.WindowsVersion} • Processadores lógicos: {_hardware.LogicalProcessors}";
            FeedbackText.Text = $"Hardware analisado em {_hardware.ScannedAt:dd/MM/yyyy HH:mm:ss}.";
        }
        catch (Exception ex)
        {
            FeedbackText.Text = $"Não foi possível concluir a análise: {ex.Message}";
        }
    }

    private void Profile_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string profile })
            return;

        ProfileTitle.Text = profile;
        ProfileDescription.Text = profile switch
        {
            "Gamer Ultra" => "Foco competitivo ampliado: Modo de Jogo e opção explícita de plano Alto desempenho, se instalado. A energia pode aumentar consumo, temperatura e ruído; não há promessa de ganho de FPS.",
            "Gamer" => "Perfil competitivo equilibrado: habilita o Modo de Jogo do Windows quando necessário, mantém energia inalterada e oferece atalhos para revisar gráficos e inicialização.",
            "Lite" => "Reduzir excessos sem comprometer recursos úteis, segurança ou estabilidade do Windows. Este perfil ainda está em planejamento.",
            "Empresarial" => "Ajustes conservadores, preservando impressoras, rede, políticas e confiabilidade. Este perfil ainda está em planejamento.",
            "Economia" => "Reduzir consumo, calor e gasto de bateria, respeitando os limites do equipamento. Este perfil ainda está em planejamento.",
            _ => "Selecione um perfil para preparar a análise."
        };

        ActivateGamerButton.IsEnabled = profile == "Gamer";
        ActivateGamerUltraButton.IsEnabled = profile == "Gamer Ultra";
        RestoreDefaultsButton.IsEnabled = OptimizationService.CanRestoreDefaults;
        StatusText.Text = OptimizationService.IsGamerUltraApplied
            ? "Gamer Ultra ativo"
            : (OptimizationService.IsGamerApplied ? "Gamer ativo" : (profile is "Gamer" or "Gamer Ultra" ? profile + " pronto" : "Nenhum perfil Gamer ativo"));
        FeedbackText.Text = $"Perfil selecionado: {profile}. {OptimizationService.GetStatusSummary()}";
    }

    private void PrepareAnalysis_Click(object sender, RoutedEventArgs e)
    {
        RefreshHardware();
        FeedbackText.Text = "Análise básica concluída. " + OptimizationService.GetStatusSummary()
            + " Nenhuma alteração foi aplicada por esta análise.";
    }

    private async void ActivateGamer_Click(object sender, RoutedEventArgs e) =>
        await ActivateProfileAsync("Gamer");

    private async void ActivateGamerUltra_Click(object sender, RoutedEventArgs e) =>
        await ActivateProfileAsync("Gamer Ultra");

    private async Task ActivateProfileAsync(string profileName)
    {
        if (ProfileTitle.Text != profileName)
        {
            MessageBox.Show($"Selecione o perfil {profileName} antes de ativá-lo.", "Lynext", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        ActivateGamerButton.IsEnabled = false;
        ActivateGamerUltraButton.IsEnabled = false;
        try
        {
            var restoreChoice = MessageBox.Show(
                $"Antes de ativar {profileName}, recomendamos tentar criar um ponto de restauração do Windows. O ponto pode ocupar espaço em disco e não garante a recuperação de todos os arquivos ou aplicativos. O Lynext também salva backups próprios dos ajustes que ele realmente modifica.\n\nDeseja tentar criar um ponto de restauração?",
                "Lynext — Proteção antes de otimizar",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);

            if (restoreChoice == MessageBoxResult.Cancel)
                return;

            var restorePointNote = "Ponto de restauração não solicitado.";
            if (restoreChoice == MessageBoxResult.Yes)
            {
                FeedbackText.Text = "Tentando criar e verificar um ponto de restauração. Nenhuma otimização foi aplicada ainda...";
                var attempt = await OptimizationService.TryCreateRestorePointAsync();
                if (attempt.Success)
                {
                    restorePointNote = $"Ponto de restauração confirmado: {attempt.Description} (sequência {attempt.SequenceNumber}).";
                }
                else
                {
                    var continueWithoutPoint = MessageBox.Show(
                        $"O Lynext não conseguiu confirmar a criação do ponto de restauração.\n\nMotivo: {attempt.Error}\n\nNenhuma otimização foi aplicada ainda. Esta etapa usa o backup próprio para os ajustes que conseguir modificar. Deseja prosseguir sem o ponto do Windows?",
                        "Lynext — Ponto de restauração não confirmado",
                        MessageBoxButton.YesNo,
                        MessageBoxImage.Warning);
                    if (continueWithoutPoint != MessageBoxResult.Yes)
                        return;
                    restorePointNote = "A ativação foi autorizada sem ponto de restauração confirmado.";
                }
            }
            else
            {
                var continueWithoutPoint = MessageBox.Show(
                    "Você escolheu não criar um ponto de restauração. As alterações desta versão são limitadas e possuem backups próprios, mas a proteção é menor sem o ponto do Windows. Deseja prosseguir mesmo assim?",
                    "Lynext — Confirmar sem ponto",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning);
                if (continueWithoutPoint != MessageBoxResult.Yes)
                    return;
                restorePointNote = "A ativação foi autorizada sem tentar criar um ponto de restauração.";
            }

            var useHighPerformancePowerPlan = false;
            if (profileName == "Gamer Ultra")
            {
                var powerChoice = MessageBox.Show(
                    "O Gamer Ultra pode tentar ativar o plano Alto desempenho se estiver instalado e o Lynext confirmar que não há bateria no sistema. Em notebooks ou se a detecção de bateria falhar, a energia não será alterada. Em desktops compatíveis, a troca pode aumentar consumo, temperatura e ruído e não garante FPS maior.\n\nDeseja incluir essa alteração?",
                    "Lynext — Opção adicional do Gamer Ultra",
                    MessageBoxButton.YesNoCancel,
                    MessageBoxImage.Warning);
                if (powerChoice == MessageBoxResult.Cancel)
                    return;
                useHighPerformancePowerPlan = powerChoice == MessageBoxResult.Yes;
            }

            var result = profileName == "Gamer"
                ? OptimizationService.ApplyGamer()
                : OptimizationService.ApplyGamerUltra(useHighPerformancePowerPlan);
            UpdateOptimizationUiState();
            FeedbackText.Text = result + " " + restorePointNote;
            MessageBox.Show(
                result + "\n\n" + restorePointNote + "\n\nNenhum ganho de FPS é presumido: valide o resultado no jogo com medições repetíveis.",
                "Lynext — " + profileName,
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            FeedbackText.Text = "Não foi possível ativar o perfil: " + ex.Message;
            MessageBox.Show(
                $"Não foi possível ativar {profileName}. O Lynext tentou reverter ajustes feitos durante esta tentativa quando foi seguro.\n\nDetalhes: {ex.Message}",
                "Lynext — Falha na ativação",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            UpdateOptimizationUiState();
        }
    }

        private void RestoreDefaults_Click(object sender, RoutedEventArgs e)
    {
        if (!OptimizationService.CanRestoreDefaults)
        {
            MessageBox.Show("Não há backup ou perfil gerenciado pelo Lynext para restaurar.", "Lynext", MessageBoxButton.OK, MessageBoxImage.Information);
            UpdateOptimizationUiState();
            return;
        }

        var confirm = MessageBox.Show(
            "O Lynext vai restaurar os valores originais que ainda estiverem sob seu controle, incluindo Modo de Jogo e plano de energia quando gerenciados. Se detectar uma mudança externa, interromperá a reversão daquele ajuste para não sobrescrever sua escolha. Deseja continuar?",
            "Lynext — Voltar ao padrão",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (confirm != MessageBoxResult.Yes)
            return;

        try
        {
            FeedbackText.Text = OptimizationService.RestoreDefaults();
            UpdateOptimizationUiState();
            MessageBox.Show(FeedbackText.Text, "Lynext — Reversão concluída", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            FeedbackText.Text = "Não foi possível restaurar as configurações: " + ex.Message;
            MessageBox.Show(FeedbackText.Text, "Lynext — Falha na reversão", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            UpdateOptimizationUiState();
        }
    }

    private void OpenGraphicsSettings_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("ms-settings:display-graphics") { UseShellExecute = true });
            FeedbackText.Text = "Configurações de gráficos abertas. No Windows 11, revise as otimizações para jogos em janela e a preferência de GPU por jogo, se aplicável.";
        }
        catch (Exception ex)
        {
            FeedbackText.Text = "Não foi possível abrir as Configurações gráficas: " + ex.Message;
        }
    }

    private void OpenStartupAppsSettings_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("ms-settings:startupapps") { UseShellExecute = true });
            FeedbackText.Text = "Aplicativos de inicialização abertos. Use o impacto mostrado pelo Windows como referência; desative individualmente apenas programas conhecidos que você não precisa ao iniciar. O Lynext não modifica serviços nem encerra processos.";
        }
        catch (Exception ex)
        {
            FeedbackText.Text = "Não foi possível abrir os Aplicativos de inicialização do Windows: " + ex.Message;
        }
    }

    private void UpdateOptimizationUiState()
    {
        RestoreDefaultsButton.IsEnabled = OptimizationService.CanRestoreDefaults;
        ActivateGamerButton.IsEnabled = ProfileTitle.Text == "Gamer";
        ActivateGamerUltraButton.IsEnabled = ProfileTitle.Text == "Gamer Ultra";
        if (OptimizationService.IsGamerUltraApplied)
            StatusText.Text = "Gamer Ultra ativo";
        else if (OptimizationService.IsGamerApplied)
            StatusText.Text = "Gamer ativo";
        else if (ProfileTitle.Text is "Gamer" or "Gamer Ultra")
            StatusText.Text = ProfileTitle.Text + " pronto";
        else
            StatusText.Text = "Nenhum perfil Gamer ativo";
    }

    private async void CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        await CheckForUpdatesAsync(showWhenUnavailable: true, automatic: false);
    }

    private async Task CheckForUpdatesAsync(bool showWhenUnavailable, bool automatic)
    {
        if (_isCheckingUpdates || _isUpdating)
            return;

        _isCheckingUpdates = true;
        CheckUpdatesButton.IsEnabled = false;
        _availableUpdate = null;
        UpdateAvailableText.Visibility = Visibility.Collapsed;
        UpdateNotesText.Visibility = Visibility.Collapsed;
        InstallUpdateButton.Visibility = Visibility.Collapsed;
        InstallUpdateButton.IsEnabled = false;
        LaterUpdateButton.Visibility = Visibility.Collapsed;
        UpdateStatusText.Text = automatic
            ? "Verificando atualizações em segundo plano..."
            : "Consultando Releases estáveis no GitHub...";

        try
        {
            _availableUpdate = await UpdateService.CheckLatestAsync();
            if (_availableUpdate is null)
            {
                UpdateStatusText.Text = "Nenhuma atualização disponível. Versão instalada: " + UpdateService.InstalledVersion;
                if (showWhenUnavailable)
                {
                    MessageBox.Show(
                        "Nenhuma atualização estável mais recente foi encontrada. Se a publicação acabou de ser feita, tente novamente em alguns instantes.",
                        "Lynext — Atualizações",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                }
                return;
            }

            ShowAvailableUpdate(_availableUpdate);
        }
        catch (OperationCanceledException)
        {
            UpdateStatusText.Text = "Verificação de atualização cancelada.";
        }
        catch (Exception ex)
        {
            UpdateStatusText.Text = "Não foi possível verificar atualizações. Sua versão não foi confirmada como atual.";
            UpdateOrchestrator.WriteUpdateLog("Falha ao verificar Releases: " + ex);
            if (!automatic)
            {
                MessageBox.Show(
                    "Não foi possível verificar a versão mais recente. Confira sua conexão e tente novamente.\n\nDetalhes: " + ex.Message,
                    "Lynext — Falha na verificação",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
            else
            {
                FeedbackText.Text = "A verificação automática falhou. Você pode tentar novamente pelo botão de atualizações.";
            }
        }
        finally
        {
            _isCheckingUpdates = false;
            CheckUpdatesButton.IsEnabled = !_isUpdating;
        }
    }

    private void ShowAvailableUpdate(UpdateInfo update)
    {
        var published = update.PublishedAt.HasValue
            ? " • Publicada em " + update.PublishedAt.Value.ToLocalTime().ToString("dd/MM/yyyy HH:mm")
            : string.Empty;
        var size = update.AssetSize.HasValue
            ? " • " + FormatBytes(update.AssetSize.Value)
            : string.Empty;

        UpdateAvailableText.Text = $"Nova versão {update.Version} disponível (instalada: {UpdateService.InstalledVersion}){published}{size}.";
        UpdateAvailableText.Visibility = Visibility.Visible;
        UpdateNotesText.Text = string.IsNullOrWhiteSpace(update.Notes)
            ? "Esta versão não contém notas de lançamento."
            : TrimNotes(update.Notes);
        UpdateNotesText.Visibility = Visibility.Visible;
        InstallUpdateButton.Visibility = Visibility.Visible;
        InstallUpdateButton.IsEnabled = update.HasIntegritySource;
        LaterUpdateButton.Visibility = Visibility.Visible;
        UpdateStatusText.Text = update.HasIntegritySource
            ? "Atualização disponível. O instalador será verificado antes de ser executado."
            : "Atualização disponível, mas não há SHA-256 verificável nesta Release. A instalação pelo atualizador está bloqueada por segurança.";
    }

    private async void InstallUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (_availableUpdate is null || _isUpdating)
            return;

        if (!_availableUpdate.HasIntegritySource)
        {
            MessageBox.Show(
                "Esta Release não fornece um SHA-256 verificável. O Lynext não executará um instalador sem validar sua integridade.",
                "Lynext — Integridade não disponível",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var confirmation = MessageBox.Show(
            $"O Lynext vai baixar e validar a versão {_availableUpdate.Version}. Depois, o programa será fechado temporariamente, o instalador oficial será aberto e o Lynext será iniciado novamente após a confirmação da instalação.\n\nSalve seu trabalho antes de continuar.",
            "Lynext — Confirmar atualização",
            MessageBoxButton.YesNo,
            MessageBoxImage.Information);
        if (confirmation != MessageBoxResult.Yes)
            return;

        _isUpdating = true;
        _updateCancellation = new CancellationTokenSource();
        var handoffStarted = false;
        CheckUpdatesButton.IsEnabled = false;
        InstallUpdateButton.IsEnabled = false;
        LaterUpdateButton.IsEnabled = false;
        CancelUpdateButton.Visibility = Visibility.Visible;
        UpdateProgressBar.Visibility = Visibility.Visible;
        UpdateProgressBar.IsIndeterminate = true;
        UpdateProgressBar.Value = 0;
        UpdateStatusText.Text = "Baixando instalador e preparando a validação de integridade...";

        try
        {
            var progress = new Progress<UpdateDownloadProgress>(value =>
            {
                UpdateProgressBar.IsIndeterminate = !value.Percent.HasValue;
                if (value.Percent.HasValue)
                {
                    UpdateProgressBar.Value = value.Percent.Value;
                    var total = value.TotalBytes.HasValue ? FormatBytes(value.TotalBytes.Value) : "tamanho desconhecido";
                    UpdateStatusText.Text = $"Baixando instalador: {value.Percent.Value:0}% ({FormatBytes(value.BytesReceived)} de {total}).";
                }
                else
                {
                    UpdateStatusText.Text = $"Baixando instalador: {FormatBytes(value.BytesReceived)} recebidos.";
                }
            });

            await UpdateOrchestrator.StartUpdateAsync(_availableUpdate, progress, _updateCancellation.Token);
            handoffStarted = true;
            UpdateStatusText.Text = "Instalador validado. Fechando o Lynext e transferindo o controle para o atualizador...";
            Application.Current.Shutdown();
        }
        catch (OperationCanceledException)
        {
            UpdateStatusText.Text = "Download cancelado. Nenhuma instalação foi iniciada.";
            UpdateProgressBar.Visibility = Visibility.Collapsed;
            UpdateOrchestrator.WriteUpdateLog("Usuário cancelou a atualização antes do início do instalador.");
        }
        catch (Exception ex)
        {
            UpdateStatusText.Text = ex is InvalidDataException
                ? "Falha na validação da atualização. O instalador não foi executado."
                : "Não foi possível preparar a atualização.";
            UpdateOrchestrator.WriteUpdateLog("Falha ao preparar atualização: " + ex);
            MessageBox.Show(
                UpdateStatusText.Text + "\n\n" + ex.Message,
                "Lynext — Falha na atualização",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            UpdateProgressBar.Visibility = Visibility.Collapsed;
        }
        finally
        {
            _updateCancellation?.Dispose();
            _updateCancellation = null;
            if (!handoffStarted)
            {
                _isUpdating = false;
                CheckUpdatesButton.IsEnabled = true;
                InstallUpdateButton.IsEnabled = _availableUpdate?.HasIntegritySource == true;
                LaterUpdateButton.IsEnabled = true;
                CancelUpdateButton.Visibility = Visibility.Collapsed;
            }
        }
    }

    private void CancelUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (_isUpdating)
        {
            UpdateStatusText.Text = "Cancelando o download com segurança...";
            _updateCancellation?.Cancel();
        }
    }

    private void LaterUpdate_Click(object sender, RoutedEventArgs e)
    {
        UpdateAvailableText.Visibility = Visibility.Collapsed;
        UpdateNotesText.Visibility = Visibility.Collapsed;
        InstallUpdateButton.Visibility = Visibility.Collapsed;
        LaterUpdateButton.Visibility = Visibility.Collapsed;
        UpdateStatusText.Text = "Atualização adiada. Você pode verificar novamente mais tarde.";
    }

    private static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB"];
        double size = Math.Max(0, bytes);
        var unit = 0;
        while (size >= 1024 && unit < units.Length - 1)
        {
            size /= 1024;
            unit++;
        }
        return $"{size:0.0} {units[unit]}";
    }

    private void OpenReleases_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var destination = _availableUpdate?.ReleaseUrl ?? "https://github.com/RyanGXD/lynextop/releases";
            Process.Start(new ProcessStartInfo(destination) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            UpdateStatusText.Text = "Não foi possível abrir a página de Releases: " + ex.Message;
        }
    }

    private static string TrimNotes(string notes)
    {
        const int maxLength = 900;
        return notes.Length <= maxLength ? notes : notes[..maxLength] + "...";
    }

    private void History_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show(
            OptimizationService.GetHistory(),
            "Lynext — Histórico de alterações",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
}
