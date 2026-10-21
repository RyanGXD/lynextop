using Lynext;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class LiteSystemDiagnosticsTests
{
    [Fact]
    public void ProcessSampleCalculatesCpuFromElapsedProcessorTimeAndKeepsIdentity()
    {
        var before = new Dictionary<int, LiteSystemDiagnosticsService.ProcessSample>
        {
            [42] = new(42, "Editor", TimeSpan.FromSeconds(1), 100, @"C:\Apps\editor.exe", "Example Ltd.", "aplicativo/outro caminho")
        };
        var after = new Dictionary<int, LiteSystemDiagnosticsService.ProcessSample>
        {
            [42] = new(42, "Editor", TimeSpan.FromSeconds(2), 200, @"C:\Apps\editor.exe", "Example Ltd.", "aplicativo/outro caminho")
        };

        var row = Assert.Single(LiteSystemDiagnosticsService.BuildProcessRows(before, after, TimeSpan.FromSeconds(2), 2));

        Assert.Equal(25d, row.CpuPercent!.Value, 5);
        Assert.Equal(200, row.WorkingSetBytes);
        Assert.Equal("Example Ltd.", row.PublisherMetadata);
        Assert.Equal(@"C:\Apps\editor.exe", row.ExecutablePath);
    }

    [Fact]
    public void UnknownOrHighMemoryProcessIsReportedWithoutBeingClassifiedAsWaste()
    {
        var process = new LiteProcessObservation("Unknown", 77, 85, 4L * 1024 * 1024 * 1024,
            "", "", "origem desconhecida");
        var report = LiteSystemDiagnosticsService.BuildReport(new(DateTimeOffset.UnixEpoch,
            "Windows test", "CPU test", 8, 4, 16, 2L * 1024 * 1024 * 1024,
            [new("C:\\", 100, 25)], [process], "desconhecida", "não confirmada", "sem histórico"));

        Assert.Contains("uso alto não significa desperdício", report);
        Assert.Contains("Unknown (PID 77)", report);
        Assert.Contains("origem desconhecida", report);
        Assert.Contains("Nenhum processo foi encerrado", report);
        Assert.DoesNotContain("dispensável", report, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ProcessThatStartsBetweenSamplesHasUnknownCpuRatherThanZeroOrAnError()
    {
        var after = new Dictionary<int, LiteSystemDiagnosticsService.ProcessSample>
        {
            [9] = new(9, "New", TimeSpan.FromMilliseconds(5), 1000, "", "", "origem desconhecida")
        };
        var row = Assert.Single(LiteSystemDiagnosticsService.BuildProcessRows(
            new Dictionary<int, LiteSystemDiagnosticsService.ProcessSample>(), after, TimeSpan.FromSeconds(1), 4));
        Assert.Null(row.CpuPercent);
    }

    [Fact]
    public void InvalidPowerQueryIsExplicitlyUnknownAndReadOnly()
    {
        var summary = LiteSystemDiagnosticsService.SummarizePowerQuery("");
        Assert.Contains("valores não confirmados", summary);
    }
}

