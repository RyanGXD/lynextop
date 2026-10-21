using Microsoft.Win32;
using System.IO;
using System.Management;
using System.Diagnostics;
using System.Text.Json;

namespace Lynext;

public sealed record StoreDiagnosticItem(string Name, string Status, string Details);
public sealed record StoreDiagnosticReport(DateTimeOffset ScannedAt, IReadOnlyList<StoreDiagnosticItem> Items)
{
    public bool UacDisabled => Items.Any(item => item.Name == "UAC: EnableLUA" && item.Status == "Desativado");
    public bool CanRepairUac => UacDisabled && Items.Any(item => item.Name == "UAC policy: EnableLUA" && item.Status == "Ausente");
    public string ToDisplayText() => "Diagnóstico somente de leitura — " + ScannedAt.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss") + Environment.NewLine + Environment.NewLine
        + string.Join(Environment.NewLine, Items.Select(item => $"[{item.Status}] {item.Name}: {item.Details}"))
        + Environment.NewLine + Environment.NewLine
        + "O diagnóstico não define a causa sozinho. Serviços em Manual/acionamento sob demanda não são considerados falha apenas por estarem parados.";
}

public static class StoreDiagnosticsService
{
    private const string SystemPolicies = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System";
    private static readonly string[] Services =
    [
        "AppXSvc", "ClipSVC", "InstallService", "LicenseManager", "BITS", "DoSvc",
        "GamingServices", "GamingServicesNet", "XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc"
    ];

    public static StoreDiagnosticReport Run()
    {
        var items = new List<StoreDiagnosticItem>();
        ReadWindowsVersion(items);
        ReadUac(items);
        ReadServices(items);
        ReadPackages(items);
        ReadLynextHistory(items);
        AppendAudit("Diagnóstico Store/Xbox/UAC", true, $"Verificações registradas: {items.Count}; EnableLUA desativado={items.Any(item => item.Name == "UAC: EnableLUA" && item.Status == "Desativado")}. Nenhuma configuração do Windows foi alterada.");
        return new(DateTimeOffset.Now, items);
    }

    public static StoreDiagnosticItem? RepairEnableLua(int expectedCurrentValue)
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(SystemPolicies, writable: true)
                ?? throw new InvalidOperationException("Não foi possível abrir a chave de política do UAC para gravação.");
            var old = key.GetValue("EnableLUA", null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            if (old is not int and not uint)
                throw new InvalidOperationException("O valor EnableLUA está ausente ou tem tipo inesperado. O Lynext não inventará o valor anterior; nenhuma alteração foi feita.");
            var previous = Convert.ToInt32(old);
            if (previous != expectedCurrentValue)
                throw new InvalidOperationException($"EnableLUA mudou depois do diagnóstico (esperado {expectedCurrentValue}, atual {previous}). Execute o diagnóstico novamente; nenhuma alteração foi feita.");
            if (previous != 0)
                throw new InvalidOperationException("O reparo automatizado só aceita o estado explicitamente observado EnableLUA=0; nenhuma alteração foi feita.");
            using (var policyKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Windows\System"))
            {
                if (policyKey?.GetValueNames().Contains("EnableLUA", StringComparer.OrdinalIgnoreCase) == true)
                    throw new InvalidOperationException("EnableLUA está definido por política de organização. O Lynext não sobrescreverá uma política administrada.");
            }
            if (previous == 1)
                return new("UAC: EnableLUA", "Sem alteração", "Já estava habilitado.");
            key.SetValue("EnableLUA", 1, RegistryValueKind.DWord);
            var verified = Convert.ToInt32(key.GetValue("EnableLUA", -1, RegistryValueOptions.DoNotExpandEnvironmentNames));
            if (verified != 1)
                throw new InvalidOperationException("O Windows não confirmou EnableLUA=1 após a gravação.");
            var result = new StoreDiagnosticItem("UAC: EnableLUA", "Corrigido (reinicialização necessária)", $"Valor anterior {previous}; valor aplicado 1 e verificado. Reinicie o Windows para a alteração produzir efeito.");
            AppendAudit("Reparo UAC", true, result.Details);
            return result;
        }
        catch (Exception ex)
        {
            AppendAudit("Reparo UAC", false, ex.Message);
            throw;
        }
    }

