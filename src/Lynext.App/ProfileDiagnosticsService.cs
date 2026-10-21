using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Management;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Lynext;

public sealed record StartupEntry(string Name, string Origin, string Location, string State, string Impact);
public sealed record PowerCommandResult(bool Success, string Output, string Error, int? ExitCode);

/// <summary>Read-only profile inventory and explicitly requested powercfg reports.</summary>
public static class ProfileDiagnosticsService
{
    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus
    {
        public byte AcLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out SystemPowerStatus status);

    private static readonly string ReportDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Reports");

    public static IReadOnlyList<StartupEntry> ReadStartupEntries()
    {
        var entries = new List<StartupEntry>();
        ReadRunKey(Registry.CurrentUser, @"Software\Microsoft\Windows\CurrentVersion\Run", "Usuário atual", entries);
        ReadRunKey(Registry.LocalMachine, @"Software\Microsoft\Windows\CurrentVersion\Run", "Todos os usuários", entries);
        ReadRunKey(Registry.LocalMachine, @"Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run", "Todos os usuários (32 bits)", entries);
        ReadStartupFolder(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Pasta do usuário", entries);
        ReadStartupFolder(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup), "Pasta comum", entries);
        return entries.OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
    }

    private static void ReadRunKey(RegistryKey root, string path, string origin, List<StartupEntry> entries)
    {
        try
        {
            using var key = root.OpenSubKey(path, writable: false);
            if (key is null) return;
            foreach (var name in key.GetValueNames())
            {
                if (key.GetValue(name) is null) continue;
                entries.Add(new(name, origin, $"{root.Name}\\{path} (argumentos omitidos)", "Habilitado (observado)", "Impacto não medido"));
            }
        }
        catch { /* Permission or registry-view limitations are intentionally non-fatal. */ }
    }

    private static void ReadStartupFolder(string folder, string origin, List<StartupEntry> entries)
    {
        try
        {
            if (!Directory.Exists(folder)) return;
            foreach (var path in Directory.EnumerateFiles(folder))
                entries.Add(new(Path.GetFileNameWithoutExtension(path), origin, "Pasta Startup (caminho completo omitido)", "Habilitado (observado)", "Impacto não medido"));
        }
        catch { /* Keep inventory read-only and best effort. */ }
    }

    public static string RunLiteDiagnostic()
    {
        var entries = ReadStartupEntries();
        var lines = new List<string>
        {
            "LITE — revisão somente de leitura",
            $"Itens de inicialização encontrados: {entries.Count}. Impacto não medido pelo Lynext.",
            "Nenhum item foi desativado. Revise somente aplicativos que você reconhece nas configurações nativas.",
            "Efeitos visuais alteram aparência e acessibilidade; não há ganho de FPS presumido.",
            "Atividade em segundo plano afeta notificações e sincronização, e depende do suporte de cada aplicativo.",
            "Limpeza e armazenamento serão feitos pelo Windows; o Lynext não exclui arquivos pessoais.",
            ""
        };
        lines.AddRange(entries.Select(item => $"• {item.Name} — {item.Origin}; {item.State}; {item.Impact}\n  {item.Location}"));
        if (entries.Count == 0) lines.Add("Nenhum item foi listado ou o acesso não está disponível; isso não comprova ausência de inicialização automática.");
        return string.Join(Environment.NewLine, lines);
    }

