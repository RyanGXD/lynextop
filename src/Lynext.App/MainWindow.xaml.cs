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
            "Gamer Ultra" => "Foco competitivo: a primeira etapa ativa apenas o Modo de Jogo do Windows, com backup e opção de reversão. Xbox, Minecraft, Game Pass, Firewall e serviços essenciais ficam preservados.",
            "Gamer" => "Priorizar FPS, frametime estável e baixa latência com base no hardware detectado. Este perfil ainda está em planejamento.",
            "Lite" => "Reduzir excessos sem comprometer recursos úteis, segurança ou estabilidade do Windows. Este perfil ainda está em planejamento.",
            "Empresarial" => "Ajustes conservadores, preservando impressoras, rede, políticas e confiabilidade. Este perfil ainda está em planejamento.",
            "Economia" => "Reduzir consumo, calor e gasto de bateria, respeitando os limites do equipamento. Este perfil ainda está em planejamento.",
            _ => "Selecione um perfil para preparar a análise."
        };

        ActivateGamerUltraButton.IsEnabled = profile == "Gamer Ultra";
        RestoreDefaultsButton.IsEnabled = OptimizationService.CanRestoreDefaults;
        StatusText.Text = OptimizationService.IsGamerUltraApplied
            ? "Gamer Ultra ativo"
            : (profile == "Gamer Ultra" ? "Gamer Ultra pronto" : "Nenhuma otimização aplicada");
        FeedbackText.Text = $"Perfil selecionado: {profile}. {OptimizationService.GetStatusSummary()}";
    }

    private void PrepareAnalysis_Click(object sender, RoutedEventArgs e)
    {
        RefreshHardware();
        FeedbackText.Text = "Análise básica concluída. " + OptimizationService.GetStatusSummary()
            + " Nenhuma alteração foi aplicada por esta análise.";
    }

    private async void ActivateGamerUltra_Click(object sender, RoutedEventArgs e)
    {
        if (ProfileTitle.Text != "Gamer Ultra")
        {
            MessageBox.Show("Selecione o perfil Gamer Ultra antes de ativá-lo.", "Lynext", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        ActivateGamerUltraButton.IsEnabled = false;
        try
        {
            var restoreChoice = MessageBox.Show(
                "Antes de ativar o Gamer Ultra, recomendamos tentar criar um ponto de restauração do Windows. Esse ponto pode ocupar espaço em disco e não garante a recuperação de todos os arquivos, aplicativos ou configurações. O Lynext também salva os valores exatos que esta etapa modifica para permitir uma reversão própria.\n\nDeseja tentar criar um ponto de restauração?",
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
                        $"O Lynext não conseguiu confirmar a criação do ponto de restauração.\n\nMotivo: {attempt.Error}\n\nNenhuma otimização foi aplicada ainda. Esta primeira etapa altera somente a opção documentada do Modo de Jogo e guarda um backup próprio. Deseja prosseguir sem o ponto de restauração?",
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
                    "Você escolheu não criar um ponto de restauração. Esta etapa altera somente a opção documentada do Modo de Jogo e salva um backup próprio para o botão Voltar ao padrão, mas a proteção é menor sem o ponto do Windows. Deseja prosseguir mesmo assim?",
                    "Lynext — Confirmar sem ponto",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning);
                if (continueWithoutPoint != MessageBoxResult.Yes)
                    return;
                restorePointNote = "A ativação foi autorizada sem tentar criar um ponto de restauração.";
            }

            var result = OptimizationService.ApplyGamerUltra();
            UpdateOptimizationUiState();
            FeedbackText.Text = result + " " + restorePointNote;
            MessageBox.Show(
                result + "\n\n" + restorePointNote + "\n\nNenhum serviço do Xbox/Game Pass, Firewall, Defender ou Windows Update foi desativado. Nenhum ganho de FPS é presumido: a etapa precisa ser medida no jogo.",
                "Lynext — Gamer Ultra",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            FeedbackText.Text = "Não foi possível aplicar o Gamer Ultra: " + ex.Message;
            MessageBox.Show(
                $"Não foi possível aplicar o Gamer Ultra. Se um erro aconteceu durante a alteração, o Lynext tentou restaurar os valores anteriores.\n\nDetalhes: {ex.Message}",
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
            "O Lynext vai restaurar somente os valores do Modo de Jogo que ele salvou antes da ativação. Xbox, Game Pass, Game DVR, Firewall, Defender, serviços e plano de energia não serão alterados por esta reversão. Deseja continuar?",
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

    private void UpdateOptimizationUiState()
    {
        RestoreDefaultsButton.IsEnabled = OptimizationService.CanRestoreDefaults;
        ActivateGamerUltraButton.IsEnabled = ProfileTitle.Text == "Gamer Ultra";
        if (OptimizationService.IsGamerUltraApplied)
            StatusText.Text = "Gamer Ultra ativo";
        else if (ProfileTitle.Text == "Gamer Ultra")
            StatusText.Text = "Gamer Ultra pronto";
        else
            StatusText.Text = "Nenhuma otimização aplicada";
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
