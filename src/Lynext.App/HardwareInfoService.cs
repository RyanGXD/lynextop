using System.Management;

namespace Lynext;

public sealed record HardwareSnapshot(
    string Processor,
    IReadOnlyList<string> GraphicsAdapters,
    string WindowsVersion,
    int LogicalProcessors,
    DateTime ScannedAt);

public static class HardwareInfoService
{
    public static HardwareSnapshot Read()
    {
        var processor = ReadFirst("SELECT Name FROM Win32_Processor", "Name")
            ?? Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER")
            ?? "Não identificado";

        var graphics = ReadMany("SELECT Name FROM Win32_VideoController", "Name");
        if (graphics.Count == 0)
            graphics.Add("Não identificada");

        var windows = $"{Environment.OSVersion.VersionString} ({(Environment.Is64BitOperatingSystem ? "64-bit" : "32-bit")})";

        return new HardwareSnapshot(
            processor.Trim(),
            graphics.Select(x => x.Trim()).Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().ToArray(),
            windows,
            Environment.ProcessorCount,
            DateTime.Now);
    }

    private static string? ReadFirst(string query, string property)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(query);
            foreach (ManagementObject item in searcher.Get())
                return item[property]?.ToString();
        }
        catch
        {
            // Hardware inventory should fail gracefully on restricted or unusual systems.
        }

        return null;
    }

    private static List<string> ReadMany(string query, string property)
    {
        var values = new List<string>();
        try
        {
            using var searcher = new ManagementObjectSearcher(query);
            foreach (ManagementObject item in searcher.Get())
            {
                var value = item[property]?.ToString();
                if (!string.IsNullOrWhiteSpace(value))
                    values.Add(value);
            }
        }
        catch
        {
            // Hardware inventory should fail gracefully on restricted or unusual systems.
        }

        return values;
    }
}
