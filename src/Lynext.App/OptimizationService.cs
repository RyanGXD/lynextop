using System.IO;
using Microsoft.Win32;
using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Lynext;

public sealed record RestorePointAttempt(bool Success, string Description, string Error, int? SequenceNumber);

public static class OptimizationService
{
    private const string GameBarPath = @"Software\Microsoft\GameBar";
    private static readonly string DataDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext");
    private static readonly string ProfileDirectory = Path.Combine(DataDirectory, "Profiles", "GamerUltra");
    private static readonly string BackupPath = Path.Combine(ProfileDirectory, "backup.json");
    private static readonly string HistoryPath = Path.Combine(DataDirectory, "Logs", "optimization-history.jsonl");
    private static readonly string PowerBackupPath = Path.Combine(ProfileDirectory, "power-backup.json");
    private static readonly string ActiveProfilePath = Path.Combine(ProfileDirectory, "active-profile.json");
    private const string HighPerformanceSchemeGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    private sealed record RegistryValueBackup(string Name, bool Exists, int? DwordValue);
    private sealed record GamerUltraBackup(DateTimeOffset CreatedAt, bool GameBarKeyExisted, List<RegistryValueBackup> Values);
    private sealed record PowerSchemeBackup(DateTimeOffset CreatedAt, string OriginalGuid, string AppliedGuid);
    private sealed record ActiveProfileState(string ProfileName, DateTimeOffset UpdatedAt, bool GameModeWasAlreadyEnabled, bool HighPerformancePlanApplied);
    private sealed record HistoryEntry(DateTimeOffset Timestamp, string Action, bool Success, string Details);
    private sealed record RestorePointPayload(bool Success, string Description, string Error, int? SequenceNumber);

    private static readonly string[] GameModeValues =
    [
        "AutoGameModeEnabled"
    ];

    public static bool CanRestoreDefaults
    {
        get
        {
            try { return File.Exists(BackupPath) || File.Exists(PowerBackupPath) || File.Exists(ActiveProfilePath); }
            catch { return false; }
        }
    }

    public static string? ActiveProfileName
    {
        get
        {
            try { return LoadProfileState()?.ProfileName; }
            catch { return null; }
        }
    }

    public static bool IsGamerApplied =>
        string.Equals(ActiveProfileName, "Gamer", StringComparison.OrdinalIgnoreCase)
        && SafeReadGameMode() == 1;

    public static bool IsGamerUltraApplied =>
        (string.Equals(ActiveProfileName, "Gamer Ultra", StringComparison.OrdinalIgnoreCase)
            || (ActiveProfileName is null && File.Exists(BackupPath)))
        && SafeReadGameMode() == 1;

    public static string GetStatusSummary()
    {
        try
        {
            var gameMode = ReadDword(GameModeValues[0]);
            var activeProfile = LoadProfileState();
            if (activeProfile is not null)
            {
                if (gameMode != 1)
                    return $"O perfil {activeProfile.ProfileName} está registrado, mas o Modo de Jogo não está confirmado como ativo. Revise o estado antes de aplicar novamente.";
                var powerText = activeProfile.HighPerformancePlanApplied
                    ? " O plano Alto desempenho também foi solicitado e verificado."
                    : " Nenhuma alteração no plano de energia é atribuída a este perfil.";
                return $"Perfil {activeProfile.ProfileName} ativo. O Modo de Jogo está habilitado.{powerText} O backup e o histórico permanecem salvos.";
            }
            if (File.Exists(PowerBackupPath))
                return "Há um backup de energia do Lynext aguardando restauração ou reconciliação. O aplicativo não deve sobrescrever uma mudança externa sem detectar o conflito.";
            if (File.Exists(BackupPath) && gameMode == 1)
                return "Existe um backup legado do Gamer Ultra e o Modo de Jogo está habilitado. A reversão continua disponível.";
            if (gameMode == 1)
                return "O Modo de Jogo já está habilitado no Windows; ainda não há um perfil gerenciado ativo pelo Lynext.";
            return "Nenhum perfil Gamer está ativo pelo Lynext. A análise não modifica configurações.";
        }
        catch (Exception ex)
        {
            return "Não foi possível ler o estado dos perfis: " + ex.Message;
        }
    }

