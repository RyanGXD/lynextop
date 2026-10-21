using System.IO;
using System.Text.Json;

namespace Lynext;

public sealed record UpdatePreferences(bool AutomaticUpdatesEnabled, DateTimeOffset? LastCheckUtc, string? LastDownloadedVersion)
{
    private static readonly string SettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lynext", "Updates", "preferences.json");
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    public const int MinimumCheckIntervalHours = 6;
    public static UpdatePreferences Default { get; } = new(false, null, null);
    public static UpdatePreferences Load(string? path = null)
    {
        try { return JsonSerializer.Deserialize<UpdatePreferences>(File.ReadAllText(path ?? SettingsPath)) ?? Default; }
        catch { return Default; }
    }
    public UpdatePreferences Save(string? path = null)
    {
        path ??= SettingsPath;
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this, JsonOptions));
        File.Move(temporary, path, true);
        return this;
    }
    public bool IsCheckDue(DateTimeOffset now) => LastCheckUtc is null || now - LastCheckUtc >= TimeSpan.FromHours(MinimumCheckIntervalHours);
}

public readonly record struct LynextReleaseVersion(Version Numeric, bool IsPreview) : IComparable<LynextReleaseVersion>
{
    public static bool TryParse(string? value, out LynextReleaseVersion parsed)
    {
        parsed = default;
        if (string.IsNullOrWhiteSpace(value)) return false;
        var text = value.Trim();
        var preview = text.EndsWith("-preview", StringComparison.OrdinalIgnoreCase)
            || text.Contains("-preview.", StringComparison.OrdinalIgnoreCase);
        if (preview) text = text[..text.IndexOf("-preview", StringComparison.OrdinalIgnoreCase)];
        if (!Version.TryParse(text, out var numeric) || numeric.Revision >= 0 && numeric.Build < 0) return false;
        parsed = new LynextReleaseVersion(numeric, preview);
        return true;
    }
    public int CompareTo(LynextReleaseVersion other)
    {
        var numeric = Numeric.CompareTo(other.Numeric);
        return numeric != 0 ? numeric : IsPreview == other.IsPreview ? 0 : IsPreview ? -1 : 1;
    }
    public override string ToString() => Numeric.ToString(3) + (IsPreview ? "-preview" : string.Empty);
}
