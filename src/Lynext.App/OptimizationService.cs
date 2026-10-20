using Microsoft.Win32;
using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;

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
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    private sealed record RegistryValueBackup(string Name, bool Exists, int? DwordValue);
    private sealed record GamerUltraBackup(DateTimeOffset CreatedAt, bool GameBarKeyExisted, List<RegistryValueBackup> Values);
    private sealed record HistoryEntry(DateTimeOffset Timestamp, string Action, bool Success, string Details);
    private sealed record RestorePointPayload(bool Success, string Description, string Error, int? SequenceNumber);

    private static readonly string[] GameModeValues =
    [
        "AutoGameModeEnabled",
        "AllowAutoGameMode"
    ];

    public static bool CanRestoreDefaults
    {
        get
        {
            try { return File.Exists(BackupPath); }
            catch { return false; }
        }
    }

    public static bool IsGamerUltraApplied
    {
        get
        {
            try
            {
                return CanRestoreDefaults
                    && ReadDword(GameModeValues[0]) == 1
                    && ReadDword(GameModeValues[1]) == 1;
            }
            catch { return false; }
        }
    }

    public static string GetStatusSummary()
    {
        try
        {
            var first = ReadDword(GameModeValues[0]);
            var second = ReadDword(GameModeValues[1]);
            if (IsGamerUltraApplied)
                return "Gamer Ultra está ativo. O backup original está salvo e pode ser restaurado pelo botão Voltar ao padrão.";
            if (CanRestoreDefaults)
                return "Existe um backup do Gamer Ultra, mas o estado atual do Modo de Jogo difere do momento da ativação. A reversão continua disponível.";
            if (first == 1 && second == 1)
                return "As opções do Modo de Jogo já parecem habilitadas no Windows; não existe backup do Lynext para essas opções.";
            return "Gamer Ultra ainda não foi aplicado. Nenhuma configuração foi alterada por esta análise.";
        }
        catch (Exception ex)
        {
            return "Não foi possível ler o estado do Modo de Jogo: " + ex.Message;
        }
    }

    public static async Task<RestorePointAttempt> TryCreateRestorePointAsync()
    {
        return await Task.Run(CreateRestorePointElevated);
    }

    public static string ApplyGamerUltra()
    {
        Directory.CreateDirectory(ProfileDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(HistoryPath)!);

        if (IsGamerUltraApplied)
        {
            const string alreadyApplied = "Gamer Ultra já está ativo. O backup original foi preservado.";
            WriteHistory("Ativar Gamer Ultra", true, alreadyApplied);
            return alreadyApplied;
        }

        if (!File.Exists(BackupPath))
            SaveBackup(CaptureBackup());

        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(GameBarPath, writable: true)
                ?? throw new InvalidOperationException("Não foi possível abrir a chave do Modo de Jogo do usuário atual.");
            key.SetValue(GameModeValues[0], 1, RegistryValueKind.DWord);
            key.SetValue(GameModeValues[1], 1, RegistryValueKind.DWord);
        }
        catch (Exception ex)
        {
            var rollbackMessage = "";
            try
            {
                RestoreBackupValues(LoadBackup());
                rollbackMessage = " Os valores anteriores foram restaurados.";
            }
            catch (Exception rollbackEx)
            {
                rollbackMessage = " Atenção: a reversão automática também falhou; preserve o backup em " + BackupPath
                    + ". Detalhes da reversão: " + rollbackEx.Message;
            }

            WriteHistory("Ativar Gamer Ultra", false, ex.Message + rollbackMessage);
            throw new InvalidOperationException("Falha ao alterar as opções do Modo de Jogo." + rollbackMessage, ex);
        }

        const string success = "Gamer Ultra ativado: as duas opções específicas de ativação automática do Modo de Jogo foram habilitadas. Os valores originais foram salvos para reversão.";
        WriteHistory("Ativar Gamer Ultra", true, success);
        return success;
    }

    public static string RestoreDefaults()
    {
        if (!File.Exists(BackupPath))
            throw new InvalidOperationException("Não há backup do Gamer Ultra para restaurar.");

        var backup = LoadBackup();
        RestoreBackupValues(backup);
        File.Delete(BackupPath);

        var message = "Valores originais do Modo de Jogo restaurados. Nenhum serviço ou recurso do Xbox, Firewall, Defender, Windows Update, energia, RAM ou SSD foi alterado por esta reversão.";
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

    private static GamerUltraBackup CaptureBackup()
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