    private static int? SafeReadGameMode()
    {
        try { return ReadDword(GameModeValues[0]); }
        catch { return null; }
    }

        public static async Task<RestorePointAttempt> TryCreateRestorePointAsync()
    {
        return await Task.Run(CreateRestorePointElevated);
    }

    public static string ApplyGamer() => ApplyProfile("Gamer", useHighPerformancePowerPlan: false);

    public static string ApplyGamerUltra() => ApplyGamerUltra(useHighPerformancePowerPlan: false);

    public static string ApplyGamerUltra(bool useHighPerformancePowerPlan) =>
        ApplyProfile("Gamer Ultra", useHighPerformancePowerPlan);

    private static string ApplyProfile(string profileName, bool useHighPerformancePowerPlan)
    {
        Directory.CreateDirectory(ProfileDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(HistoryPath)!);

        var originalGameMode = ReadDword(GameModeValues[0]);
        var gameModeAlreadyEnabled = originalGameMode == 1;
        var createdRegistryBackupForThisAttempt = false;

        if (!gameModeAlreadyEnabled && !File.Exists(BackupPath))
        {
            SaveBackup(CaptureBackup());
            createdRegistryBackupForThisAttempt = true;
        }

        var gameModeChanged = false;
        try
        {
            if (!gameModeAlreadyEnabled)
            {
                using var key = Registry.CurrentUser.CreateSubKey(GameBarPath, writable: true)
                    ?? throw new InvalidOperationException("Não foi possível abrir a chave do Modo de Jogo do usuário atual.");
                key.SetValue(GameModeValues[0], 1, RegistryValueKind.DWord);
                if (ReadDword(GameModeValues[0]) != 1)
                    throw new InvalidOperationException("O Modo de Jogo foi gravado, mas a leitura posterior não confirmou o valor esperado.");
                gameModeChanged = true;
            }

            var powerNote = ReconcilePowerPlan(useHighPerformancePowerPlan);
            var profileState = new ActiveProfileState(
                profileName,
                DateTimeOffset.Now,
                gameModeAlreadyEnabled,
                useHighPerformancePowerPlan && powerNote.Contains("Plano Alto desempenho ativado e verificado", StringComparison.OrdinalIgnoreCase));
            SaveProfileState(profileState);

            var status = gameModeAlreadyEnabled
                ? "O Modo de Jogo já estava habilitado; o Lynext preservou esse estado sem atribuir a alteração a si mesmo."
                : "Modo de Jogo habilitado e confirmado por leitura posterior.";
            var message = $"{profileName} registrado. {status} {powerNote} Xbox, Game Pass, Minecraft, Game Bar/Game DVR, segurança, serviços e Windows Update não foram alterados. Nenhum ganho de FPS é presumido.";
            WriteHistory("Ativar " + profileName, true, message);
            return message;
        }
        catch (Exception ex)
        {
            var rollbackNotes = new List<string>();
            if (gameModeChanged && File.Exists(BackupPath))
            {
                try
                {
                    RestoreBackupValues(LoadBackup());
                    VerifyBackupRestored(LoadBackup());
                    if (createdRegistryBackupForThisAttempt)
                        File.Delete(BackupPath);
                    rollbackNotes.Add("O valor do Modo de Jogo foi restaurado após a falha.");
                }
                catch (Exception rollbackEx)
                {
                    rollbackNotes.Add("A reversão do Modo de Jogo também falhou; preserve o backup em " + BackupPath + ". " + rollbackEx.Message);
                }
            }

            try
            {
                if (File.Exists(PowerBackupPath))
                    RestoreManagedPowerScheme(LoadPowerBackup());
            }
            catch (Exception rollbackPowerEx)
            {
                rollbackNotes.Add("A reversão do plano de energia não pôde ser confirmada; preserve o backup em " + PowerBackupPath + ". " + rollbackPowerEx.Message);
            }

            var details = ex.Message + (rollbackNotes.Count > 0 ? " " + string.Join(" ", rollbackNotes) : "");
            WriteHistory("Ativar " + profileName, false, details);
            throw new InvalidOperationException($"Falha ao ativar {profileName}. {details}", ex);
        }
    }

