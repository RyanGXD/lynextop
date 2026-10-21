using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Lynext.Updater;

internal sealed record UpdateManifest(
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

internal static class Program
{
    private const string AppExecutableName = "Lynext.exe";
    private const string InstallerPrefix = "Lynext-Setup-";
    private const string InstallerSuffix = "-x64.exe";
    private const int ParentWaitSeconds = 45;
    private const int InstallerWaitMinutes = 20;
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    private static async Task<int> Main(string[] args)
    {
        UpdateManifest? manifest = null;
        var manifestValidated = false;
        var parentHasExited = false;
        string? manifestPath = null;
        try
        {
            if (args.Length != 2 || !string.Equals(args[0], "--apply-update", StringComparison.Ordinal))
                throw new InvalidDataException("Parâmetros inválidos para o componente auxiliar de atualização.");

            manifestPath = Path.GetFullPath(args[1]);
            var updatesRoot = GetUpdatesRoot();
            EnsureContainedPath(updatesRoot, manifestPath);
            if (!string.Equals(Path.GetExtension(manifestPath), ".json", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("O arquivo de preparação da atualização não é válido.");

            var json = await File.ReadAllTextAsync(manifestPath, Encoding.UTF8);
            manifest = JsonSerializer.Deserialize<UpdateManifest>(json, JsonOptions)
                ?? throw new InvalidDataException("O arquivo de preparação da atualização está vazio ou inválido.");

            ValidateManifest(manifest, updatesRoot);
            manifestValidated = true;
            await WaitForParentToExitAsync(manifest);
            parentHasExited = true;
            await VerifyInstallerAsync(manifest);

            // Do not pass /DIR from the writable manifest. Inno Setup's existing AppId resolves the installation,
            // and the user sees the normal installer UI and any UAC prompt.
            var setupInfo = new ProcessStartInfo
            {
                FileName = Path.GetFullPath(manifest.InstallerPath),
                WorkingDirectory = Path.GetFullPath(manifest.InstallDirectory),
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Normal
            };
            setupInfo.ArgumentList.Add("/LYNEXTUPDATE=1");

            Process? installerProcess;
            try
            {
                installerProcess = Process.Start(setupInfo);
            }
            catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
            {
                await RelaunchPreviousIfIntactAsync(manifest);
                Log("Instalação cancelada na solicitação de elevação do Windows.");
                Show("A atualização foi cancelada na solicitação de permissão do Windows. A versão anterior foi mantida.", "Lynext — Atualização cancelada", 0x30);
                return 2;
            }

            if (installerProcess is null)
                throw new InvalidOperationException("O Windows não conseguiu iniciar o instalador.");

            using (installerProcess)
            {
                var finished = await WaitForProcessAsync(installerProcess, TimeSpan.FromMinutes(InstallerWaitMinutes));
                if (!finished)
                {
                    Log("O instalador excedeu o limite de tempo de espera. Não é seguro reabrir o app enquanto o instalador pode estar executando.");
                    Show("A instalação ainda pode estar em andamento. O Lynext não será reaberto enquanto não for possível confirmar que o instalador terminou. Verifique a janela do instalador antes de tentar novamente.", "Lynext — Instalação ainda em andamento", 0x30);
                    return 1;
                }

                if (installerProcess.ExitCode != 0)
                {
                    Log($"O instalador terminou com código {installerProcess.ExitCode}.");
                    await RelaunchPreviousIfIntactAsync(manifest);
                    Show($"O instalador terminou com o código {installerProcess.ExitCode}. O Lynext só reabrirá a versão anterior se conseguir confirmar que o executável não foi alterado.", "Lynext — Falha na atualização", 0x10);
                    return installerProcess.ExitCode;
                }
            }

            var installedVersion = TryReadExecutableVersion(manifest.InstalledExecutablePath);
            if (installedVersion is null || !VersionsEqual(installedVersion, manifest.TargetVersion))
            {
                Log($"Instalador retornou sucesso, mas a versão encontrada não corresponde ao alvo. Esperada={manifest.TargetVersion}; encontrada={installedVersion ?? "indisponível"}.");
                await RelaunchPreviousIfIntactAsync(manifest);
                Show("O instalador terminou, mas não foi possível confirmar a versão esperada. A atualização não será marcada como concluída.", "Lynext — Verificação incompleta", 0x10);
                return 1;
            }

            Log($"Atualização concluída e verificada. Versão {installedVersion}.");
            TryDeleteFile(manifest.InstallerPath);
            if (manifestPath is not null)
                TryDeleteFile(manifestPath);

            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = Path.GetFullPath(manifest.InstalledExecutablePath),
                    WorkingDirectory = Path.GetFullPath(manifest.InstallDirectory),
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                Log("A atualização foi verificada, mas a reabertura falhou: " + ex.Message);
                Show("A atualização foi concluída, mas o Lynext não conseguiu reabrir automaticamente. Abra-o pelo atalho habitual.", "Lynext — Atualização concluída", 0x30);
                return 3;
            }

            return 0;
        }
        catch (Exception ex)
        {
            Log("Falha no atualizador: " + ex);
            if (manifestValidated && parentHasExited && manifest is not null)
            {
                try { await RelaunchPreviousIfIntactAsync(manifest); }
                catch (Exception relaunchEx) { Log("Falha ao reabrir a versão anterior: " + relaunchEx.Message); }
            }
            Show("Não foi possível concluir a atualização do Lynext. A instalação não será declarada como atualizada sem verificação.\n\nDetalhes: " + ex.Message,
                "Lynext — Falha na atualização", 0x10);
            return 1;
        }
    }

    private static string GetUpdatesRoot() => Path.GetFullPath(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Updates"));

    private static void ValidateManifest(UpdateManifest manifest, string updatesRoot)
    {
        if (!UpdateValidation.IsAllowedHash(manifest.ExpectedSha256)
            || !UpdateValidation.IsAllowedHash(manifest.PreviousExecutableSha256))
            throw new InvalidDataException("O manifesto contém um hash inválido.");

        if (!Version.TryParse(manifest.TargetVersion, out var targetVersion)
            || !Version.TryParse(manifest.PreviousVersion, out var previousVersion)
            || targetVersion <= previousVersion)
            throw new InvalidDataException("A versão de destino não é válida ou não é mais recente.");

        var installerPath = Path.GetFullPath(manifest.InstallerPath);
        EnsureContainedPath(updatesRoot, installerPath);
        if (!string.Equals(Path.GetFileName(installerPath), InstallerPrefix + targetVersion.ToString(3) + InstallerSuffix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("O instalador não corresponde à versão informada.");

        var installDirectory = Path.GetFullPath(manifest.InstallDirectory);
        var executablePath = Path.GetFullPath(manifest.InstalledExecutablePath);
        if (!string.Equals(Path.GetFileName(executablePath), AppExecutableName, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(Path.GetFullPath(Path.GetDirectoryName(executablePath)!), installDirectory, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("O caminho de instalação não corresponde ao executável do Lynext.");

        if (!File.Exists(executablePath))
            throw new FileNotFoundException("O executável instalado do Lynext não foi encontrado.", executablePath);

        if (!Uri.TryCreate(manifest.ReleaseUrl, UriKind.Absolute, out var releaseUri)
            || releaseUri.Scheme != Uri.UriSchemeHttps
            || !string.Equals(releaseUri.Host, "github.com", StringComparison.OrdinalIgnoreCase)
            || !releaseUri.AbsolutePath.StartsWith("/RyanGXD/lynextop/releases/", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("A URL da Release não é válida.");

        if (manifest.ParentProcessId <= 0 || manifest.ParentProcessStartTimeUtcTicks <= 0)
            throw new InvalidDataException("A referência do processo principal não é válida.");
    }

    private static async Task WaitForParentToExitAsync(UpdateManifest manifest)
    {
        var deadline = DateTime.UtcNow.AddSeconds(ParentWaitSeconds);
        while (DateTime.UtcNow < deadline)
        {
            if (!IsExpectedParentRunning(manifest))
                return;
            await Task.Delay(250);
        }

        throw new TimeoutException("O Lynext principal não fechou dentro do tempo esperado. O instalador não foi iniciado.");
    }

    private static bool IsExpectedParentRunning(UpdateManifest manifest)
    {
        try
        {
            using var process = Process.GetProcessById(manifest.ParentProcessId);
            var processPath = process.MainModule?.FileName;
            if (!string.Equals(Path.GetFullPath(processPath ?? string.Empty),
                    Path.GetFullPath(manifest.InstalledExecutablePath), StringComparison.OrdinalIgnoreCase))
                return false;

            var startTicks = process.StartTime.ToUniversalTime().Ticks;
            return Math.Abs(startTicks - manifest.ParentProcessStartTimeUtcTicks) <= TimeSpan.FromSeconds(2).Ticks;
        }
        catch
        {
            return false;
        }
    }

    private static async Task VerifyInstallerAsync(UpdateManifest manifest)
    {
        var actual = await HashFileAsync(manifest.InstallerPath);
        if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(actual), Convert.FromHexString(manifest.ExpectedSha256)))
            throw new InvalidDataException("O checksum do instalador mudou depois do download. A execução foi bloqueada.");

        var oldHash = await HashFileAsync(manifest.InstalledExecutablePath);
        if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(oldHash), Convert.FromHexString(manifest.PreviousExecutableSha256)))
            throw new InvalidDataException("A instalação existente mudou antes do início da atualização; o processo foi interrompido.");
    }

    private static async Task RelaunchPreviousIfIntactAsync(UpdateManifest manifest)
    {
        if (!File.Exists(manifest.InstalledExecutablePath))
        {
            Log("A versão anterior não pode ser reaberta: o executável não existe.");
            return;
        }

        var hash = await HashFileAsync(manifest.InstalledExecutablePath);
        if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(hash), Convert.FromHexString(manifest.PreviousExecutableSha256)))
        {
            Log("A versão anterior não foi reaberta porque o hash do executável mudou.");
            return;
        }

        var version = TryReadExecutableVersion(manifest.InstalledExecutablePath);
        if (version is null || !VersionsEqual(version, manifest.PreviousVersion))
        {
            Log("A versão anterior não foi reaberta porque a versão do executável não corresponde ao manifesto.");
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = Path.GetFullPath(manifest.InstalledExecutablePath),
            WorkingDirectory = Path.GetFullPath(manifest.InstallDirectory),
            UseShellExecute = true
        });
        Log("Versão anterior reaberta depois de confirmar hash e versão.");
    }

    private static string? TryReadExecutableVersion(string path)
    {
        try { return AssemblyName.GetAssemblyName(path).Version?.ToString(3); }
        catch (Exception ex)
        {
            Log("Não foi possível ler a versão do executável: " + ex.Message);
            return null;
        }
    }

    private static bool VersionsEqual(string left, string right) =>
        Version.TryParse(left, out var leftVersion)
        && Version.TryParse(right, out var rightVersion)
        && leftVersion.CompareTo(rightVersion) == 0;

    private static async Task<string> HashFileAsync(string path)
    {
        await using var stream = new FileStream(
            path, FileMode.Open, FileAccess.Read, FileShare.Read,
            1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        return Convert.ToHexString(await SHA256.HashDataAsync(stream)).ToLowerInvariant();
    }

    private static async Task<bool> WaitForProcessAsync(Process process, TimeSpan timeout)
    {
        try
        {
            using var timeoutSource = new CancellationTokenSource(timeout);
            await process.WaitForExitAsync(timeoutSource.Token);
            return true;
        }
        catch (OperationCanceledException) { return false; }
    }

    private static void EnsureContainedPath(string root, string path)
    {
        var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var fullPath = Path.GetFullPath(path);
        var relative = Path.GetRelativePath(fullRoot, fullPath);
        if (relative == "." || relative == ".."
            || relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal)
            || Path.IsPathRooted(relative))
            throw new InvalidDataException("Um caminho da atualização está fora do diretório permitido.");
    }

    private static void Log(string message)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Logs");
            Directory.CreateDirectory(directory);
            var entry = new { Timestamp = DateTimeOffset.UtcNow, Event = "Updater", Message = message };
            File.AppendAllText(
                Path.Combine(directory, "update-history.jsonl"),
                JsonSerializer.Serialize(entry) + Environment.NewLine,
                new UTF8Encoding(false));
        }
        catch { }
    }

    private static void Show(string text, string caption, uint type)
    {
        try { _ = MessageBox(IntPtr.Zero, text, caption, type | 0x00040000); }
        catch { }
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }
}

internal static class UpdateValidation
{
    private static readonly Regex HashPattern = new(@"^[a-fA-F0-9]{64}$", RegexOptions.CultureInvariant | RegexOptions.Compiled);
    public static bool IsAllowedHash(string? value) => !string.IsNullOrWhiteSpace(value) && HashPattern.IsMatch(value);
}