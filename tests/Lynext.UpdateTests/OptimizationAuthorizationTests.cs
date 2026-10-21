using Lynext;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class OptimizationAuthorizationTests
{
    [Theory]
    [InlineData("AppXSvc")]
    [InlineData("ClipSVC")]
    [InlineData("InstallService")]
    [InlineData("LicenseManager")]
    [InlineData("BITS")]
    [InlineData("DoSvc")]
    [InlineData("GamingServices")]
    [InlineData("GamingServicesNet")]
    [InlineData("XblAuthManager")]
    [InlineData("XblGameSave")]
    [InlineData("XboxNetApiSvc")]
    [InlineData("XboxGipSvc")]
    public void ProtectedServiceMutationIsDenied(string name)
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
            [new("try.stop-service", OptimizationTargetKind.Service, name)]);
        Assert.False(decision.Allowed);
    }

    [Theory]
    [InlineData(@"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA")]
    [InlineData(@"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorAdmin")]
    [InlineData(@"HKLM\SOFTWARE\Policies\Microsoft\WindowsStore\AutoDownload")]
    [InlineData(@"HKLM\SYSTEM\CurrentControlSet\Services\AppXSvc\Start")]
    [InlineData(@"HKCU\Software\Microsoft\Windows\CurrentVersion\Appx\PackageRepository")]
    public void ProtectedRegistryPathIsDenied(string target)
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
            [new("custom.registry", OptimizationTargetKind.RegistryValue, target)]);
        Assert.False(decision.Allowed);
    }

    [Fact]
    public void GamerGameModeIsTheOnlyApprovedRegistryChange()
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
            [new("gamer.game-mode", OptimizationTargetKind.RegistryValue, @"HKCU\Software\Microsoft\GameBar\AutoGameModeEnabled")]);
        Assert.True(decision.Allowed);
    }

    [Fact]
    public void ApprovedPowerPlanChangeIsAllowed()
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
            [new("gamer-ultra.power-plan", OptimizationTargetKind.PowerPlan, "active-power-scheme")]);
        Assert.True(decision.Allowed);
    }

    [Fact]
    public void UnknownConfigurationIsDeniedByDefault()
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
            [new("unknown", OptimizationTargetKind.RegistryValue, @"HKCU\Software\Example\Value")]);
        Assert.False(decision.Allowed);
    }

    [Fact]
    public void ArbitraryExternalScriptIsDenied()
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
            [new("gamer.game-mode", OptimizationTargetKind.ExternalCommand, "powershell -File arbitrary.ps1")]);
        Assert.False(decision.Allowed);
    }

    [Fact]
    public void MixedAllowedAndDeniedChangesAreRejectedAsAWhole()
    {
        var decision = OptimizationAuthorizationPolicy.Authorize(
        [
            new("gamer.game-mode", OptimizationTargetKind.RegistryValue, @"HKCU\Software\Microsoft\GameBar\AutoGameModeEnabled"),
            new("unknown", OptimizationTargetKind.RegistryValue, @"HKLM\Software\Unknown\Value")
        ]);
        Assert.False(decision.Allowed);
    }

    [Fact]
    public void EmptyOrUndeclaredCatalogIsDenied()
    {
        Assert.False(OptimizationAuthorizationPolicy.Authorize([]).Allowed);
    }

    [Fact]
    public void ServiceAndPackageChangesAreNeverAllowedByOptimizationProfiles()
    {
        Assert.False(OptimizationAuthorizationPolicy.Authorize([new("future", OptimizationTargetKind.Service, "SomeService")]).Allowed);
        Assert.False(OptimizationAuthorizationPolicy.Authorize([new("future", OptimizationTargetKind.AppxPackage, "Some.Package")]).Allowed);
    }
}
