using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Management;
using Microsoft.Win32;

namespace Lynext;

public sealed record LiteProcessObservation(
    string Name, int ProcessId, double? CpuPercent, long WorkingSetBytes,
    string ExecutablePath, string PublisherMetadata, string Origin);

public sealed record LiteDriveObservation(string Name, long TotalBytes, long FreeBytes);

public sealed record LiteSystemSnapshot(
    DateTimeOffset CapturedAt, string WindowsVersion, string Processor,
    int LogicalProcessors, int PhysicalCores, double InstalledMemoryGb,
    long? AvailableMemoryBytes, IReadOnlyList<LiteDriveObservation> Drives,
    IReadOnlyList<LiteProcessObservation> Processes, string PowerStatus,
    string PowerSettings, string HistorySummary);

/// <summary>Local, read-only system, storage and process sampling for Lynext Lite.</summary>
public static class LiteSystemDiagnosticsService
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MemoryStatusEx
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx buffer);

    public static LiteSystemSnapshot ReadSnapshot(TimeSpan? processSampleWindow = null)
    {
        var hardware = HardwareInfoService.Read();
        var requestedWindow = processSampleWindow ?? TimeSpan.FromMilliseconds(700);
        var sampleStarted = Stopwatch.GetTimestamp();
        var before = ReadProcesses();
        Thread.Sleep(requestedWindow);
        var after = ReadProcesses();
        var elapsed = Stopwatch.GetElapsedTime(sampleStarted);
        var processRows = BuildProcessRows(before, after, elapsed, Environment.ProcessorCount);

        long? availableMemory = null;
        try
        {
            var memory = new MemoryStatusEx { Length = (uint)Marshal.SizeOf<MemoryStatusEx>() };
            if (GlobalMemoryStatusEx(ref memory)) availableMemory = checked((long)memory.AvailablePhysical);
        }
        catch { /* Preserve unavailable memory as unknown. */ }

        var drives = new List<LiteDriveObservation>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (drive.IsReady && drive.DriveType == DriveType.Fixed)
                    drives.Add(new(drive.Name, drive.TotalSize, drive.AvailableFreeSpace));
            }
            catch { /* A disconnected or restricted drive is omitted, not treated as empty. */ }
        }

        return new(DateTimeOffset.Now, hardware.WindowsVersion, hardware.Processor,
            hardware.LogicalProcessors, hardware.PhysicalCores, hardware.InstalledMemoryGb,
            availableMemory, drives, processRows, ReadPowerStatus(), ReadPowerSettings(),
            OptimizationService.GetStatusSummary());
    }

    public static string BuildReport(LiteSystemSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        var lines = new List<string>
        {
            "LYNEXT LITE — análise local e somente de leitura",
            $"Captura: {snapshot.CapturedAt:dd/MM/yyyy HH:mm:ss}. CPU e memória variam conforme os aplicativos abertos; esta amostra não classifica aplicativos como dispensáveis.",
            $"Windows: {Safe(snapshot.WindowsVersion)}",
            $"Processador: {Safe(snapshot.Processor)} • {snapshot.LogicalProcessors} processador(es) lógico(s) • núcleos físicos: {(snapshot.PhysicalCores > 0 ? snapshot.PhysicalCores.ToString() : "indisponíveis")}",
            $"RAM instalada: {(snapshot.InstalledMemoryGb > 0 ? $"{snapshot.InstalledMemoryGb:N1} GB" : "indisponível")} • memória física disponível: {FormatBytes(snapshot.AvailableMemoryBytes)}",
            "",
            "Armazenamento fixo (o Lynext não remove arquivos):"
        };
        if (snapshot.Drives.Count == 0) lines.Add("• Unidades fixas: informação indisponível.");
        else lines.AddRange(snapshot.Drives.Select(d => $"• {Safe(d.Name)} — livre {FormatBytes(d.FreeBytes)} de {FormatBytes(d.TotalBytes)}."));

        lines.Add("");
        lines.Add("Processos — amostra aproximada de 700 ms; uso alto não significa desperdício:");
        if (snapshot.Processes.Count == 0) lines.Add("• Nenhum processo pôde ser amostrado.");
        else
        {
            var processRows = snapshot.Processes.OrderByDescending(p => p.CpuPercent ?? -1).Take(5)
                .Concat(snapshot.Processes.OrderByDescending(p => p.WorkingSetBytes).Take(5))
                .DistinctBy(p => p.ProcessId).Take(10);
            foreach (var process in processRows)
            {
                var cpu = process.CpuPercent.HasValue ? $"CPU {process.CpuPercent.Value:N1}%" : "CPU não disponível";
                var path = string.IsNullOrWhiteSpace(process.ExecutablePath) ? "caminho indisponível" : Safe(process.ExecutablePath);
                var publisher = string.IsNullOrWhiteSpace(process.PublisherMetadata) ? "fabricante não identificado" : $"fabricante informado nos metadados: {Safe(process.PublisherMetadata)} (assinatura não verificada)";
                lines.Add($"• {Safe(process.Name)} (PID {process.ProcessId}) — {cpu}; memória {FormatBytes(process.WorkingSetBytes)}; origem: {Safe(process.Origin)}; {publisher}; {path}");
            }
        }
        lines.Add("Nenhum processo foi encerrado. O Lynext não oferece encerramento quando identidade e consequência não puderem ser verificadas.");
        lines.Add("");
        lines.Add("Inicialização: use Configurações > Aplicativos > Inicialização para revisar cada item. O impacto só é mostrado quando o Windows o informa; o Lynext não desativa itens desconhecidos.");
        lines.Add("Atividade em segundo plano: o controle varia por tipo de aplicativo e versão do Windows; alterações podem atrasar notificações e sincronização.");
        lines.Add("Energia: " + Safe(snapshot.PowerStatus));
        lines.Add("Tela/suspensão: " + Safe(snapshot.PowerSettings));
        lines.Add("Limpeza: consulte as recomendações do Windows; Downloads, documentos e caches de shaders não são removidos pelo Lynext.");
        lines.Add("Histórico Lynext: " + Safe(snapshot.HistorySummary));
        lines.Add("Ações seguras disponíveis: revisar inicialização, abrir opções nativas de efeitos visuais/armazenamento/atividade em segundo plano e configurar o plano Lynext Lite após confirmação.");
        return string.Join(Environment.NewLine, lines);
    }

    public static IReadOnlyList<LiteProcessObservation> BuildProcessRows(
        IReadOnlyDictionary<int, ProcessSample> before,
        IReadOnlyDictionary<int, ProcessSample> after,
        TimeSpan elapsed, int logicalProcessors)
    {
        if (elapsed <= TimeSpan.Zero || logicalProcessors <= 0) return [];
        var rows = after.Values.Select(current =>
        {
            double? cpu = null;
            if (before.TryGetValue(current.ProcessId, out var previous))
            {
                var delta = current.CpuTime - previous.CpuTime;
                cpu = Math.Clamp(delta.TotalMilliseconds / (elapsed.TotalMilliseconds * logicalProcessors) * 100d, 0d, 100d);
            }
            return new LiteProcessObservation(current.Name, current.ProcessId, cpu, current.WorkingSetBytes,
                current.ExecutablePath, current.PublisherMetadata, current.Origin);
        }).ToArray();
        var byCpu = rows.OrderByDescending(p => p.CpuPercent ?? -1).Take(10);
        var byMemory = rows.OrderByDescending(p => p.WorkingSetBytes).Take(10);
        return byCpu.Concat(byMemory).DistinctBy(p => p.ProcessId).ToArray();
    }

    public sealed record ProcessSample(int ProcessId, string Name, TimeSpan CpuTime, long WorkingSetBytes,
        string ExecutablePath, string PublisherMetadata, string Origin);

    private static Dictionary<int, ProcessSample> ReadProcesses()
    {
        var samples = new Dictionary<int, ProcessSample>();
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    var path = process.MainModule?.FileName ?? string.Empty;
                    var company = string.Empty;
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        try { company = FileVersionInfo.GetVersionInfo(path).CompanyName?.Trim() ?? string.Empty; }
                        catch { }
                    }
                    var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                    var origin = !string.IsNullOrWhiteSpace(path) && path.StartsWith(windows, StringComparison.OrdinalIgnoreCase)
                        ? "caminho dentro da pasta do Windows (não é validação de assinatura)"
                        : string.IsNullOrWhiteSpace(path) ? "origem desconhecida" : "aplicativo/outro caminho; função não inferida";
                    samples[process.Id] = new(process.Id, process.ProcessName, process.TotalProcessorTime,
                        process.WorkingSet64, path, company, origin);
                }
                catch { /* Access denied or exited processes remain unavailable, never actionable. */ }
            }
        }
        return samples;
    }

    private static string ReadPowerStatus()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT EstimatedChargeRemaining, BatteryStatus FROM Win32_Battery");
            using var items = searcher.Get();
            var battery = items.Cast<ManagementObject>().FirstOrDefault();
            var power = battery is null ? "bateria não detectada por WMI" : $"bateria detectada; nível {battery["EstimatedChargeRemaining"]?.ToString() ?? "indisponível"}%";
            return power + "; origem de alimentação atual: " + (GetSystemPowerStatus(out var status) ? status.AcLineStatus switch { 0 => "bateria", 1 => "tomada", _ => "desconhecida" } : "desconhecida");
        }
        catch { return "estado da bateria/alimentação indisponível"; }
    }

    private static string ReadPowerSettings()
    {
        try
        {
            var active = RunPowercfg("/getactivescheme");
            if (!active.Success) return "plano ativo não confirmado";
            var guid = System.Text.RegularExpressions.Regex.Match(active.Output,
                @"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b");
            if (!guid.Success) return "GUID do plano ativo não confirmado";
            var query = RunPowercfg("/query", guid.Value);
            return query.Success ? SummarizePowerQuery(query.Output) : "consulta do plano ativo indisponível";
        }
        catch { return "consulta indisponível"; }
    }

    private static (bool Success, string Output) RunPowercfg(params string[] arguments)
    {
        var start = new ProcessStartInfo("powercfg.exe")
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start);
        if (process is null) return (false, string.Empty);
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(5_000))
        {
            try { process.Kill(true); } catch { }
            return (false, string.Empty);
        }
        Task.WaitAll(stdout, stderr);
        return (process.ExitCode == 0, stdout.Result);
    }

    public static string SummarizePowerQuery(string output)
    {
        if (string.IsNullOrWhiteSpace(output)) return "valores não confirmados";
        var guid = System.Text.RegularExpressions.Regex.Match(output, @"(?i)Power Scheme GUID:\s*\{?([0-9a-f-]{36})\}?");
        var screen = System.Text.RegularExpressions.Regex.Match(output, @"(?im)Video idle timeout.*?\r?\n(?:.*\r?\n){0,5}.*?AC Power Setting Index:\s*(0x[0-9a-f]+).*?\r?\n.*?DC Power Setting Index:\s*(0x[0-9a-f]+)");
        var sleep = System.Text.RegularExpressions.Regex.Match(output, @"(?im)Sleep idle timeout.*?\r?\n(?:.*\r?\n){0,5}.*?AC Power Setting Index:\s*(0x[0-9a-f]+).*?\r?\n.*?DC Power Setting Index:\s*(0x[0-9a-f]+)");
        return $"plano {(guid.Success ? guid.Groups[1].Value : "desconhecido")}; tela {(screen.Success ? screen.Groups[1].Value + "/" + screen.Groups[2].Value : "não confirmada")}; suspensão {(sleep.Success ? sleep.Groups[1].Value + "/" + sleep.Groups[2].Value : "não confirmada")}. Valores hexadecimais AC/DC; não alterados.";
    }

    private static string FormatBytes(long? bytes) => bytes.HasValue ? FormatBytes(bytes.Value) : "indisponível";
    private static string FormatBytes(long bytes) => bytes < 0 ? "indisponível" : $"{bytes / 1024d / 1024d / 1024d:N1} GB";
    private static string Safe(string? text) => string.IsNullOrWhiteSpace(text) ? "indisponível" : text.Replace('\r', ' ').Replace('\n', ' ').Trim();

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemPowerStatus { public byte AcLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public uint BatteryLifeTime, BatteryFullLifeTime; }
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemPowerStatus(out SystemPowerStatus status);
}

