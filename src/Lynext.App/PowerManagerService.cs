using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Lynext;

public sealed record PowerCommandResult(int ExitCode, string Output, string Error = "");
public interface IPowerCommandRunner { PowerCommandResult Run(params string[] arguments); }
public interface IPowerSchemeDescriptionReader { string ReadDescription(string schemeGuid); }
public interface IPowerPolicyDetector { bool IsPowerManaged(); }
public sealed class WindowsPowerPolicyDetector : IPowerPolicyDetector
{
    public bool IsPowerManaged()
    {
        try
        {
            using var power = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Power");
            using var windowsPower = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Windows\Power");
            return power is not null || windowsPower is not null;
        }
        catch { return true; } // Unknown policy state fails closed.
    }
}

public sealed class PowerSchemeDescriptionReader : IPowerSchemeDescriptionReader
{
    public string ReadDescription(string schemeGuid)
    {
        try
        {
            var guid = Guid.Parse(schemeGuid);
            var buffer = new byte[4096];
            uint size = (uint)buffer.Length;
            if (PowerReadDescription(IntPtr.Zero, ref guid, IntPtr.Zero, IntPtr.Zero, buffer, ref size) != 0 || size < 2) return string.Empty;
            return System.Text.Encoding.Unicode.GetString(buffer, 0, (int)size).TrimEnd('\0');
        }
        catch { return string.Empty; }
    }
    [DllImport("powrprof.dll", CharSet = CharSet.Unicode)]
    private static extern uint PowerReadDescription(IntPtr rootPowerKey, ref Guid schemeGuid, IntPtr subgroupGuid, IntPtr settingGuid, byte[] buffer, ref uint bufferSize);
}

public sealed class PowerCfgCommandRunner : IPowerCommandRunner
{
    public PowerCommandResult Run(params string[] arguments)
    {
        var start = new ProcessStartInfo("powercfg.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Não foi possível iniciar powercfg.exe.");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit(20_000);
        if (!process.HasExited) { process.Kill(true); throw new TimeoutException("powercfg.exe excedeu o tempo limite."); }
        return new(process.ExitCode, output, error);
    }
}

public sealed record PowerProfilePlan(string Id, string Name, string Description, string? Guid, bool Exists, bool IsActive, string State);
public sealed record PowerManagerSnapshot(string? ActiveGuid, string? ActiveName, IReadOnlyList<PowerProfilePlan> Profiles, string? Error = null);
public sealed record PowerManagerOperation(bool Success, string Message, PowerManagerSnapshot? Snapshot = null);
public sealed record PowerProfileSettingTarget(string Key, string SubgroupGuid, string SettingGuid, uint Ac, uint Dc);
public sealed record PowerSettingValues(uint Ac, uint Dc);

/// <summary>Creates and manages only schemes recorded in the Lynext ownership manifest.</summary>
public sealed class PowerManagerService
{
    private const string BalancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e";
    private const string SubVideo = "7516b95f-f776-4464-8c53-06167f40cc99", VideoIdle = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e";
    private const string SubSleep = "238c9fa8-0aad-41ed-83f4-97be242c8f20", StandbyIdle = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da";
    private const string SubDisk = "0012ee47-9041-4b5d-9b77-535fba8b1442", DiskIdle = "6738e2c4-e8a5-4a42-b16a-e040e769756e";
    private const string SubCpu = "54533251-82be-4824-96c1-47b60b740d00", CpuMin = "893dee8e-2bef-41e0-89c6-b55d0929964c", CpuMax = "bc5038f7-23e0-4960-96da-33abaf5935ec";
    private readonly string Root;
    private readonly string ManifestPath;
    private readonly string BackupPath;
    private readonly string HistoryPath;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    private readonly IPowerCommandRunner _runner;
    private readonly IPowerSchemeDescriptionReader _descriptionReader;
    private readonly IPowerPolicyDetector _policyDetector;
    private static readonly (string Id, string Name, string Description, bool CpuMax)[] Definitions =
    [
        ("gamer-ultra", "Lynext Ultra Performance", "Desempenho de CPU máximo; mínimo e máximo em 100% em AC e DC.", true),
        ("gamer", "Lynext Gamer", "Perfil para jogos; CPU mínima e máxima em 100% em AC e DC.", true),
        ("business", "Lynext Empresarial", "Baseado em Balanced; preserva os valores de CPU herdados.", false),
        ("lite", "Lynext Lite", "Baseado em Balanced; preserva os valores de CPU herdados.", false),
        ("economy", "Lynext Economia", "Baseado em Balanced; usa configurações nativas de eficiência sem impor limites de CPU.", false)
    ];

