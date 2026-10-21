using Lynext;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class ProfileDiagnosticsTests
{
    [Fact]
    public void EconomyDiagnosticUsesOnlyReadOnlyPowerQueries()
    {
        var commands = new List<string>();
        var report = ProfileDiagnosticsService.BuildEconomyDiagnostic("Bateria: detectada; nível 70%.", command =>
        {
            commands.Add(command);
            return command == "/getactivescheme"
                ? new(true, "Power Scheme GUID: test", "", 0)
                : new(true, "Power Schemes: GUID x", "", 0);
        }, "Alimentação atual: alimentação externa; nível reportado 70%.");

        Assert.Equal(new[] { "/getactivescheme", "/list" }, commands);
        Assert.Contains("nenhum plano foi ativado ou substituído", report);
        Assert.Contains("alimentação externa", report);
        Assert.Contains("não altera temporizadores", report);
        Assert.Contains("não há controle universal", report);
    }

    [Fact]
    public void EconomyDiagnosticCanRepresentUnknownPowerSource()
    {
        var report = ProfileDiagnosticsService.BuildEconomyDiagnostic("Bateria: estado desconhecido.",
            _ => new(true, "", "", 0), "Alimentação: estado desconhecido (API indisponível).");
        Assert.Contains("Alimentação: estado desconhecido", report);
    }

    [Fact]
    public void EconomyDiagnosticKeepsUnavailableBatteryUnknown()
    {
        var report = ProfileDiagnosticsService.BuildEconomyDiagnostic(
            "Bateria: estado desconhecido (consulta indisponível). Não será presumido um notebook.",
            _ => new(false, "", "indisponível", null));
        Assert.Contains("estado desconhecido", report);
        Assert.Contains("Não será presumido um notebook", report);
        Assert.Contains("não confirmado", report);
        Assert.Contains("lista indisponível", report);
    }

    [Fact]
    public void EconomyDoesNotClaimBatteryForDeviceWithoutBatteryData()
    {
        var report = ProfileDiagnosticsService.BuildEconomyDiagnostic(
            "Bateria: não detectada por WMI; suporte não confirmado.",
            _ => new(true, "", "", 0));
        Assert.Contains("não detectada por WMI", report);
        Assert.DoesNotContain("bateria detectada", report, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("battery", "/batteryreport")]
    [InlineData("energy", "/energy /duration 10")]
    [InlineData("sleepstudy", "/sleepstudy /duration 3")]
    public void ReportTypesAreFromDocumentedReadOnlyPowercfgSet(string type, string expected)
    {
        // Verify argument selection without invoking powercfg on the development machine.
        Assert.Equal(expected, ProfileDiagnosticsService.GetPowerReportArguments(type));
    }

    [Theory]
    [InlineData("\"C:\\Program Files\\Vendor\\app.exe\" --background", "C:\\Program Files\\Vendor\\app.exe")]
    [InlineData("%LOCALAPPDATA%\\Vendor\\app.exe --silent", "%LOCALAPPDATA%\\Vendor\\app.exe")]
    public void StartupCommandResolverReturnsExecutableWithoutArguments(string command, string expected)
    {
        Assert.Equal(Environment.ExpandEnvironmentVariables(expected), ProfileDiagnosticsService.ExpandStartupTarget(command));
    }

    [Fact]
    public void StartupCommandResolverDoesNotGuessUnrecognizedTargets()
    {
        Assert.Contains("destino não identificado", ProfileDiagnosticsService.ExpandStartupTarget("rundll32 strange syntax"));
    }

    [Fact]
    public void UnsupportedPowerReportIsRejectedBeforeCommandExecution()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => ProfileDiagnosticsService.GetPowerReportArguments("unknown"));
        Assert.Throws<ArgumentOutOfRangeException>(() => ProfileDiagnosticsService.GeneratePowerReport("unknown", _ =>
            throw new Xunit.Sdk.XunitException("runner should not be called")));
    }

    [Theory]
    [InlineData("Lite", "lite.startup-review")]
    [InlineData("Lite", "lite.visual-review")]
    [InlineData("Lite", "lite.background-review")]
    [InlineData("Lite", "lite.storage-review")]
    [InlineData("Empresarial", "business.compatibility-diagnostic")]
    [InlineData("Empresarial", "business.policy-review")]
    [InlineData("Economia", "economy.power-review")]
    [InlineData("Economia", "economy.power-reports")]
    [InlineData("Economia", "economy.native-settings")]
    public void FeatureExistsOnlyInItsOwnProfile(string profile, string featureId)
    {
        Assert.Contains(OptimizationProfileCatalog.GetFeatures(profile), feature => feature.Id == featureId);
        Assert.DoesNotContain(OptimizationProfileCatalog.Features.Where(feature => feature.ProfileId != OptimizationProfileCatalog.FindByName(profile)!.Id), feature => feature.Id == featureId);
    }
}
