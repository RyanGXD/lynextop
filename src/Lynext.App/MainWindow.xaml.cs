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

    public MainWindow()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            LoadOptionalBrandImage();
            RefreshHardware();
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
            "Gamer Ultra" => "Foco agressivo em desempenho para hardware limitado. Ajustes compatíveis serão avaliados individualmente.",
            "Gamer" => "Priorizar FPS, frametime estável e baixa latência com base no hardware detectado.",
            "Lite" => "Reduzir excessos sem comprometer recursos úteis, segurança ou estabilidade do Windows.",
            "Empresarial" => "Ajustes conservadores, preservando impressoras, rede, políticas e confiabilidade.",
            "Economia" => "Reduzir consumo, calor e gasto de bateria, respeitando os limites do equipamento.",
            _ => "Selecione um perfil para preparar a análise."
        };

        FeedbackText.Text = $"Perfil selecionado: {profile}. Nenhuma alteração foi aplicada.";
    }

    private void PrepareAnalysis_Click(object sender, RoutedEventArgs e)
    {
        RefreshHardware();
        FeedbackText.Text = "Análise básica concluída. O catálogo de otimizações será adicionado na próxima etapa; nada foi alterado.";
    }

    private async void CheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        if (CheckUpdatesButton.IsEnabled == false)
            return;

        CheckUpdatesButton.IsEnabled = false;
        UpdateStatusText.Text = "Consultando versões estáveis no GitHub...";
        try
        {
            _availableUpdate = await UpdateService.CheckLatestAsync();
            if (_availableUpdate is null)
            {
                UpdateStatusText.Text = "Você está na versão atual ou ainda não existe uma Release estável publicada.";
                MessageBox.Show(
                    "Nenhuma atualização estável foi encontrada. Isso pode significar que você já está atualizado ou que ainda não publicamos uma Release com instalador.",
                    "Lynext — Atualizações",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                return;
            }

            var notes = string.IsNullOrWhiteSpace(_availableUpdate.Notes)
                ? "Não há notas de versão publicadas."
                : _availableUpdate.Notes;
            var answer = MessageBox.Show(
                $"Nova versão: {_availableUpdate.Version}\nVersão instalada: {UpdateService.InstalledVersion}\n\nNotas da versão:\n{TrimNotes(notes)}\n\nDeseja baixar o instalador oficial agora? A instalação só começa após outra confirmação.",
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
            MessageBox.Show(
                $"Falha ao verificar/baixar a atualização. Confira sua conexão e tente novamente.\n\nDetalhes: {ex.Message}",
                "Lynext — Atualizações",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
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
            "O registro persistente de alterações será implementado junto com o motor de otimização. Esta versão ainda não aplica ajustes.",
            "Lynext — Histórico",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
}
