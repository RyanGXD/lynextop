using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace Lynext;

public sealed record UpdateManifest(
    string InstallerPath,
    string ExpectedSha256,
    string TargetVersion,
    string InstallDirectory,
    string InstalledExecutablePath,
    string PreviousVersion,
    string PreviousExecutableSha256,
    int ParentProcessId,
    long ParentProcessStartTimeUtcTicks,
    string ReleaseUrl,
    DateTimeOffset PreparedAt);

public static class UpdateOrchestrator
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static async Task StartUpdateAsync(
        UpdateInfo update,
        IProgress<UpdateDownloadProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var verified = await UpdateService.DownloadAndVerifyInstallerAsync(update, progress, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();

        var currentExecutable = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(currentExecutable)
            || !string.Equals(Path.GetFileName(currentExecutable), "Lynext.exe", StringComparison.OrdinalIgnoreCase)
            || !File.Exists(currentExecutable))
            throw new InvalidOperationException("Não foi possível identificar a instalação atual do Lynext. Execute o programa instalado antes de atualizar.");

        var installDirectory = Path.GetFullPath(Path.GetDirectoryName(currentExecutable)!);
        var updatesDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Updates");
        Directory.CreateDirectory(updatesDirectory);

        var helperSource = Path.Combine(AppContext.BaseDirectory, "Lynext.Updater.exe");
        if (!File.Exists(helperSource))
            throw new FileNotFoundException(
                "Esta instalação ainda não contém o componente seguro de atualização. Instale manualmente uma versão recente uma única vez; as próximas atualizações poderão ser feitas pelo Lynext.",
                helperSource);

        var previousHash = await UpdateService.ComputeFileSha256Async(currentExecutable, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        File.Copy(helperSource, Path.Combine(updatesDirectory, "Lynext.Updater.exe"), overwrite: true);

        using var currentProcess = Process.GetCurrentProcess();
        var manifest = new UpdateManifest(
            verified.FilePath,
            verified.Sha256,
            update.Version,
            installDirectory,
            Path.GetFullPath(currentExecutable),
            UpdateService.InstalledVersion.ToString(3),
            previousHash,
            currentProcess.Id,
            currentProcess.StartTime.ToUniversalTime().Ticks,
            update.ReleaseUrl,
            DateTimeOffset.UtcNow);

        var manifestPath = Path.Combine(updatesDirectory, "manifest-" + Guid.NewGuid().ToString("N") + ".json");
        var temporaryManifestPath = manifestPath + ".tmp";
        try
        {
            var json = JsonSerializer.Serialize(manifest, JsonOptions);
            await File.WriteAllTextAsync(temporaryManifestPath, json, new UTF8Encoding(false), cancellationToken);
            File.Move(temporaryManifestPath, manifestPath, overwrite: false);
            cancellationToken.ThrowIfCancellationRequested();

            var startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(updatesDirectory, "Lynext.Updater.exe"),
                WorkingDirectory = updatesDirectory,
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            startInfo.ArgumentList.Add("--apply-update");
            startInfo.ArgumentList.Add(manifestPath);

            using var helperProcess = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Não foi possível iniciar o componente auxiliar de atualização.");

            WriteUpdateLog("Componente auxiliar iniciado; o Lynext será fechado para permitir a substituição segura dos arquivos.");
        }
        catch
        {
            TryDeleteFile(temporaryManifestPath);
            TryDeleteFile(manifestPath);
            throw;
        }
    }

    public static void WriteUpdateLog(string message)
    {
        try
        {
            var logDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Logs");
            Directory.CreateDirectory(logDirectory);
            var entry = new { Timestamp = DateTimeOffset.UtcNow, Event = "Update", Message = message };
            File.AppendAllText(
                Path.Combine(logDirectory, "update-history.jsonl"),
                JsonSerializer.Serialize(entry) + Environment.NewLine,
                new UTF8Encoding(false));
        }
        catch
        {
            // Logging should not crash the update path.
        }
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }
}