using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Reflection;

namespace Lynext;

public sealed record UpdateInfo(string Version, string TagName, string Notes, Uri InstallerUri, string ReleaseUrl);

public static class UpdateService
{
    private const string Owner = "RyanGXD";
    private const string Repository = "lynextop";
    private static readonly string CurrentVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.1.0";

    // Keep API checks short, but allow larger installer downloads on slower connections.
    private static readonly HttpClient ApiClient = CreateApiClient();
    private static readonly HttpClient DownloadClient = CreateDownloadClient();

    private static HttpClient CreateApiClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Lynext-Optimizer/" + CurrentVersion);
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        client.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28");
        return client;
    }

    private static HttpClient CreateDownloadClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Lynext-Optimizer/" + CurrentVersion);
        return client;
    }

    public static Version InstalledVersion => Version.TryParse(CurrentVersion, out var version) ? version : new Version(0, 1, 0);

    public static async Task<UpdateInfo?> CheckLatestAsync(CancellationToken cancellationToken = default)
    {
        var endpoint = new Uri($"https://api.github.com/repos/{Owner}/{Repository}/releases/latest");
        using var response = await ApiClient.GetAsync(endpoint, HttpCompletionOption.ResponseHeadersRead, cancellationToken);

        if (response.StatusCode == HttpStatusCode.NotFound)
            return null; // No stable release has been published yet.

        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var json = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = json.RootElement;

        var tag = root.TryGetProperty("tag_name", out var tagElement) ? tagElement.GetString() : null;
        var htmlUrl = root.TryGetProperty("html_url", out var urlElement) ? urlElement.GetString() : null;
        var notes = root.TryGetProperty("body", out var bodyElement) ? bodyElement.GetString() ?? "" : "";

        if (string.IsNullOrWhiteSpace(tag) || !TryParseVersion(tag, out var latestVersion))
            return null;

        if (latestVersion <= InstalledVersion)
            return null;

        if (!root.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
            return null;

        foreach (var asset in assets.EnumerateArray())
        {
            var name = asset.TryGetProperty("name", out var nameElement) ? nameElement.GetString() : null;
            var downloadUrl = asset.TryGetProperty("browser_download_url", out var downloadElement) ? downloadElement.GetString() : null;

            if (string.IsNullOrWhiteSpace(name) ||
                !name.StartsWith("Lynext-Setup-", StringComparison.OrdinalIgnoreCase) ||
                !name.EndsWith("-x64.exe", StringComparison.OrdinalIgnoreCase) ||
                !Uri.TryCreate(downloadUrl, UriKind.Absolute, out var uri) ||
                uri.Scheme != Uri.UriSchemeHttps ||
                (uri.Host != "github.com" && uri.Host != "release-assets.githubusercontent.com" && uri.Host != "objects.githubusercontent.com"))
                continue;

            return new UpdateInfo(latestVersion.ToString(), tag, notes, uri, htmlUrl ?? $"https://github.com/{Owner}/{Repository}/releases");
        }

        return null;
    }

    public static async Task<string> DownloadInstallerAsync(UpdateInfo update, IProgress<double>? progress = null, CancellationToken cancellationToken = default)
    {
        var directory = Path.Combine(Path.GetTempPath(), "Lynext", "Updates");
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, $"Lynext-Setup-{update.Version}-x64.exe");
        var temporary = destination + ".download";

        try
        {
            using var response = await DownloadClient.GetAsync(update.InstallerUri, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            response.EnsureSuccessStatusCode();

            var total = response.Content.Headers.ContentLength;
            const long maxInstallerBytes = 1_000_000_000;
            if (total is > maxInstallerBytes)
                throw new InvalidDataException("O instalador excede o limite de tamanho permitido.");

            await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using (var output = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true))
            {
                var buffer = new byte[81920];
                long received = 0;
                int read;
                while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
                {
                    received += read;
                    if (received > maxInstallerBytes)
                        throw new InvalidDataException("O instalador excedeu o limite de tamanho permitido.");
                    await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                    if (total is > 0)
                        progress?.Report(Math.Clamp((double)received / total.Value * 100d, 0d, 100d));
                }
                await output.FlushAsync(cancellationToken);
            }

            File.Move(temporary, destination, overwrite: true);
            return destination;
        }
        finally
        {
            // Never leave a partial executable behind if a download fails or is cancelled.
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    private static bool TryParseVersion(string tag, out Version version)
    {
        var normalized = tag.Trim();
        if (normalized.StartsWith("v", StringComparison.OrdinalIgnoreCase))
            normalized = normalized[1..];
        return Version.TryParse(normalized, out version!);
    }
}
