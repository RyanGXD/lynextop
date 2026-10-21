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

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            LoadOptionalBrandImage();
            RefreshHardware();
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
                    "O Gamer Ultra pode tentar ativar o plano de energia Alto desempenho do Windows, caso esteja instalado. Isso altera o plano ativo até você mudar de perfil ou usar Voltar ao padrão e pode aumentar consumo, temperatura e ruído. Não garante FPS maior.\n\nDeseja incluir essa alteração?",
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
            MessageBox.Show("Não existe backup do Gamer Ultra para restaurar.", "Lynext", MessageBoxButton.OK, MessageBoxImage.Information);
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
        if (_isCheckingUpdates)
            return;

        _isCheckingUpdates = true;
        CheckUpdatesButton.IsEnabled = false;
        UpdateStatusText.Text = automatic
            ? "Verificando atualizações em segundo plano..."
            : "Consultando versões estáveis no GitHub...";

        try
        {
            _availableUpdate = await UpdateService.CheckLatestAsync();
            if (_availableUpdate is null)
            {
                UpdateStatusText.Text = "Versão instalada: " + UpdateService.InstalledVersion;
                if (showWhenUnavailable)
                {
                    MessageBox.Show(
                        "Nenhuma atualização estável foi encontrada. Você já pode estar na versão atual ou ainda não existe uma Release com instalador publicado.",
                        "Lynext — Atualizações",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                }
                return;
            }

            var notes = string.IsNullOrWhiteSpace(_availableUpdate.Notes)
                ? "Não há notas de versão publicadas."
                : _availableUpdate.Notes;
            var answer = MessageBox.Show(
                $"Uma nova versão está disponível: {_availableUpdate.Version}\nVersão instalada: {UpdateService.InstalledVersion}\n\nNotas da versão:\n{TrimNotes(notes)}\n\nDeseja baixar o instalador oficial agora? A instalação só começa após outra confirmação.",
                "Lynext — Atualização disponível",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);

            UpdateStatusText.Text = $"Atualização {_availableUpdate.Version} disponível.";
            if (answer != MessageBoxResult.Yes)
                return;

            CheckUpdatesButton.Content = "Baixando...";
            var progress = new Progress<double>(value =>
                UpdateStatusText.Text = $"Baixando instalador: {value:0}%");
            var installerPath = await UpdateService.DownloadInstallerAsync(_availableUpdate, progress);

            var launch = MessageBox.Show(
                "O download terminou. O Windows poderá pedir permissão para abrir o instalador. Salve seu trabalho antes de continuar. Deseja abrir o instalador agora?",
                "Lynext — Instalar atualização",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);

            if (launch == MessageBoxResult.Yes)
            {
                Process.Start(new ProcessStartInfo(installerPath) { UseShellExecute = true });
                UpdateStatusText.Text = "Instalador aberto. Siga as instruções dele para concluir a atualização.";
            }
            else
            {
                UpdateStatusText.Text = $"Instalador baixado: {installerPath}";
                MessageBox.Show($"Você pode executar o instalador depois:\n{installerPath}", "Lynext");
            }
        }
        catch (Exception ex)
        {
            UpdateStatusText.Text = "Não foi possível verificar ou baixar a atualização.";
            if (!automatic)
            {
                MessageBox.Show(
                    $"Falha ao verificar/baixar a atualização. Confira sua conexão e tente novamente.\n\nDetalhes: {ex.Message}",
                    "Lynext — Atualizações",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
            else
            {
                FeedbackText.Text = "Não foi possível verificar atualizações agora. Você pode tentar novamente pelo botão de atualizações.";
            }
        }
        finally
        {
            _isCheckingUpdates = false;
            CheckUpdatesButton.IsEnabled = true;
            CheckUpdatesButton.Content = "Verificar atualizações";
        }
    }

    private void OpenReleases_Click(object sender, RoutedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://github.com/RyanGXD/lynextop/releases") { UseShellExecute = true });
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