    public static string RestoreDefaults()
    {
        var hasRegistryBackup = File.Exists(BackupPath);
        var hasPowerBackup = File.Exists(PowerBackupPath);
        if (!hasRegistryBackup && !hasPowerBackup && !File.Exists(ActiveProfilePath))
            throw new InvalidOperationException("Não há ajustes gerenciados pelo Lynext para restaurar.");

        // Validate conflicts before changing either setting. Never overwrite a manual change silently.
        GamerUltraBackup? registryBackup = hasRegistryBackup ? LoadBackup() : null;
        PowerSchemeBackup? powerBackup = hasPowerBackup ? LoadPowerBackup() : null;
        if (registryBackup is not null)
            EnsureRegistryStateIsRestorable(registryBackup);
        if (powerBackup is not null)
            EnsurePowerPlanStateIsRestorable(powerBackup);

        if (registryBackup is not null)
        {
            RestoreBackupValues(registryBackup);
            VerifyBackupRestored(registryBackup);
        }

        if (powerBackup is not null)
        {
            RestoreManagedPowerScheme(powerBackup);
            // A method verifies the active GUID after switching or confirming the original state.
        }

        // Backups are deleted only after all managed settings have been read back and verified.
        if (hasRegistryBackup)
            File.Delete(BackupPath);
        if (hasPowerBackup)
            File.Delete(PowerBackupPath);
        TryDeleteFile(ActiveProfilePath);

        const string message = "Os ajustes gerenciados pelo Lynext foram restaurados e verificados. Configurações que já estavam ativas antes da aplicação foram preservadas; Xbox, Game Pass, Minecraft, Game Bar/Game DVR, segurança, serviços e Windows Update não foram alterados.";
        WriteHistory("Voltar ao padrão", true, message);
        return message;
    }

        public static string GetHistory()
    {
        if (!File.Exists(HistoryPath))
            return "Ainda não há alterações do Lynext registradas.";

        try
        {
            var records = File.ReadAllLines(HistoryPath)
                .Where(line => !string.IsNullOrWhiteSpace(line))
                .Reverse()
                .Take(20)
                .Select(line =>
                {
                    try { return JsonSerializer.Deserialize<HistoryEntry>(line, JsonOptions); }
                    catch { return null; }
                })
                .Where(record => record is not null)
                .Select(record =>
                    $"{record!.Timestamp.ToLocalTime():dd/MM/yyyy HH:mm:ss} | {(record.Success ? "OK" : "FALHA")} | {record.Action}{Environment.NewLine}{record.Details}")
                .ToArray();

            return records.Length == 0
                ? "O arquivo de histórico existe, mas não há entradas válidas."
                : string.Join(Environment.NewLine + Environment.NewLine, records);
        }
        catch (Exception ex)
        {
            return "Não foi possível ler o histórico: " + ex.Message;
        }
    }

    private static ActiveProfileState? LoadProfileState()
    {
        if (!File.Exists(ActiveProfilePath))
            return null;
        var content = File.ReadAllText(ActiveProfilePath, Encoding.UTF8);
        return JsonSerializer.Deserialize<ActiveProfileState>(content, JsonOptions)
            ?? throw new InvalidDataException("O estado persistente do perfil está vazio ou inválido.");
    }

