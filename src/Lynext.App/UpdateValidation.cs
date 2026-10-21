using System.Text.RegularExpressions;

namespace Lynext;

public static class UpdateValidation
{
    private static readonly Regex VersionTagPattern = new(
        @"^[vV]?(?<version>\d+\.\d+\.\d+(?:\.\d+)?)$",
        RegexOptions.CultureInvariant | RegexOptions.Compiled);

    private static readonly Regex Sha256Pattern = new(
        @"^[a-fA-F0-9]{64}$",
        RegexOptions.CultureInvariant | RegexOptions.Compiled);

    private static readonly Regex ChecksumLinePattern = new(
        @"^(?<hash>[a-fA-F0-9]{64})(?:\s+\*?(?<name>[^\s]+))?$",
        RegexOptions.CultureInvariant | RegexOptions.Compiled);

    private static readonly HashSet<string> AllowedDownloadHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "github.com",
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com"
    };

    public static bool TryParseVersionTag(string? tag, out Version version)
    {
        version = new Version(0, 0, 0);
        if (string.IsNullOrWhiteSpace(tag))
            return false;

        var match = VersionTagPattern.Match(tag.Trim());
        return match.Success && Version.TryParse(match.Groups["version"].Value, out version!);
    }

    public static bool IsStableRelease(bool draft, bool prerelease) => !draft && !prerelease;

    public static bool IsNewerVersion(Version candidate, Version installed) => candidate > installed;

    public static bool IsExpectedInstallerName(string? assetName, Version version) =>
        string.Equals(assetName, $"Lynext-Setup-{version.ToString(3)}-x64.exe", StringComparison.OrdinalIgnoreCase);

    public static bool IsAllowedDownloadUri(Uri? uri) =>
        uri is not null
        && uri.IsAbsoluteUri
        && string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
        && uri.IsDefaultPort
        && string.IsNullOrEmpty(uri.UserInfo)
        && AllowedDownloadHosts.Contains(uri.IdnHost);

    public static bool TryParseSha256Digest(string? digest, out string normalizedHash)
    {
        normalizedHash = string.Empty;
        if (string.IsNullOrWhiteSpace(digest))
            return false;

        var candidate = digest.Trim();
        if (candidate.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
            candidate = candidate["sha256:".Length..].Trim();

        if (!Sha256Pattern.IsMatch(candidate))
            return false;

        normalizedHash = candidate.ToLowerInvariant();
        return true;
    }

    public static bool TryParseChecksumText(string? text, string expectedFileName, out string normalizedHash)
    {
        normalizedHash = string.Empty;
        if (string.IsNullOrWhiteSpace(text) || string.IsNullOrWhiteSpace(expectedFileName))
            return false;

        string? foundHash = null;
        foreach (var rawLine in text.Replace("\r", string.Empty, StringComparison.Ordinal).Split('\n'))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal))
                continue;

            var match = ChecksumLinePattern.Match(line);
            if (!match.Success || foundHash is not null)
                return false;

            var suppliedName = match.Groups["name"].Value;
            if (!string.IsNullOrEmpty(suppliedName))
            {
                if (suppliedName.Contains('/') || suppliedName.Contains('\\')
                    || !string.Equals(suppliedName, expectedFileName, StringComparison.Ordinal))
                    return false;
            }

            foundHash = match.Groups["hash"].Value.ToLowerInvariant();
        }

        if (foundHash is null)
            return false;

        normalizedHash = foundHash;
        return true;
    }

    public static bool IsAllowedHash(string? value) =>
        !string.IsNullOrWhiteSpace(value) && Sha256Pattern.IsMatch(value);
}