    public static string RunBusinessDiagnostic()
    {
        var lines = new List<string> { "EMPRESARIAL — diagnóstico local, somente leitura", "Nenhum dado é enviado. Nomes e endereços completos são omitidos." };
        try
        {
            var interfaces = NetworkInterface.GetAllNetworkInterfaces();
            var connected = interfaces.Count(adapter => adapter.OperationalStatus == OperationalStatus.Up);
            lines.Add($"Rede: {(connected > 0 ? "Normal (" + connected + " adaptador(es) ativo(s))" : "Aviso: nenhum adaptador reporta estado conectado")}. DNS, gateway e endereços não são exibidos nem modificados.");
            var vpnObserved = interfaces.Any(a => a.NetworkInterfaceType == NetworkInterfaceType.Ppp && a.OperationalStatus == OperationalStatus.Up);
            lines.Add($"Adaptadores enumerados: {interfaces.Length}. VPN: {(vpnObserved ? "conexão PPP ativa observada" : "não identificada por este método; estado desconhecido para outros tipos de túnel")}.");
        }
        catch { lines.Add("Rede: informação indisponível."); }

        AddPrinterSummary(lines);
        AddWmiSummary(lines, "Serviço de impressão", "SELECT State FROM Win32_Service WHERE Name='Spooler'",
            item => "Spooler: " + (item["State"]?.ToString() ?? "estado desconhecido"));

        var managed = HasPolicySignals();
        lines.Add("Gerenciamento por política: " + (managed switch { true => "sinais encontrados; não altere configurações e consulte o administrador", false => "nenhum sinal local conhecido (isso não prova que o dispositivo não é gerenciado)", _ => "estado desconhecido" }));
        lines.Add("Atualizações, Defender, firewall, VPN, rede, filas e serviços não foram alterados. Esta triagem não certifica integridade ou compatibilidade completa.");
        lines.Add("Resumo do histórico Lynext: " + OptimizationService.GetStatusSummary());
        return string.Join(Environment.NewLine, lines);
    }