    private static void SaveProfileState(ActiveProfileState state)
    {
        var temporaryPath = ActiveProfilePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state, JsonOptions), new UTF8Encoding(false));
        File.Move(temporaryPath, ActiveProfilePath, overwrite: true);
    }

    private static string ReconcilePowerPlan(bool useHighPerformancePowerPlan)
    {
        if (!useHighPerformancePowerPlan)
        {
            if (!File.Exists(PowerBackupPath))
                return "O plano de energia permaneceu inalterado.";
            var existingBackup = LoadPowerBackup();
            EnsurePowerPlanStateIsRestorable(existingBackup);
            RestoreManagedPowerScheme(existingBackup);
            return "O plano de energia original foi restaurado; o backup permanece guardado para a restauração final.";
        }

        var schemes = RunPowerCfg("/list");
        if (!schemes.Contains(HighPerformanceSchemeGuid, StringComparison.OrdinalIgnoreCase))
        {
            if (File.Exists(PowerBackupPath))
            {
                var oldBackup = LoadPowerBackup();
                RestoreManagedPowerScheme(oldBackup);
            }
            return "O plano Alto desempenho não está listado neste computador. Nenhuma alteração de energia foi feita.";
        }

        var current = GetActivePowerSchemeGuid();
        if (string.Equals(current, HighPerformanceSchemeGuid, StringComparison.OrdinalIgnoreCase))
            return "O plano Alto desempenho já estava ativo; nenhuma mudança de plano foi necessária.";

        PowerSchemeBackup backup;
        if (File.Exists(PowerBackupPath))
        {
            backup = LoadPowerBackup();
            if (!string.Equals(backup.AppliedGuid, HighPerformanceSchemeGuid, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("O backup de energia pertence a outro plano gerenciado; é necessária uma revisão manual antes de trocar novamente.");
            if (!string.Equals(current, backup.OriginalGuid, StringComparison.OrdinalIgnoreCase)
                && !string.Equals(current, backup.AppliedGuid, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("O plano de energia foi alterado externamente após a otimização. O Lynext não vai sobrescrever essa mudança silenciosamente.");
        }
        else
        {
            backup = new PowerSchemeBackup(DateTimeOffset.Now, current, HighPerformanceSchemeGuid);
            SavePowerBackup(backup);
        }

        RunPowerCfg("/setactive " + HighPerformanceSchemeGuid);
        var after = GetActivePowerSchemeGuid();
        if (!string.Equals(after, HighPerformanceSchemeGuid, StringComparison.OrdinalIgnoreCase))
        {
            try { RunPowerCfg("/setactive " + backup.OriginalGuid); }
            catch { /* Keep the verified backup for manual recovery. */ }
            throw new InvalidOperationException("O comando de energia terminou, mas a leitura posterior não confirmou o plano Alto desempenho.");
        }

        return "Plano Alto desempenho ativado e verificado. Ele pode aumentar consumo, temperatura e ruído; não garante FPS maior.";
    }

    private static void SavePowerBackup(PowerSchemeBackup backup)
    {
        var temporaryPath = PowerBackupPath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(backup, JsonOptions), new UTF8Encoding(false));
        File.Move(temporaryPath, PowerBackupPath, overwrite: true);
    }

    private static PowerSchemeBackup LoadPowerBackup()
    {
        var content = File.ReadAllText(PowerBackupPath, Encoding.UTF8);
        var backup = JsonSerializer.Deserialize<PowerSchemeBackup>(content, JsonOptions)
            ?? throw new InvalidDataException("O backup do plano de energia está vazio ou inválido.");
        if (!Guid.TryParse(backup.OriginalGuid, out _) || !Guid.TryParse(backup.AppliedGuid, out _))
            throw new InvalidDataException("O backup do plano de energia contém um GUID inválido.");
        return backup;
    }

    private static void RestoreManagedPowerScheme(PowerSchemeBackup backup)
    {
        var current = GetActivePowerSchemeGuid();
        if (string.Equals(current, backup.OriginalGuid, StringComparison.OrdinalIgnoreCase))
            return;
        if (!string.Equals(current, backup.AppliedGuid, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("O usuário ou outro programa mudou o plano de energia desde a aplicação. O Lynext preservou essa escolha; revise manualmente antes de restaurar.");
        RunPowerCfg("/setactive " + backup.OriginalGuid);
        var after = GetActivePowerSchemeGuid();
        if (!string.Equals(after, backup.OriginalGuid, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("A reversão do plano de energia foi solicitada, mas o plano original não foi confirmado.");
    }

    private static void EnsurePowerPlanStateIsRestorable(PowerSchemeBackup backup)
    {
        var current = GetActivePowerSchemeGuid();
        if (string.Equals(current, backup.OriginalGuid, StringComparison.OrdinalIgnoreCase)
            || string.Equals(current, backup.AppliedGuid, StringComparison.OrdinalIgnoreCase))
            return;
        throw new InvalidOperationException("O plano de energia atual difere tanto do original quanto do plano aplicado pelo Lynext. Para evitar sobrescrever uma mudança externa, a restauração foi interrompida.");
    }

    private static string GetActivePowerSchemeGuid()
    {
        var output = RunPowerCfg("/getactivescheme");
        var match = Regex.Match(output, @"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}");
        if (!match.Success || !Guid.TryParse(match.Value, out var guid))
            throw new InvalidOperationException("Não foi possível identificar o GUID do plano de energia ativo.");
        return guid.ToString("D");
    }

    private static string RunPowerCfg(string arguments)
    {
        var executable = Path.Combine(Environment.SystemDirectory, "powercfg.exe");
        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            Arguments = arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Não foi possível iniciar powercfg.exe.");
        var standardOutputTask = process.StandardOutput.ReadToEndAsync();
        var standardErrorTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit((int)TimeSpan.FromSeconds(15).TotalMilliseconds))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw new TimeoutException("powercfg.exe excedeu o limite de 15 segundos.");
        }

        Task.WaitAll(standardOutputTask, standardErrorTask);
        var output = standardOutputTask.Result + Environment.NewLine + standardErrorTask.Result;
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"powercfg.exe falhou (código {process.ExitCode}): {output.Trim()}");
        return output;
    }

    private static void EnsureRegistryStateIsRestorable(GamerUltraBackup backup)
    {
        using var key = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
        var hasValue = key is not null && key.GetValueNames().Contains(GameModeValues[0], StringComparer.OrdinalIgnoreCase);
        var isAppliedValue = hasValue && key!.GetValueKind(GameModeValues[0]) == RegistryValueKind.DWord
            && Convert.ToInt32(key.GetValue(GameModeValues[0], 0, RegistryValueOptions.DoNotExpandEnvironmentNames)) == 1;
        var original = backup.Values.FirstOrDefault(v => string.Equals(v.Name, GameModeValues[0], StringComparison.OrdinalIgnoreCase));
        var matchesOriginal = original is not null && original.Exists == hasValue
            && (!hasValue || (key!.GetValueKind(GameModeValues[0]) == RegistryValueKind.DWord
                && original.DwordValue == Convert.ToInt32(key.GetValue(GameModeValues[0], 0, RegistryValueOptions.DoNotExpandEnvironmentNames))));
        if (!isAppliedValue && !matchesOriginal)
            throw new InvalidOperationException("O valor do Modo de Jogo foi alterado externamente depois da ativação. O Lynext não vai sobrescrever a alteração silenciosamente.");
    }

    private static void VerifyBackupRestored(GamerUltraBackup backup)
    {
        using var key = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
        foreach (var value in backup.Values)
        {
            var exists = key is not null && key.GetValueNames().Contains(value.Name, StringComparer.OrdinalIgnoreCase);
            if (exists != value.Exists)
                throw new InvalidOperationException($"A verificação da reversão falhou para {value.Name}: a existência não corresponde ao backup.");
            if (value.Exists)
            {
                if (key!.GetValueKind(value.Name) != RegistryValueKind.DWord
                    || value.DwordValue != Convert.ToInt32(key.GetValue(value.Name, 0, RegistryValueOptions.DoNotExpandEnvironmentNames)))
                    throw new InvalidOperationException($"A verificação da reversão falhou para {value.Name}: o tipo ou valor não corresponde ao backup.");
            }
        }
        if (!backup.GameBarKeyExisted)
        {
            using var remainingKey = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
            if (remainingKey is not null && remainingKey.GetValueNames().Length == 0 && remainingKey.GetSubKeyNames().Length == 0)
                throw new InvalidOperationException("A chave vazia do Modo de Jogo deveria ter sido removida, mas ainda existe.");
        }
    }

    private static int? ReadDword(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
        if (key is null || !key.GetValueNames().Contains(name, StringComparer.OrdinalIgnoreCase))
            return null;
        if (key.GetValueKind(name) != RegistryValueKind.DWord)
            return null;
        return Convert.ToInt32(key.GetValue(name, 0, RegistryValueOptions.DoNotExpandEnvironmentNames));
    }

    private static GamerUltraBackup CaptureBackup()
    {
    {
        using var key = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
        var keyExisted = key is not null;
        var values = new List<RegistryValueBackup>();

        foreach (var name in GameModeValues)
        {
            var exists = key is not null && key.GetValueNames().Contains(name, StringComparer.OrdinalIgnoreCase);
            int? value = null;

            if (exists)
            {
                var kind = key!.GetValueKind(name);
                if (kind != RegistryValueKind.DWord)
                    throw new InvalidOperationException(
                        $"O valor {name} tem o tipo de registro {kind}, não DWORD. O Lynext não irá alterá-lo para evitar uma restauração imprecisa.");

                value = Convert.ToInt32(key!.GetValue(name, 0, RegistryValueOptions.DoNotExpandEnvironmentNames));
            }

            values.Add(new RegistryValueBackup(name, exists, value));
        }

        return new GamerUltraBackup(DateTimeOffset.Now, keyExisted, values);
    }

    private static void SaveBackup(GamerUltraBackup backup)
    {
        Directory.CreateDirectory(ProfileDirectory);
        var temporaryPath = BackupPath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(backup, JsonOptions), new UTF8Encoding(false));
        File.Move(temporaryPath, BackupPath, overwrite: true);
    }

    private static GamerUltraBackup LoadBackup()
    {
        var content = File.ReadAllText(BackupPath, Encoding.UTF8);
        return JsonSerializer.Deserialize<GamerUltraBackup>(content, JsonOptions)
            ?? throw new InvalidDataException("O backup do Gamer Ultra está vazio ou inválido; nenhuma restauração foi feita.");
    }

    private static void RestoreBackupValues(GamerUltraBackup backup)
    {
        var key = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: true);
        if (key is null && backup.Values.Any(value => value.Exists))
            key = Registry.CurrentUser.CreateSubKey(GameBarPath, writable: true);

        if (key is not null)
        {
            using (key)
            {
                foreach (var value in backup.Values)
                {
                    if (value.Exists && value.DwordValue.HasValue)
                        key.SetValue(value.Name, value.DwordValue.Value, RegistryValueKind.DWord);
                    else
                        key.DeleteValue(value.Name, throwOnMissingValue: false);
                }
            }
        }

        if (!backup.GameBarKeyExisted)
        {
            using var remainingKey = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
            if (remainingKey is not null && remainingKey.GetValueNames().Length == 0 && remainingKey.GetSubKeyNames().Length == 0)
                Registry.CurrentUser.DeleteSubKey(GameBarPath, throwOnMissingSubKey: false);
        }
    }

    private static int? ReadDword(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(GameBarPath, writable: false);
        if (key is null || !key.GetValueNames().Contains(name, StringComparer.OrdinalIgnoreCase))
            return null;
        if (key.GetValueKind(name) != RegistryValueKind.DWord)
            return null;
        return Convert.ToInt32(key.GetValue(name, 0, RegistryValueOptions.DoNotExpandEnvironmentNames));
    }

    private static RestorePointAttempt CreateRestorePointElevated()
    {
        var description = "Lynext Gamer Ultra " + DateTime.Now.ToString("yyyyMMdd-HHmmss");
        var workDirectory = Path.Combine(Path.GetTempPath(), "Lynext", "RestorePoints");
        var token = Guid.NewGuid().ToString("N");
        var scriptPath = Path.Combine(workDirectory, "create-" + token + ".ps1");
        var resultPath = Path.Combine(workDirectory, "result-" + token + ".json");

        try
        {
            Directory.CreateDirectory(workDirectory);
            var script = """
                $ErrorActionPreference = 'Stop'
                $ProgressPreference = 'SilentlyContinue'
                $description = '__DESCRIPTION__'
                $resultPath = '__RESULT_PATH__'
                try {
                    Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                    $points = @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq $description } | Sort-Object SequenceNumber -Descending | Select-Object -First 1)
                    if ($points.Count -lt 1) {
                        throw 'O comando terminou, mas o novo ponto não apareceu na consulta de verificação.'
                    }
                    $payload = [ordered]@{
                        Success = $true
                        Description = $description
                        Error = ''
                        SequenceNumber = [int]$points[0].SequenceNumber
                    }
                } catch {
                    $payload = [ordered]@{
                        Success = $false
                        Description = $description
                        Error = $_.Exception.Message
                        SequenceNumber = $null
                    }
                }
                [System.IO.File]::WriteAllText($resultPath, ($payload | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
                if (-not $payload.Success) { exit 1 }
                """.Replace("__DESCRIPTION__", EscapePowerShellString(description), StringComparison.Ordinal)
                    .Replace("__RESULT_PATH__", EscapePowerShellString(resultPath), StringComparison.Ordinal);

            File.WriteAllText(scriptPath, script, new UTF8Encoding(false));

            var powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");
            var startInfo = new ProcessStartInfo
            {
                FileName = powershellPath,
                Arguments = $"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{scriptPath}\"",
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            };

            using var process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Não foi possível iniciar o processo elevado para criar o ponto de restauração.");

            if (!process.WaitForExit((int)TimeSpan.FromMinutes(3).TotalMilliseconds))
            {
                process.Kill(entireProcessTree: true);
                var timeout = new RestorePointAttempt(false, description, "A tentativa de criar o ponto de restauração excedeu três minutos.", null);
                WriteHistory("Criar ponto de restauração", false, timeout.Error);
                return timeout;
            }

            if (!File.Exists(resultPath))
            {
                var noResult = new RestorePointAttempt(false, description,
                    $"O PowerShell encerrou sem um resultado verificável (código {process.ExitCode}).", null);
                WriteHistory("Criar ponto de restauração", false, noResult.Error);
                return noResult;
            }

            var payload = JsonSerializer.Deserialize<RestorePointPayload>(File.ReadAllText(resultPath, Encoding.UTF8), JsonOptions);
            if (payload is null)
            {
                var invalid = new RestorePointAttempt(false, description, "O resultado da verificação do ponto de restauração era inválido.", null);
                WriteHistory("Criar ponto de restauração", false, invalid.Error);
                return invalid;
            }

            var attempt = new RestorePointAttempt(payload.Success, payload.Description, payload.Error, payload.SequenceNumber);
            WriteHistory("Criar ponto de restauração", attempt.Success,
                attempt.Success ? $"Ponto confirmado: {attempt.Description}, sequência {attempt.SequenceNumber}."
                    : "Ponto não confirmado: " + attempt.Error);
            return attempt;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            var cancelled = new RestorePointAttempt(false, description, "A solicitação de elevação do Windows foi cancelada.", null);
            WriteHistory("Criar ponto de restauração", false, cancelled.Error);
            return cancelled;
        }
        catch (Exception ex)
        {
            var failed = new RestorePointAttempt(false, description, ex.Message, null);
            WriteHistory("Criar ponto de restauração", false, failed.Error);
            return failed;
        }
        finally
        {
            TryDeleteFile(scriptPath);
            TryDeleteFile(resultPath);
        }
    }

    private static string EscapePowerShellString(string value) => value.Replace("'", "''", StringComparison.Ordinal);

    private static void WriteHistory(string action, bool success, string details)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(HistoryPath)!);
            var entry = new HistoryEntry(DateTimeOffset.Now, action, success, details);
            File.AppendAllText(HistoryPath, JsonSerializer.Serialize(entry) + Environment.NewLine, new UTF8Encoding(false));
        }
        catch
        {
            // History failures must not undo or block an otherwise successful, reversible setting change.
        }
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }
}