    public static void LogRepairDeclined() => AppendAudit("Reparo UAC recusado pelo usuário", true, "Nenhuma configuração do Windows foi alterada.");
    public static void LogDiagnosticFailure(string details) => AppendAudit("Diagnóstico Store/Xbox/UAC", false, details);

    private static void ReadUac(List<StoreDiagnosticItem> items)
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(SystemPolicies);
            ReadDword(key, "EnableLUA", items, "UAC: EnableLUA", value => value switch
            {
                1 => ("Ativo", "Valor 1; UAC habilitado."),
                0 => ("Desativado", "Valor 0; UAC está desabilitado."),
                _ => ("Valor inesperado", $"Valor {value}; reparo automático recusado.")
            });
            ReadDword(key, "ConsentPromptBehaviorAdmin", items, "UAC: ConsentPromptBehaviorAdmin", value => ("Informativo", $"Valor atual {value}; o comportamento recomendado depende da política organizacional."));
            ReadDword(key, "PromptOnSecureDesktop", items, "UAC: PromptOnSecureDesktop", value => ("Informativo", $"Valor atual {value}; o comportamento recomendado depende da política organizacional."));
            using var policyKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Windows\System");
            ReadDword(policyKey, "EnableLUA", items, "UAC policy: EnableLUA", value => ("Definido por política", $"Política organizacional define EnableLUA={value}; correção automática bloqueada."));
        }
        catch (Exception ex) { items.Add(new("Políticas UAC", "Não verificado", ex.Message)); }
    }

    private static void ReadWindowsVersion(List<StoreDiagnosticItem> items)
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            var product = Convert.ToString(key?.GetValue("ProductName")) ?? "Windows não identificado";
            var displayVersion = Convert.ToString(key?.GetValue("DisplayVersion")) ?? "versão indisponível";
            var build = Convert.ToString(key?.GetValue("CurrentBuildNumber")) ?? "build indisponível";
            items.Add(new("Versão do Windows", "Informativo", $"{product}; {displayVersion}; build {build}. A análise não presume padrões específicos de serviços para esta edição."));
        }
        catch (Exception ex) { items.Add(new("Versão do Windows", "Não verificado", ex.Message)); }
    }

    private static void ReadDword(RegistryKey? key, string name, List<StoreDiagnosticItem> items, string label, Func<int, (string Status, string Details)> describe)
    {
        if (key is null || !key.GetValueNames().Contains(name, StringComparer.OrdinalIgnoreCase))
        {
            items.Add(new(label, "Ausente", "Não existe valor explícito; nenhuma configuração padrão foi presumida."));
            return;
        }
        if (key.GetValueKind(name) != RegistryValueKind.DWord)
        {
            items.Add(new(label, "Tipo inesperado", "O valor não é DWORD; reparo automático recusado."));
            return;
        }
        var result = describe(Convert.ToInt32(key.GetValue(name, 0, RegistryValueOptions.DoNotExpandEnvironmentNames)));
        items.Add(new(label, result.Status, result.Details));
    }

    private static void ReadServices(List<StoreDiagnosticItem> items)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name, State, StartMode, Status, ExitCode, Dependencies FROM Win32_Service");
            var found = new Dictionary<string, (string State, string StartMode, string Status, string ExitCode, string[] Dependencies)>(StringComparer.OrdinalIgnoreCase);
            foreach (ManagementObject service in searcher.Get())
            {
                using (service)
                {
                    var serviceName = Convert.ToString(service["Name"]);
                    if (!string.IsNullOrWhiteSpace(serviceName))
                        found[serviceName] = (
                            Convert.ToString(service["State"]) ?? "Desconhecido",
                            Convert.ToString(service["StartMode"]) ?? "Desconhecido",
                            Convert.ToString(service["Status"]) ?? "Desconhecido",
                            Convert.ToString(service["ExitCode"]) ?? "Desconhecido",
                            service["Dependencies"] as string[] ?? []);
                }
            }
            foreach (var name in Services)
            {
                if (!found.TryGetValue(name, out var service))
                {
                    items.Add(new("Serviço " + name, "Ausente", "Não instalado nesta versão/edição; nenhuma suposição de existência."));
                    continue;
                }
                var (state, start, statusCode, exitCode, dependencies) = service;
                var status = start.Equals("Disabled", StringComparison.OrdinalIgnoreCase) ? "Desativado" : state;
                var dependencyText = dependencies.Length == 0 ? "Sem dependências listadas por Win32_Service." : "Dependências: " + string.Join(", ", dependencies.Select(dependency =>
                    found.TryGetValue(dependency, out var dependencyState)
                        ? $"{dependency} (estado={dependencyState.State}, inicialização={dependencyState.StartMode}, Status={dependencyState.Status}, código={dependencyState.ExitCode})"
                        : $"{dependency} (não encontrado na consulta)"));
                items.Add(new("Serviço " + name, status, $"Estado={state}; inicialização={start}; Status={statusCode}; código de saída={exitCode}. {dependencyText}"));
            }
        }
        catch (Exception ex) { items.Add(new("Serviços Store/Xbox", "Não verificado", ex.Message)); }
    }

    private static void ReadPackages(List<StoreDiagnosticItem> items)
    {
        // Fixed, read-only queries. No script text, paths or service names come from user input.
        const string script = """
            $ErrorActionPreference = 'Stop'
            $names = @('Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.StorePurchaseApp','Microsoft.GamingServices','Microsoft.XboxIdentityProvider','Microsoft.XboxApp')
            foreach ($n in $names) {
                try {
                    $p = @(Get-AppxPackage -Name $n -ErrorAction Stop)
                    if ($p.Count) { foreach ($x in $p) { '{0}|Instalado (usuário atual)|{1}|{2}' -f $n,$x.PackageFullName,$x.Status } }
                    else { '{0}|Não instalado para o usuário atual||' -f $n }
                } catch { '{0}|Instalação não verificada||{1}' -f $n,$_.Exception.Message }
                try {
                    $q = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object DisplayName -eq $n)
                    if ($q.Count) { foreach ($x in $q) { 'Provisionado|{0}|{1}|Imagem Windows' -f $n,$x.PackageName } }
                    else { 'Provisionado|{0}|Não provisionado|' -f $n }
                } catch { 'Provisionado|{0}|Não verificado|{1}' -f $n,$_.Exception.Message }
            }
            try {
                $events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppXDeploymentServer/Operational'; StartTime=(Get-Date).AddDays(-7)} -MaxEvents 30 -ErrorAction Stop
                foreach ($e in $events) { if ($e.Level -le 3) { 'EVENTO|{0}|{1}|{2}' -f $e.TimeCreated.ToString('s'),$e.Id,($e.Message -replace '[\r\n]+',' ') } }
            } catch { 'EVENTO|Indisponível||' }
            """;
        try
        {
            var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
            var exe = Path.Combine(system, "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(exe)) throw new FileNotFoundException("Windows PowerShell não encontrado.");
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = exe,
                Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -Command \"" + script.Replace("\"", "`\"", StringComparison.Ordinal) + "\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }) ?? throw new InvalidOperationException("Não foi possível iniciar consulta de pacotes.");
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(15000)) { process.Kill(entireProcessTree: true); throw new TimeoutException("Consulta de pacotes excedeu 15 segundos."); }
            var output = outputTask.GetAwaiter().GetResult();
            var error = errorTask.GetAwaiter().GetResult();
            if (process.ExitCode != 0) throw new InvalidOperationException(error);
            foreach (var line in output.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries))
            {
                var parts = line.Split(new[] { '|' }, 4, StringSplitOptions.None);
                if (parts[0] == "EVENTO") items.Add(new("Implantação AppX (7 dias)", parts.Length > 1 && parts[1] == "Indisponível" ? "Não verificado" : "Evento", parts.Length > 2 ? string.Join(" | ", parts.Skip(1)) : line));
                else if (parts[0] == "Provisionado" && parts.Length >= 3) items.Add(new("Pacote provisionado " + parts[1], parts[2], parts.Length > 3 ? parts[3] : string.Empty));
                else if (parts.Length >= 3) items.Add(new("Pacote " + parts[0], parts[1], string.Join(" | ", parts.Skip(2))));
            }
        }
        catch (Exception ex) { items.Add(new("Pacotes Store/Xbox e eventos AppX", "Não verificado", ex.Message)); }
    }

    private static void ReadLynextHistory(List<StoreDiagnosticItem> items)
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var history = Path.Combine(local, "Lynext", "Logs", "optimization-history.jsonl");
        var legacyBackup = Path.Combine(local, "Lynext", "performance_backup.json");
        if (!File.Exists(legacyBackup))
            legacyBackup = Path.Combine(Path.GetTempPath(), "Lynext", "performance_backup.json");
        if (File.Exists(history))
        {
            var relevant = File.ReadLines(history).Where(line => line.Contains("Store", StringComparison.OrdinalIgnoreCase)
                || line.Contains("Xbox", StringComparison.OrdinalIgnoreCase) || line.Contains("UAC", StringComparison.OrdinalIgnoreCase)
                || line.Contains("EnableLUA", StringComparison.OrdinalIgnoreCase) || line.Contains("serviço", StringComparison.OrdinalIgnoreCase)).TakeLast(20).ToArray();
            items.Add(new("Histórico Lynext atual", relevant.Length == 0 ? "Sem referência" : "Referência encontrada", relevant.Length == 0 ? "Nenhuma entrada relacionada encontrada." : string.Join(" ; ", relevant)));
        }
        else items.Add(new("Histórico Lynext atual", "Ausente", "Nenhum histórico local disponível."));
        if (File.Exists(legacyBackup))
        {
            items.Add(new("Backup do módulo PowerShell antigo", "Existe; revisão manual necessária", legacyBackup));
            ReadLegacyBackup(legacyBackup, items);
        }
        else items.Add(new("Backup do módulo PowerShell antigo", "Ausente", "Nenhum backup legado encontrado."));

        var legacyLogs = Path.Combine(local, "Lynext", "Logs");
        if (!Directory.Exists(legacyLogs))
            legacyLogs = Path.Combine(Path.GetTempPath(), "Lynext", "Logs");
        try
        {
            var matches = Directory.Exists(legacyLogs)
                ? Directory.EnumerateFiles(legacyLogs, "PerformanceApp_*.log")
                    .SelectMany(path => File.ReadLines(path).Select(line => (Path: Path.GetFileName(path), Line: line)))
                    .Where(entry => entry.Line.Contains("START:", StringComparison.OrdinalIgnoreCase)
                        || entry.Line.Contains("OK:", StringComparison.OrdinalIgnoreCase)
                        || entry.Line.Contains("FAIL:", StringComparison.OrdinalIgnoreCase)
                        || entry.Line.Contains("Reset", StringComparison.OrdinalIgnoreCase))
                    .TakeLast(30).ToArray()
                : Array.Empty<(string Path, string Line)>();
            items.Add(new("Histórico de otimização PowerShell antigo", matches.Length == 0 ? "Sem referência" : "Ações antigas registradas", matches.Length == 0
                ? "Nenhuma ação antiga identificada nos logs locais."
                : string.Join(" ; ", matches.Select(entry => entry.Path + ": " + entry.Line))));
        }
        catch (Exception ex) { items.Add(new("Histórico PowerShell antigo", "Não verificado", ex.Message)); }
    }

    private static void ReadLegacyBackup(string path, List<StoreDiagnosticItem> items)
    {
        var known = new Dictionary<string, (RegistryHive Hive, string Path, string Name)>(StringComparer.OrdinalIgnoreCase)
        {
            ["AutoGameModeEnabled"] = (RegistryHive.CurrentUser, @"Software\Microsoft\GameBar", "AutoGameModeEnabled"),
            ["AllowAutoGameMode"] = (RegistryHive.CurrentUser, @"Software\Microsoft\GameBar", "AllowAutoGameMode"),
            ["AppCaptureEnabled"] = (RegistryHive.CurrentUser, @"Software\Microsoft\Windows\CurrentVersion\GameDVR", "AppCaptureEnabled"),
            ["GameDVR_Enabled"] = (RegistryHive.CurrentUser, @"System\GameConfigStore", "GameDVR_Enabled"),
            ["HwSchMode"] = (RegistryHive.LocalMachine, @"SYSTEM\CurrentControlSet\Control\GraphicsDrivers", "HwSchMode"),
            ["NetworkThrottlingIndex"] = (RegistryHive.LocalMachine, @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile", "NetworkThrottlingIndex"),
            ["SystemResponsiveness"] = (RegistryHive.LocalMachine, @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile", "SystemResponsiveness"),
            ["PowerThrottlingOff"] = (RegistryHive.LocalMachine, @"SYSTEM\CurrentControlSet\Control\Power\PowerThrottling", "PowerThrottlingOff"),
            ["GamesGpuPriority"] = (RegistryHive.LocalMachine, @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games", "GPU Priority"),
            ["GamesPriority"] = (RegistryHive.LocalMachine, @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games", "Priority")
        };
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            if (!document.RootElement.TryGetProperty("Registry", out var registry) || registry.ValueKind != JsonValueKind.Object)
            {
                items.Add(new("Comparação do backup antigo", "Formato desconhecido", "O backup não contém o catálogo esperado; nenhum reparo será presumido."));
                return;
            }
            foreach (var property in registry.EnumerateObject())
            {
                if (!known.TryGetValue(property.Name, out var target) || property.Value.ValueKind != JsonValueKind.Object)
                {
                    items.Add(new("Backup antigo: " + property.Name, "Ignorado", "Entrada fora do catálogo conhecido; nenhum caminho fornecido pelo arquivo é executado."));
                    continue;
                }
                var hadValue = property.Value.TryGetProperty("Exists", out var existsElement) && existsElement.ValueKind == JsonValueKind.True;
                var saved = hadValue && property.Value.TryGetProperty("Value", out var valueElement) ? valueElement.ToString() : "<ausente>";
                using var root = RegistryKey.OpenBaseKey(target.Hive, RegistryView.Default);
                using var key = root.OpenSubKey(target.Path);
                var current = key is null || !key.GetValueNames().Contains(target.Name, StringComparer.OrdinalIgnoreCase)
                    ? "<ausente>" : Convert.ToString(key.GetValue(target.Name, null, RegistryValueOptions.DoNotExpandEnvironmentNames)) ?? "<null>";
                items.Add(new("Backup antigo: " + property.Name, string.Equals(saved, current, StringComparison.Ordinal) ? "Igual ao backup" : "Divergente do backup",
                    $"Salvo antes do preset={saved}; atual={current}. O formato legado não registra o valor aplicado nem a origem de alterações posteriores, portanto a divergência não prova que Lynext causou a mudança e não pode ser restaurada automaticamente."));
            }
        }
        catch (Exception ex) { items.Add(new("Comparação do backup antigo", "Não verificado", ex.Message)); }
    }

    private static void AppendAudit(string action, bool success, string details)
    {
        try
        {
            var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Logs", "store-diagnostics.jsonl");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var line = System.Text.Json.JsonSerializer.Serialize(new { Timestamp = DateTimeOffset.Now, Action = action, Success = success, Details = details });
            File.AppendAllText(path, line + Environment.NewLine);
        }
        catch { }
    }
}