    private static bool? HasPolicySignals()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate", writable: false);
            if (key is not null && key.GetValueNames().Length > 0) return true;
            using var enrollment = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Enrollments", writable: false);
            if (enrollment is not null && enrollment.GetSubKeyNames().Length > 0) return true;
            return false;
        }
        catch { return null; }
    }

    private static void AddWmiSummary(List<string> lines, string label, string query, Func<ManagementObject, string> format)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(query);
            using var results = searcher.Get();
            var items = results.Cast<ManagementObject>().Select(format).ToArray();
            lines.Add(label + ": " + (items.Length == 0 ? "nenhum item encontrado; estado pode ser indisponível" : string.Join("; ", items)));
        }
        catch { lines.Add(label + ": informação indisponível ou não suportada."); }
    }

    private static void AddPrinterSummary(List<string> lines)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT WorkOffline FROM Win32_Printer");
            using var results = searcher.Get();
            var printers = results.Cast<ManagementObject>().ToArray();
            var offline = printers.Count(item => Convert.ToBoolean(item["WorkOffline"] ?? false));
            lines.Add(printers.Length == 0
                ? "Impressoras: nenhuma enumerada ou informação indisponível."
                : $"Impressoras: {printers.Length} enumerada(s); {offline} marcada(s) offline. Funcionamento e fila de impressão não confirmados. Nomes omitidos.");
        }
        catch { lines.Add("Impressoras: informação indisponível ou não suportada."); }
    }

    public static string RunEconomyDiagnostic(Func<string, PowerCommandResult>? runner = null)
    {
        string batteryObservation;
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT EstimatedChargeRemaining, BatteryStatus FROM Win32_Battery");
            using var batteries = searcher.Get();
            var found = batteries.Cast<ManagementObject>().ToArray();
            batteryObservation = found.Length == 0
                ? "Bateria: não detectada por WMI; pode ser desktop ou falta de suporte/dados. Opções específicas de bateria não serão presumidas."
                : "Bateria: detectada; nível " + (found[0]["EstimatedChargeRemaining"]?.ToString() ?? "indisponível") + "% ; status " + (found[0]["BatteryStatus"]?.ToString() ?? "indisponível") + ".";
        }
        catch { batteryObservation = "Bateria: estado desconhecido (consulta indisponível). Não será presumido um notebook."; }
        return BuildEconomyDiagnostic(batteryObservation, runner ?? RunPowerCommand, ReadPowerSource());
    }

    public static string BuildEconomyDiagnostic(string batteryObservation, Func<string, PowerCommandResult> runner, string powerSourceObservation = "Alimentação: estado desconhecido.")
    {
        ArgumentNullException.ThrowIfNull(runner);
        var lines = new List<string> { "ECONOMIA — diagnóstico somente de leitura", batteryObservation, powerSourceObservation };
        var scheme = runner("/getactivescheme");
        lines.Add("Plano ativo: " + (scheme.Success ? Sanitize(scheme.Output) : "não confirmado; " + Sanitize(scheme.Error)));
        var plans = runner("/list");
        lines.Add("Planos de energia: " + (plans.Success ? CountPlanLines(plans.Output) + " listado(s); nenhum plano foi ativado ou substituído." : "lista indisponível."));
        lines.Add("Tela/suspensão: o Lynext não altera temporizadores; use Energia e bateria no Windows para revisar valores de bateria e tomada.");
        lines.Add("Limite de carga: não há controle universal. A compatibilidade depende do firmware e do fabricante.");
        return string.Join(Environment.NewLine, lines);
    }

    private static string ReadPowerSource()
    {
        try
        {
            if (!GetSystemPowerStatus(out var status)) return "Alimentação: estado desconhecido (API indisponível).";
            var source = status.AcLineStatus switch
            {
                0 => "bateria",
                1 => "alimentação externa",
                _ => "origem desconhecida"
            };
            var level = status.BatteryLifePercent == 255 ? "nível indisponível" : $"nível reportado {status.BatteryLifePercent}%";
            var battery = status.BatteryFlag == 255 ? "estado da bateria indisponível" : (status.BatteryFlag & 128) != 0 ? "sem bateria detectada pela API" : level;
            return $"Alimentação atual: {source}; {battery}.";
        }
        catch (Exception ex) { return "Alimentação: estado desconhecido (" + ex.GetType().Name + ")."; }
    }

    public static PowerCommandResult GeneratePowerReport(string reportType, Func<string, PowerCommandResult>? runner = null)
    {
        var args = GetPowerReportArguments(reportType);
        Directory.CreateDirectory(ReportDirectory);
        var output = Path.Combine(ReportDirectory, $"{reportType}-{DateTime.Now:yyyyMMdd-HHmmss}.html");
        // powercfg writes to the current directory unless /output is explicit.
        var fullArgs = args + " /output \"" + output + "\"";
        var result = (runner ?? RunPowerCommand)(fullArgs);
        return result.Success && File.Exists(output)
            ? result with { Output = output }
            : result with { Success = false, Error = string.IsNullOrWhiteSpace(result.Error) ? "O relatório não foi encontrado no local de saída esperado." : result.Error };
    }

    public static string GetPowerReportArguments(string reportType) => reportType switch
    {
        "battery" => "/batteryreport",
        "energy" => "/energy /duration 10",
        "sleepstudy" => "/sleepstudy /duration 3",
        _ => throw new ArgumentOutOfRangeException(nameof(reportType))
    };

    private static PowerCommandResult RunPowerCommand(string arguments)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo("powercfg.exe", arguments)
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
            if (process is null) return new(false, "", "Não foi possível iniciar powercfg.", null);
            if (!process.WaitForExit(30_000)) { process.Kill(entireProcessTree: true); return new(false, "", "Tempo limite ao gerar relatório.", null); }
            return new(process.ExitCode == 0, process.StandardOutput.ReadToEnd(), process.StandardError.ReadToEnd(), process.ExitCode);
        }
        catch (Exception ex) { return new(false, "", ex.Message, null); }
    }

    private static string CountPlanLines(string output) => output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Count(line => line.Contains("GUID", StringComparison.OrdinalIgnoreCase)).ToString();
    private static string Sanitize(string value) => string.Join(" ", value.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Select(line => line.Trim())).Trim();
}
