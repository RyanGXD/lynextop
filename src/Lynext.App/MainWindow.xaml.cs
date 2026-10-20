using System.Windows;
using System.Windows.Controls;

namespace Lynext;

public partial class MainWindow : Window
{
    private HardwareSnapshot? _hardware;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshHardware();
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
            RamText.Text = $"Memória RAM instalada: {(_hardware.InstalledMemoryGb > 0 ? $"{_hardware.InstalledMemoryGb:N1} GB" : "não identificada")} • Núcleos físicos: {(_hardware.PhysicalCores > 0 ? _hardware.PhysicalCores : "indisponível")}";
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

    private void History_Click(object sender, RoutedEventArgs e)
    {
        MessageBox.Show(
            "O registro persistente de alterações será implementado junto com o motor de otimização. Esta versão ainda não aplica ajustes.",
            "Lynext — Histórico",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
}
