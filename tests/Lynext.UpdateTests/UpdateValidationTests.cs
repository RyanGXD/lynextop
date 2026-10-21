using Lynext;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class UpdateValidationTests
{
    private const string InstallerName = "Lynext-Setup-1.2.3-x64.exe";
    private static string ValidHash => new('a', 64);

    [Theory]
    [InlineData("v1.2.3", true)]
    [InlineData("1.2.3", true)]
    [InlineData("V1.2.3", true)]
    [InlineData("1.2.3.4", true)]
    [InlineData("", false)]
    [InlineData("latest", false)]
    [InlineData("v1.2", false)]
    [InlineData("v1.2.3-beta", false)]
    [InlineData("../1.2.3", false)]
    [InlineData("1.2.3/../../x", false)]
    [InlineData("v1.2.3.4.5", false)]
    public void ParsesOnlyNumericStableVersionTags(string? value, bool expected) =>
        Assert.Equal(expected, UpdateValidation.TryParseVersionTag(value, out _));

    [Theory]
    [InlineData("https://github.com/RyanGXD/lynextop/releases/download/v1.2.3/setup.exe", true)]
    [InlineData("https://release-assets.githubusercontent.com/assets/setup.exe", true)]
    [InlineData("https://objects.githubusercontent.com/assets/setup.exe", true)]
    [InlineData("http://github.com/RyanGXD/lynextop/setup.exe", false)]
    [InlineData("ftp://github.com/setup.exe", false)]
    [InlineData("https://example.com/setup.exe", false)]
    [InlineData("https://github.com.evil.example/setup.exe", false)]
    [InlineData("https://github.com:444/setup.exe", false)]
    [InlineData("https://user:password@github.com/setup.exe", false)]
    [InlineData("file:///C:/temp/setup.exe", false)]
    [InlineData("javascript:alert(1)", false)]
    public void ValidatesDownloadOrigins(string value, bool expected) =>
        Assert.Equal(expected, UpdateValidation.IsAllowedDownloadUri(new Uri(value)));

    [Fact]
    public void RejectsNullDownloadUri() => Assert.False(UpdateValidation.IsAllowedDownloadUri(null));

    [Fact]
    public void ParsesSha256DigestWithPrefix()
    {
        Assert.True(UpdateValidation.TryParseSha256Digest("sha256:" + ValidHash.ToUpperInvariant(), out var parsed));
        Assert.Equal(ValidHash, parsed);
    }

    [Fact]
    public void ParsesBareSha256Digest()
    {
        Assert.True(UpdateValidation.TryParseSha256Digest(ValidHash, out var parsed));
        Assert.Equal(ValidHash, parsed);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("sha1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
    [InlineData("sha512:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
    [InlineData("sha256:1234")]
    [InlineData("sha256:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")]
    public void RejectsMalformedDigest(string? value) =>
        Assert.False(UpdateValidation.TryParseSha256Digest(value, out _));

    [Fact]
    public void ParsesChecksumWithMatchingFilename()
    {
        Assert.True(UpdateValidation.TryParseChecksumText(ValidHash + "  " + InstallerName + "\n", InstallerName, out var parsed));
        Assert.Equal(ValidHash, parsed);
    }

    [Fact]
    public void ParsesChecksumWithGnuFilenameMarker()
    {
        Assert.True(UpdateValidation.TryParseChecksumText(ValidHash.ToUpperInvariant() + " *" + InstallerName, InstallerName, out var parsed));
        Assert.Equal(ValidHash, parsed);
    }

    [Fact]
    public void ParsesChecksumWithoutFilename()
    {
        Assert.True(UpdateValidation.TryParseChecksumText(ValidHash, InstallerName, out var parsed));
        Assert.Equal(ValidHash, parsed);
    }

    [Fact]
    public void IgnoresChecksumCommentsAndBlankLines()
    {
        var text = "# sha256 checksum\n\n" + ValidHash + "\n";
        Assert.True(UpdateValidation.TryParseChecksumText(text, InstallerName, out var parsed));
        Assert.Equal(ValidHash, parsed);
    }

    [Theory]
    [InlineData("")]
    [InlineData("not a checksum")]
    [InlineData("abc")]
    [InlineData("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
    public void RejectsMalformedChecksumText(string text) =>
        Assert.False(UpdateValidation.TryParseChecksumText(text, InstallerName, out _));

    [Fact]
    public void RejectsChecksumWithDifferentFilename() =>
        Assert.False(UpdateValidation.TryParseChecksumText(ValidHash + "  other.exe", InstallerName, out _));

    [Fact]
    public void RejectsChecksumWithPathTraversalFilename() =>
        Assert.False(UpdateValidation.TryParseChecksumText(ValidHash + "  ../" + InstallerName, InstallerName, out _));

    [Fact]
    public void RejectsMultipleChecksumValues() =>
        Assert.False(UpdateValidation.TryParseChecksumText(ValidHash + "\n" + ValidHash, InstallerName, out _));

    [Fact]
    public void RejectsEmptyChecksumFilenameParameter() =>
        Assert.False(UpdateValidation.TryParseChecksumText(ValidHash, "", out _));

    [Theory]
    [InlineData("Lynext-Setup-1.2.3-x64.exe", true)]
    [InlineData("lynEXT-setup-1.2.3-x64.EXE", true)]
    [InlineData("Lynext-Setup-1.2.4-x64.exe", false)]
    [InlineData("Lynext-Setup-1.2.3-arm64.exe", false)]
    [InlineData("evil-Lynext-Setup-1.2.3-x64.exe", false)]
    [InlineData("Lynext-Setup-1.2.3-x64.exe.exe", false)]
    public void RequiresExactVersionedInstallerName(string name, bool expected) =>
        Assert.Equal(expected, UpdateValidation.IsExpectedInstallerName(name, Version.Parse("1.2.3")));

    [Theory]
    [InlineData(true, false, false)]
    [InlineData(false, true, false)]
    [InlineData(false, false, true)]
    [InlineData(true, true, false)]
    public void RejectsDraftsAndPrereleases(bool draft, bool prerelease, bool expected) =>
        Assert.Equal(expected, UpdateValidation.IsStableRelease(draft, prerelease));

    [Theory]
    [InlineData("1.2.4", "1.2.3", true)]
    [InlineData("1.2.3", "1.2.3", false)]
    [InlineData("1.2.2", "1.2.3", false)]
    [InlineData("2.0.0", "1.99.99", true)]
    [InlineData("1.2.3.1", "1.2.3", true)]
    public void ComparesVersionsWithoutDowngrading(string candidate, string installed, bool expected) =>
        Assert.Equal(expected, UpdateValidation.IsNewerVersion(Version.Parse(candidate), Version.Parse(installed)));

    [Fact]
    public void ValidatesManifestHashes()
    {
        Assert.False(UpdateValidation.IsAllowedHash(null));
        Assert.False(UpdateValidation.IsAllowedHash("not-a-hash"));
        Assert.False(UpdateValidation.IsAllowedHash(new string('a', 63)));
        Assert.False(UpdateValidation.IsAllowedHash(new string('g', 64)));
        Assert.True(UpdateValidation.IsAllowedHash(ValidHash));
    }
}