    public PowerManagerService(IPowerCommandRunner? runner = null, IPowerSchemeDescriptionReader? descriptionReader = null, string? dataRoot = null, IPowerPolicyDetector? policyDetector = null)
    {
        _runner = runner ?? new PowerCfgCommandRunner();
        _descriptionReader = descriptionReader ?? new PowerSchemeDescriptionReader();
        _policyDetector = policyDetector ?? new WindowsPowerPolicyDetector();
        Root = dataRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "PowerManager");
        ManifestPath = Path.Combine(Root, "plans.json");
        BackupPath = Path.Combine(Root, "activation-backup.json");
        HistoryPath = Path.Combine(Root, "history.jsonl");
    }
    public static IReadOnlyList<(string Id, string Name, string Description, bool CpuMax)> Profiles => Definitions;

    public string ReadProfileSettings(string profileId)
    {
        var snapshot = ReadSnapshot();
        var profile = snapshot.Profiles.FirstOrDefault(p => p.Id == profileId);
        if (profile is null || !profile.Exists || profile.Guid is null) return "Valores reais indisponíveis: o plano Lynext ainda não foi criado ou sua propriedade não foi confirmada.";
        try
        {
            string Read(string label, string subgroup, string setting)
            {
                var value = Query(profile.Guid, subgroup, setting);
                return value is null ? $"{label}: não foi possível confirmar" : $"{label}: AC {FormatMinutes(value.Value.Ac)}, DC {FormatMinutes(value.Value.Dc)}";
            }
            var values = new List<string> { Read("Tela", SubVideo, VideoIdle), Read("Suspensão", SubSleep, StandbyIdle), Read("Disco", SubDisk, DiskIdle) };
            if (profileId is "gamer" or "gamer-ultra")
            {
                values.Add(ReadCpu("CPU mínimo", CpuMin));
                values.Add(ReadCpu("CPU máximo", CpuMax));
            }
            else
            {
                values.Add(ReadCpu("CPU mínimo herdado", CpuMin));
                values.Add(ReadCpu("CPU máximo herdado", CpuMax));
            }
            return string.Join(" • ", values);

            string ReadCpu(string label, string setting)
            {
                var value = Query(profile.Guid, SubCpu, setting);
                return value is null ? $"{label}: não foi possível confirmar" : $"{label}: AC {value.Value.Ac}%, DC {value.Value.Dc}%";
            }
        }
        catch (Exception ex) { return "Não foi possível confirmar os valores consultados: " + ex.Message; }
    }
    private static string FormatMinutes(uint value) => value == 0 ? "Nunca" : $"{value} min";

    public PowerManagerSnapshot ReadSnapshot()
    {
        var list = Execute("/list");
        var active = Execute("/getactivescheme");
        if (list.ExitCode != 0 || active.ExitCode != 0) return new(null, null, [], list.Error + active.Error);
        var schemes = ParseSchemes(list.Output);
        for (var index = 0; index < schemes.Count; index++)
            schemes[index] = (schemes[index].Guid, schemes[index].Name, _descriptionReader.ReadDescription(schemes[index].Guid));
        var activeGuid = ParseGuid(active.Output);
        var manifest = ReadManifest();
        var entries = Definitions.Select(def =>
        {
            manifest.Plans.TryGetValue(def.Id, out var guid);
            var scheme = schemes.FirstOrDefault(item => item.Guid == guid);
            var collides = schemes.Any(item => string.Equals(item.Name, def.Name, StringComparison.OrdinalIgnoreCase) && item.Guid != guid);
            // Ownership requires the persisted GUID and the expected scheme name together; a matching
            // name by itself is never sufficient, so third-party name collisions are left untouched.
            var owned = scheme is not null && guid is not null && scheme.Guid == guid
                && string.Equals(scheme.Name, def.Name, StringComparison.Ordinal)
                && scheme.Description.Contains(Marker(def.Id), StringComparison.Ordinal);
            var status = collides ? "Conflito de nome externo" : scheme is null ? (guid is null ? "Ainda não criado" : "Plano registrado ausente") : !owned ? "Propriedade não confirmada" : "Plano Lynext encontrado";
            return new PowerProfilePlan(def.Id, def.Name, def.Description, owned ? guid : null, owned, owned && guid == activeGuid, status);
        }).ToArray();
        return new(activeGuid, schemes.FirstOrDefault(s => s.Guid == activeGuid)?.Name, entries);
    }

    public PowerManagerOperation Activate(string profileId)
    {
        var definition = Definitions.FirstOrDefault(p => p.Id == profileId);
        if (definition == default) return new(false, "Perfil desconhecido.");
        var authorization = OptimizationAuthorizationPolicy.Authorize(
            [new("power-manager." + profileId, OptimizationTargetKind.PowerPlan, "managed-scheme:" + profileId)]);
        if (!authorization.Allowed) return new(false, "A política do Lynext negou a operação: " + authorization.Reason);
        try
        {
            if (_policyDetector.IsPowerManaged()) return new(false, "O Windows apresenta política de energia empresarial ou não foi possível consultá-la. Nenhum plano será criado ou alterado.", SafeSnapshot());
            var capabilities = Execute("/a");
            if (capabilities.ExitCode != 0) return new(false, "Não foi possível consultar os estados de energia suportados. Nenhuma alteração foi feita.");
            var before = ReadSnapshot();
            if (before.Error is not null) return new(false, "Não foi possível consultar os planos do Windows. Nenhuma alteração foi feita.");
            if (!before.Profiles.All(p => p.State == "Ainda não criado" || p.State == "Plano Lynext encontrado"))
                return new(false, "Os planos Lynext ainda não foram configurados ou há colisões/problemas de propriedade. Atualize o diagnóstico.", before);

            var manifest = ReadManifest();
            if (manifest.Plans.Count < Definitions.Length)
            {
                if (before.Profiles.Any(p => p.State is "Conflito de nome externo" or "Propriedade não confirmada" or "Plano registrado ausente"))
                    return new(false, "Há plano em conflito, ausente ou com propriedade não confirmada. Não será criada uma duplicata automática.", before);
                // Modern Standby supports Balanced-derived custom schemes; all plans use the built-in Balanced GUID.
                foreach (var profile in Definitions)
                {
                    if (manifest.Plans.ContainsKey(profile.Id)) continue;
                    var duplicated = Execute("/duplicatescheme", BalancedGuid);
                    if (duplicated.ExitCode != 0 || ParseGuid(duplicated.Output) is not { } guid)
                        return new(false, "O Windows não confirmou a criação de todos os planos. O Lynext interrompeu a operação; consulte powercfg e tente novamente após revisar os planos existentes.", ReadSnapshot());
                    var renamed = Execute("/changename", guid, profile.Name, Marker(profile.Id));
                    if (renamed.ExitCode != 0) return new(false, "Não foi possível identificar com segurança um plano duplicado. A operação foi interrompida.", ReadSnapshot());
                    manifest.Plans[profile.Id] = guid;
                    SaveManifest(manifest);
                }
            }

            var current = ReadSnapshot();
            if (current.Profiles.Any(p => p.State is "Conflito de nome externo" or "Propriedade não confirmada" or "Plano registrado ausente"))
                return new(false, "Há conflito, plano ausente ou propriedade não confirmada. Nenhum plano será sobrescrito.", current);
            if (!current.Profiles.All(p => p.Exists)) return new(false, "Os cinco planos gerenciados não estão disponíveis. Nenhuma duplicata adicional foi criada.", current);
            var active = current.ActiveGuid ?? throw new InvalidOperationException("GUID do plano ativo desconhecido.");
            if (!File.Exists(BackupPath)) WriteJson(BackupPath, new ActivationBackup(active, null, DateTimeOffset.UtcNow));
            var managedStatePath = Path.Combine(Root, "managed-settings.json");
            var managedState = ReadJson<ManagedSettings>(managedStatePath) ?? new ManagedSettings();
            foreach (var managedProfile in current.Profiles)
            {
                var guid = managedProfile.Guid!;
                if (!managedState.Profiles.TryGetValue(managedProfile.Id, out var applied) || applied.Guid != guid) continue;
                foreach (var setting in GetSettingsForProfile(managedProfile.Id))
                {
                    var actual = Query(guid, setting.SubgroupGuid, setting.SettingGuid);
                    if (actual is null) return new(false, $"Não foi possível confirmar {setting.Key} em {managedProfile.Name}; nenhum esquema será ativado.", ReadSnapshot());
                    if (!applied.Values.TryGetValue(setting.Key, out var lastApplied) || lastApplied != actual.Value)
                        return new(false, $"Conflito detectado: {setting.Key} em {managedProfile.Name} foi alterado fora do Lynext. Valores salvos foram preservados; revise o plano antes de tentar novamente.", ReadSnapshot());
                }
            }
            foreach (var managedProfile in current.Profiles)
            {
                var guid = managedProfile.Guid!;
                var expected = GetSettingsForProfile(managedProfile.Id);
                var previous = new Dictionary<string, PowerSettingValues>();
                foreach (var setting in expected)
                {
                    var prior = Query(guid, setting.SubgroupGuid, setting.SettingGuid);
                    if (prior is null) return new(false, $"Não foi possível ler {setting.Key} de {managedProfile.Name} antes da alteração; nenhum esquema será ativado.", ReadSnapshot());
                    previous[setting.Key] = prior.Value;
                }
                SaveSettingsBackup(managedProfile.Id, guid, previous);
                foreach (var setting in expected)
                {
                    try
                    {
                        Execute("/setacvalueindex", guid, setting.SubgroupGuid, setting.SettingGuid, setting.Ac.ToString());
                        Execute("/setdcvalueindex", guid, setting.SubgroupGuid, setting.SettingGuid, setting.Dc.ToString());
                    }
                    catch (Exception ex)
                    {
                        TryRestoreSetting(guid, setting, previous[setting.Key]);
                        return new(false, $"Falha parcial ao configurar {managedProfile.Name} ({setting.Key}): {ex.Message} O plano não será ativado.", ReadSnapshot());
                    }
                    var verified = Query(guid, setting.SubgroupGuid, setting.SettingGuid);
                    if (verified is null || verified.Value.Ac != setting.Ac || verified.Value.Dc != setting.Dc)
                    {
                        TryRestoreSetting(guid, setting, previous[setting.Key]);
                        return new(false, $"A consulta posterior não confirmou AC e DC para {managedProfile.Name} ({setting.Key}); o plano não será ativado.", ReadSnapshot());
                    }
                }
                managedState.Profiles[managedProfile.Id] = new ManagedPlanSettings(guid,
                    expected.ToDictionary(setting => setting.Key, setting => new PowerSettingValues(setting.Ac, setting.Dc), StringComparer.Ordinal));
                WriteJson(managedStatePath, managedState);
            }
            var guidTarget = current.Profiles.Single(p => p.Id == profileId).Guid!;
            var beforeActivation = ReadSnapshot();
            if (beforeActivation.ActiveGuid != active)
                return new(false, "O plano ativo mudou durante a configuração. Conflito detectado; o Lynext não substituirá essa escolha.", beforeActivation);
            var activated = Execute("/setactive", guidTarget);
            if (activated.ExitCode != 0) return new(false, "O Windows não aceitou ativar o plano. O perfil não foi marcado como ativo.", ReadSnapshot());
            var after = ReadSnapshot();
            if (after.ActiveGuid != guidTarget) return new(false, "O plano ativo consultado não corresponde ao solicitado. A ativação não foi confirmada.", after);
            var backup = ReadJson<ActivationBackup>(BackupPath) ?? new ActivationBackup(active, null, DateTimeOffset.UtcNow);
            WriteJson(BackupPath, backup with { LynextGuid = guidTarget, UpdatedAt = DateTimeOffset.UtcNow });
            WriteHistory("Ativar " + definition.Name, true, $"GUID {guidTarget} ativado e valores verificados; plano anterior {active} preservado para restauração.");
            return new(true, $"{definition.Name} configurado e ativado; valores confirmados por consulta do Windows. CPU: {(definition.CpuMax ? "100% mínimo e máximo AC/DC" : "herdada do Balanced") }.", after);
        }
        catch (Exception ex) { return new(false, "Falha ao gerenciar o plano: " + ex.Message, SafeSnapshot()); }
    }

    public PowerManagerOperation RestorePrevious()
    {
        try
        {
            var backup = ReadJson<ActivationBackup>(BackupPath);
            if (backup is null || string.IsNullOrWhiteSpace(backup.LynextGuid)) return new(false, "Não há ativação Lynext registrada para restaurar.", ReadSnapshot());
            var current = ReadSnapshot();
            if (current.ActiveGuid != backup.LynextGuid) return new(false, "O plano ativo mudou desde a ativação do Lynext. Conflito detectado; backup preservado e nenhuma alteração feita.", current);
            if (!current.ActiveGuid!.Equals(backup.LynextGuid, StringComparison.OrdinalIgnoreCase)) return new(false, "Plano ativo divergente; backup preservado.", current);
            var restore = Execute("/setactive", backup.OriginalGuid);
            if (restore.ExitCode != 0) return new(false, "Não foi possível voltar ao plano anterior. O backup foi preservado.", ReadSnapshot());
            var after = ReadSnapshot();
            if (after.ActiveGuid != backup.OriginalGuid) return new(false, "A consulta não confirmou o plano anterior. O backup foi preservado.", after);
            File.Delete(BackupPath);
            WriteHistory("Voltar ao plano anterior", true, $"Plano anterior {backup.OriginalGuid} restaurado; os planos Lynext foram preservados.");
            return new(true, "Plano anterior restaurado e confirmado. Os planos Lynext foram preservados.", after);
        }
        catch (Exception ex) { return new(false, "Restauração não confirmada: " + ex.Message, SafeSnapshot()); }
    }

    public static IReadOnlyList<PowerProfileSettingTarget> GetSettingsForProfile(string profileId)
    {
        var definition = Definitions.FirstOrDefault(p => p.Id == profileId);
        if (definition == default) return [];
        var settings = new List<PowerProfileSettingTarget>
        {
            new("screen", SubVideo, VideoIdle, 0, 60), new("sleep", SubSleep, StandbyIdle, 0, 60), new("disk", SubDisk, DiskIdle, 0, 0)
        };
        if (definition.CpuMax) { settings.Add(new("cpu-min", SubCpu, CpuMin, 100, 100)); settings.Add(new("cpu-max", SubCpu, CpuMax, 100, 100)); }
        return settings;
    }

    private PowerSettingValues? Query(string scheme, string subgroup, string setting)
    {
        var result = Execute("/query", scheme, subgroup, setting);
        if (result.ExitCode != 0) return null;
        // Match the AC/DC tags used by English and Portuguese powercfg output, then parse the numeric indexes.
        var acMatch = Regex.Match(result.Output, @"(?im)^.*(?:AC|CA|alternada|alternating).*?0x([0-9a-f]+)\s*$");
        var dcMatch = Regex.Match(result.Output, @"(?im)^.*(?:DC|CC|contínua|continua|direct current).*?0x([0-9a-f]+)\s*$");
        if (!acMatch.Success || !dcMatch.Success) return null;
        if (!uint.TryParse(acMatch.Groups[1].Value, System.Globalization.NumberStyles.HexNumber, null, out var ac) || !uint.TryParse(dcMatch.Groups[1].Value, System.Globalization.NumberStyles.HexNumber, null, out var dc)) return null;
        return new(ac, dc);
    }

    private PowerCommandResult Execute(params string[] args)
    {
        if (args.Length == 0 || !new[] { "/list", "/getactivescheme", "/a", "/duplicatescheme", "/changename", "/query", "/setacvalueindex", "/setdcvalueindex", "/setactive" }.Contains(args[0], StringComparer.OrdinalIgnoreCase))
            throw new InvalidOperationException("Operação powercfg não permitida pelo catálogo do Power Manager.");
        var result = _runner.Run(args);
        if (result.ExitCode != 0 && args[0] is not "/list" and not "/getactivescheme" and not "/a" and not "/query")
            throw new InvalidOperationException($"powercfg {args[0]} retornou código {result.ExitCode}: {result.Error} {result.Output}".Trim());
        return result;
    }
    private static string Marker(string id) => $"Lynext.PowerManager.Schema=1;Profile={id}";
    private static string? ParseGuid(string text) => Regex.Match(text, @"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b").Success ? Regex.Match(text, @"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b").Value.ToLowerInvariant() : null;
    private static List<(string Guid, string Name, string Description)> ParseSchemes(string text) => Regex.Matches(text, @"(?im)^\s*[^\r\n]*?\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b\s*\((.*?)\)(?:\s+\*)?\s*$").Cast<Match>().Select(m => (m.Groups[1].Value.ToLowerInvariant(), m.Groups[2].Value.Trim(), string.Empty)).ToList();
    private Manifest ReadManifest() => ReadJson<Manifest>(ManifestPath) ?? new Manifest();
    private void SaveManifest(Manifest value) => WriteJson(ManifestPath, value);
    private static T? ReadJson<T>(string path) => File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions) : default;
    private static void WriteJson<T>(string path, T value) { Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, JsonSerializer.Serialize(value, JsonOptions)); }
    private static void WriteHistory(string action, bool success, string details)
    {
        Directory.CreateDirectory(Root);
        File.AppendAllText(HistoryPath, JsonSerializer.Serialize(new { timestamp = DateTimeOffset.UtcNow, action, success, details }) + Environment.NewLine);
    }
    private void SaveSettingsBackup(string id, string guid, Dictionary<string, PowerSettingValues> values)
    {
        var backup = ReadJson<SettingsBackup>(Path.Combine(Root, "settings-backup.json")) ?? new SettingsBackup();
        if (!backup.Profiles.ContainsKey(id)) backup.Profiles[id] = new SavedSettings(guid, DateTimeOffset.UtcNow, values);
        WriteJson(Path.Combine(Root, "settings-backup.json"), backup);
    }
    private void TryRestoreSetting(string guid, PowerProfileSettingTarget setting, PowerSettingValues values)
    {
        try
        {
            Execute("/setacvalueindex", guid, setting.SubgroupGuid, setting.SettingGuid, values.Ac.ToString());
            Execute("/setdcvalueindex", guid, setting.SubgroupGuid, setting.SettingGuid, values.Dc.ToString());
        }
        catch { /* The original-value backup is retained for an explicit recovery attempt. */ }
    }
    private PowerManagerSnapshot SafeSnapshot() { try { return ReadSnapshot(); } catch { return new(null, null, [], "Estado desconhecido."); } }
    private sealed class Manifest { public Manifest() { } public Dictionary<string, string> Plans { get; set; } = new(StringComparer.Ordinal); }
    private sealed record ActivationBackup(string OriginalGuid, string? LynextGuid, DateTimeOffset UpdatedAt);
    private sealed class SettingsBackup { public SettingsBackup() { } public Dictionary<string, SavedSettings> Profiles { get; set; } = new(StringComparer.Ordinal); }
    private sealed record SavedSettings(string Guid, DateTimeOffset CapturedAt, Dictionary<string, PowerSettingValues> Values);
    private sealed class ManagedSettings { public ManagedSettings() { } public Dictionary<string, ManagedPlanSettings> Profiles { get; set; } = new(StringComparer.Ordinal); }
    private sealed record ManagedPlanSettings(string Guid, Dictionary<string, PowerSettingValues> Values);
}

