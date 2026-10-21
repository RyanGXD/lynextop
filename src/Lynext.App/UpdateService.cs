using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Reflection;

namespace Lynext;

public sealed record UpdateInfo(
    string Version,
    string TagName,
    string Notes,
    Uri InstallerUri,
    Uri? ChecksumUri,
    string? ExpectedSha256,
    long? AssetSize,
    DateTimeOffset? PublishedAt,
    string ReleaseUrl)
{
    public string InstallerFileName => $"Lynext-Setup-{Version}-x64.exe";
    public bool HasIntegritySource =>
        UpdateValidation.TryParseSha256Digest(ExpectedSha256, out _) || ChecksumUri is not null;
}

public sealed record UpdateDownloadProgress(long BytesReceived, long? TotalBytes)
{
    public double? Percent => TotalBytes is > 0
        ? Math.Clamp(BytesReceived * 100d / TotalBytes.Value, 0d, 100d)
        : null;
}

public sealed record VerifiedInstaller(string FilePath, string Sha256, long Size);

public static class UpdateService
{
    private const string Owner = "RyanGXD";
    private const string Repository = "lynextop";
    private const long MaxInstallerBytes = 1_000_000_000;
    private const int MaxChecksumBytes = 8 * 1024;
    private const int MaxRedirects = 5;
    private static readonly string CurrentVersion =
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.1.0";

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
        var handler = new HttpClientHandler { AllowAutoRedirect = false };
        var client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Lynext-Optimizer/" + CurrentVersion);
        return client;
    }

    public static Version InstalledVersion =>
        Version.TryParse(CurrentVersion, out var version) ? version : new Version(0, 1, 0);

    public static async Task<UpdateInfo?> CheckLatestAsync(CancellationToken cancellationToken = default)
    {
        var endpoint = new Uri($"https://api.github.com/repos/{Owner}/{Repository}/releases/latest");
        using var response = await ApiClient.GetAsync(endpoint, HttpCompletionOption.ResponseHeadersRead, cancellationToken);

        if (response.StatusCode == HttpStatusCode.NotFound)
            return null;

        if (response.StatusCode == HttpStatusCode.Forbidden
            && response.Headers.TryGetValues("X-RateLimit-Remaining", out var remainingValues)
            && remainingValues.FirstOrDefault() == "0")
            throw new HttpRequestException("O limite de consultas do GitHub foi atingido. Tente novamente mais tarde.", null, response.StatusCode);

        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var json = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = json.RootElement;

        if (!UpdateValidation.IsStableRelease(ReadBoolean(root, "draft"), ReadBoolean(root, "prerelease")))
            return null;

        var tag = ReadString(root, "tag_name");
        if (!UpdateValidation.TryParseVersionTag(tag, out var latestVersion))
            throw new InvalidDataException("A última Release do GitHub tem uma tag de versão inválida.");

        if (!UpdateValidation.IsNewerVersion(latestVersion, InstalledVersion))
            return null;

        if (!root.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
            throw new InvalidDataException("A Release mais recente não contém ativos publicados.");

        var versionText = latestVersion.ToString(3);
        var installerName = $"Lynext-Setup-{versionText}-x64.exe";
        var installerAsset = assets.EnumerateArray()
            .FirstOrDefault(asset => string.Equals(ReadString(asset, "name"), installerName, StringComparison.OrdinalIgnoreCase));

        if (installerAsset.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException($"A Release {tag} não contém o instalador compatível {installerName}.");

        var installerUrlText = ReadString(installerAsset, "browser_download_url");
        if (!Uri.TryCreate(installerUrlText, UriKind.Absolute, out var installerUri)
            || !UpdateValidation.IsAllowedDownloadUri(installerUri))
            throw new InvalidDataException("O endereço do instalador não pertence a um domínio HTTPS de download permitido do GitHub.");

        long? assetSize = null;
        if (installerAsset.TryGetProperty("size", out var sizeElement)
            && sizeElement.ValueKind == JsonValueKind.Number
            && sizeElement.TryGetInt64(out var size)
            && size > 0)
            assetSize = size;

        string? expectedHash = null;
        if (UpdateValidation.TryParseSha256Digest(ReadString(installerAsset, "digest"), out var parsedDigest))
            expectedHash = parsedDigest;

        Uri? checksumUri = null;
        var checksumName = installerName + ".sha256";
        var checksumAsset = assets.EnumerateArray()
            .FirstOrDefault(asset => string.Equals(ReadString(asset, "name"), checksumName, StringComparison.OrdinalIgnoreCase));
        if (checksumAsset.ValueKind == JsonValueKind.Object)
        {
            var checksumUrlText = ReadString(checksumAsset, "browser_download_url");
            if (!Uri.TryCreate(checksumUrlText, UriKind.Absolute, out var parsedChecksumUri)
                || !UpdateValidation.IsAllowedDownloadUri(parsedChecksumUri))
                throw new InvalidDataException("O endereço do checksum não pertence a um domínio HTTPS de download permitido do GitHub.");
            checksumUri = parsedChecksumUri;
        }

        var publishedAtText = ReadString(root, "published_at");
        DateTimeOffset? publishedAt = DateTimeOffset.TryParse(publishedAtText, out var parsedPublishedAt)
            ? parsedPublishedAt
            : null;

        var releaseUrlText = ReadString(root, "html_url");
        var releaseUrl = Uri.TryCreate(releaseUrlText, UriKind.Absolute, out var releaseUri)
            && releaseUri.Scheme == Uri.UriSchemeHttps
            && string.Equals(releaseUri.Host, "github.com", StringComparison.OrdinalIgnoreCase)
            ? releaseUri.AbsoluteUri
            : $"https://github.com/{Owner}/{Repository}/releases";

        return new UpdateInfo(
            versionText,
            tag!,
            ReadString(root, "body") ?? string.Empty,
            installerUri,
            checksumUri,
            expectedHash,
            assetSize,
            publishedAt,
            releaseUrl);
    }

    public static async Task<VerifiedInstaller> DownloadAndVerifyInstallerAsync(
        UpdateInfo update,
        IProgress<UpdateDownloadProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (!UpdateValidation.TryParseVersionTag(update.TagName, out var version)
            || !string.Equals(version.ToString(3), update.Version, StringComparison.Ordinal))
            throw new InvalidDataException("Os metadados da versão da atualização não são consistentes.");

        if (!UpdateValidation.IsExpectedInstallerName(update.InstallerFileName, version))
            throw new InvalidDataException("O nome do instalador não corresponde à versão esperada.");

        if (!UpdateValidation.IsAllowedDownloadUri(update.InstallerUri))
            throw new InvalidDataException("A origem do instalador não é permitida.");

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(15));
        var token = timeout.Token;

        string? expectedHash = null;
        if (UpdateValidation.TryParseSha256Digest(update.ExpectedSha256, out var parsedHash))
            expectedHash = parsedHash;

        if (update.ChecksumUri is not null)
        {
            var sidecarHash = await DownloadChecksumAsync(update.ChecksumUri, update.InstallerFileName, token);
            if (expectedHash is not null
                && !string.Equals(expectedHash, sidecarHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("O SHA-256 da API do GitHub diverge do checksum publicado junto com o instalador.");
            expectedHash = sidecarHash;
        }

        if (expectedHash is null)
            throw new InvalidDataException("Esta Release não fornece um SHA-256 confiável. O Lynext bloqueou a execução do instalador.");

        if (update.AssetSize is > MaxInstallerBytes)
            throw new InvalidDataException("O instalador excede o limite de tamanho permitido.");

        var updateRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Lynext", "Updates", "Downloads");
        Directory.CreateDirectory(updateRoot);
        var destination = Path.Combine(updateRoot, update.InstallerFileName);
        var temporary = destination + "." + Guid.NewGuid().ToString("N") + ".download";

        try
        {
            using var response = await SendAllowedGetAsync(update.InstallerUri, token);
            response.EnsureSuccessStatusCode();

            var contentLength = response.Content.Headers.ContentLength;
            if (contentLength is > MaxInstallerBytes)
                throw new InvalidDataException("O instalador excede o limite de tamanho permitido.");
            if (update.AssetSize.HasValue && contentLength.HasValue && update.AssetSize.Value != contentLength.Value)
                throw new InvalidDataException("O tamanho informado pelo GitHub não corresponde ao tamanho da resposta de download.");

            var expectedLength = update.AssetSize ?? contentLength;
            await using var input = await response.Content.ReadAsStreamAsync(token);
            await using var output = new FileStream(
                temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                81920, FileOptions.Asynchronous | FileOptions.SequentialScan);
            using var hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

            var buffer = new byte[81920];
            long received = 0;
            int read;
            while ((read = await input.ReadAsync(buffer.AsMemory(0, buffer.Length), token)) > 0)
            {
                received += read;
                if (received > MaxInstallerBytes)
                    throw new InvalidDataException("O instalador excedeu o limite de tamanho permitido.");
                hasher.AppendData(buffer, 0, read);
                await output.WriteAsync(buffer.AsMemory(0, read), token);
                progress?.Report(new UpdateDownloadProgress(received, expectedLength));
            }

            await output.FlushAsync(token);
            if (expectedLength.HasValue && received != expectedLength.Value)
                throw new InvalidDataException("O download terminou, mas o tamanho final diverge dos metadados.");

            var actualHash = Convert.ToHexString(hasher.GetHashAndReset()).ToLowerInvariant();
            if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(actualHash), Convert.FromHexString(expectedHash)))
                throw new InvalidDataException("O SHA-256 do instalador não corresponde ao checksum oficial. O arquivo não será executado.");

            File.Move(temporary, destination, overwrite: true);
            return new VerifiedInstaller(destination, actualHash, received);
        }
        finally
        {
            if (File.Exists(temporary))
                File.Delete(temporary);
        }
    }

    public static async Task<string> ComputeFileSha256Async(string path, CancellationToken cancellationToken = default)
    {
        await using var stream = new FileStream(
            path, FileMode.Open, FileAccess.Read, FileShare.Read,
            1024 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static async Task<string> DownloadChecksumAsync(
        Uri checksumUri,
        string installerFileName,
        CancellationToken cancellationToken)
    {
        if (!UpdateValidation.IsAllowedDownloadUri(checksumUri))
            throw new InvalidDataException("A origem do checksum não é permitida.");

        using var response = await SendAllowedGetAsync(checksumUri, cancellationToken);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is > MaxChecksumBytes)
            throw new InvalidDataException("O arquivo de checksum excede o limite permitido.");

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var memory = new MemoryStream();
        var buffer = new byte[1024];
        int read;
        while ((read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
        {
            if (memory.Length + read > MaxChecksumBytes)
                throw new InvalidDataException("O arquivo de checksum excede o limite permitido.");
            await memory.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }

        var text = new UTF8Encoding(false, true).GetString(memory.ToArray());
        if (!UpdateValidation.TryParseChecksumText(text, installerFileName, out var parsedHash))
            throw new InvalidDataException("O arquivo de checksum está vazio, malformado ou cita um nome de arquivo diferente.");
        return parsedHash;
    }

    private static async Task<HttpResponseMessage> SendAllowedGetAsync(Uri initialUri, CancellationToken cancellationToken)
    {
        if (!UpdateValidation.IsAllowedDownloadUri(initialUri))
            throw new InvalidDataException("O endereço de download não é permitido.");

        var currentUri = initialUri;
        for (var redirectCount = 0; redirectCount <= MaxRedirects; redirectCount++)
        {
            if (!UpdateValidation.IsAllowedDownloadUri(currentUri))
                throw new InvalidDataException("Um redirecionamento apontou para uma origem não permitida.");

            var request = new HttpRequestMessage(HttpMethod.Get, currentUri);
            HttpResponseMessage response;
            try
            {
                response = await DownloadClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            }
            catch
            {
                request.Dispose();
                throw;
            }

            if (!IsRedirect(response.StatusCode))
                return response;

            var location = response.Headers.Location;
            response.Dispose();
            request.Dispose();
            if (location is null)
                throw new InvalidDataException("O servidor retornou um redirecionamento sem destino.");
            if (redirectCount == MaxRedirects)
                throw new InvalidDataException("O servidor excedeu o limite de redirecionamentos permitido.");

            currentUri = location.IsAbsoluteUri ? location : new Uri(currentUri, location);
            if (!UpdateValidation.IsAllowedDownloadUri(currentUri))
                throw new InvalidDataException("O redirecionamento tenta sair dos domínios HTTPS permitidos do GitHub.");
        }

        throw new InvalidDataException("Não foi possível concluir o redirecionamento do download.");
    }

    private static bool IsRedirect(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.MovedPermanently
            or HttpStatusCode.Redirect
            or HttpStatusCode.SeeOther
            or HttpStatusCode.TemporaryRedirect
            or HttpStatusCode.PermanentRedirect;

    private static bool ReadBoolean(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.True;

    private static string? ReadString(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}