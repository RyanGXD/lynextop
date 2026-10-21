using System.Management;

namespace Lynext;

public sealed record GraphicsAdapterInfo(string Name, string DriverVersion, string DriverDate);

public sealed record HardwareSnapshot(
    string Processor,
    IReadOnlyList<GraphicsAdapterInfo> GraphicsAdapters,
    string WindowsVersion,
    int LogicalProcessors,
    int PhysicalCores,
    double InstalledMemoryGb,
    DateTime ScannedAt);

public static class HardwareInfoService
{
    public static HardwareSnapshot Read()
    {
        var processor = ReadFirst("SELECT Name FROM Win32_Processor", "Name")
            ?? Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER")
            ?? "Não identificado";

        var physicalCores = ReadIntegerFirst("SELECT NumberOfCores FROM Win32_Processor", "NumberOfCores");
        var totalMemoryBytes = ReadUnsignedLongFirst("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem", "TotalPhysicalMemory");
        var memoryGb = totalMemoryBytes > 0 ? Math.Round(totalMemoryBytes / 1024d / 1024d / 1024d, 1) : 0;

        var graphics = ReadGraphicsAdapters();
        if (graphics.Count == 0)
            graphics.Add(new GraphicsAdapterInfo("Não identificada", "Indisponível", "Indisponível"));

        var windowsName = ReadFirst("SELECT Caption FROM Win32_OperatingSystem", "Caption");
        var windowsVersion = ReadFirst("SELECT Version FROM Win32_OperatingSystem", "Version");
        var windowsBuild = ReadFirst("SELECT BuildNumber FROM Win32_OperatingSystem", "BuildNumber");
        var windows = $"{windowsName ?? Environment.OSVersion.VersionString} {windowsVersion ?? ""} (build {windowsBuild ?? "?"}, {(Environment.Is64BitOperatingSystem ? "64-bit" : "32-bit")})".Trim();

        return new HardwareSnapshot(
            processor.Trim(),
            graphics,
            windows,
            Environment.ProcessorCount,
            physicalCores,
            memoryGb,
            DateTime.Now);
    }

    private static List<GraphicsAdapterInfo> ReadGraphicsAdapters()
    {
        var values = new List<GraphicsAdapterInfo>();
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT Name, DriverVersion, DriverDate FROM Win32_VideoController");
            foreach (ManagementObject item in searcher.Get())
            {
                var name = item["Name"]?.ToString();
                if (string.IsNullOrWhiteSpace(name))
                    continue;

                values.Add(new GraphicsAdapterInfo(
                    name.Trim(),
                    item["DriverVersion"]?.ToString() ?? "Indisponível",
                    FormatWmiDate(item["DriverDate"]?.ToString())));
            }
        }
        catch
        {
            // Hardware inventory should fail gracefully on restricted or unusual systems.
        }

        return values
            .GroupBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .Select(x => x.First())
            .ToList();
    }

    private static string FormatWmiDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "Indisponível";

        try
        {
            return ManagementDateTimeConverter.ToDateTime(value).ToString("dd/MM/yyyy");
        }
        catch
        {
            return "Indisponível";
        }
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

    private static int ReadIntegerFirst(string query, string property)
    {
        var value = ReadFirst(query, property);
        return int.TryParse(value, out var parsed) ? parsed : 0;
    }

    private static ulong ReadUnsignedLongFirst(string query, string property)
    {
        var value = ReadFirst(query, property);
        return ulong.TryParse(value, out var parsed) ? parsed : 0;
    }
}
