using Lynext;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class OptimizationProfileCatalogTests
{
    [Theory]
    [InlineData("Gamer", "gamer")]
    [InlineData("Gamer Ultra", "gamer-ultra")]
    [InlineData("Lite", "lite")]
    [InlineData("Empresarial", "business")]
    [InlineData("Economia", "economy")]
    public void ProfileSelectionShowsOnlyItsOwnScreen(string profile, string expectedPanel)
    {
        Assert.Equal(new[] { expectedPanel }, OptimizationProfileCatalog.GetVisiblePanels(profile));
        Assert.Empty(OptimizationProfileCatalog.GetSelectionOperations(profile));
    }

    [Fact]
    public void GamerProfilesHaveSeparateAllowedOptimizationSets()
    {
        Assert.Equal(new[] { "gamer.game-mode", "power-manager.gamer" }, OptimizationProfileCatalog.FindByName("Gamer")!.OptimizationIds);
        Assert.Equal(new[] { "gamer.game-mode", "gamer-ultra.power-plan", "power-manager.gamer-ultra" },
            OptimizationProfileCatalog.FindByName("Gamer Ultra")!.OptimizationIds);
    }

    [Theory]
    [InlineData("Lite")]
    [InlineData("Empresarial")]
    [InlineData("Economia")]
    public void NonGamingProfilesUseOnlyTheirDedicatedEnergyOperation(string profile)
    {
        var definition = OptimizationProfileCatalog.FindByName(profile)!;
        Assert.True(definition.IsImplemented);
        Assert.Equal(new[] { "power-manager." + definition.Id }, definition.OptimizationIds);
        Assert.Empty(OptimizationProfileCatalog.GetSelectionOperations(profile));
        Assert.NotEmpty(OptimizationProfileCatalog.GetFeatures(profile));
        Assert.All(OptimizationProfileCatalog.GetFeatures(profile), feature => Assert.False(feature.ChangesWindows));
    }

    [Theory]
    [InlineData("Lite", "lite")]
    [InlineData("Empresarial", "business")]
    [InlineData("Economia", "economy")]
    public void NewProfileCapabilitiesAreIsolated(string profile, string expectedId)
    {
        var definition = OptimizationProfileCatalog.FindByName(profile)!;
        Assert.Equal(expectedId, definition.Id);
        Assert.All(OptimizationProfileCatalog.GetFeatures(profile), feature => Assert.Equal(expectedId, feature.ProfileId));
    }

    [Fact]
    public void FeatureCatalogDescribesReadQueryActionAndRestoreForEveryCapability()
    {
        Assert.All(OptimizationProfileCatalog.Features, feature =>
        {
            Assert.False(string.IsNullOrWhiteSpace(feature.Id));
            Assert.False(string.IsNullOrWhiteSpace(feature.Scope));
            Assert.False(string.IsNullOrWhiteSpace(feature.Preconditions));
            Assert.False(string.IsNullOrWhiteSpace(feature.Benefit));
            Assert.False(string.IsNullOrWhiteSpace(feature.Risk));
            Assert.False(string.IsNullOrWhiteSpace(feature.Query));
            Assert.False(string.IsNullOrWhiteSpace(feature.Action));
            Assert.False(string.IsNullOrWhiteSpace(feature.Restore));
            Assert.StartsWith("https://", feature.Reference);
        });
        Assert.Equal(OptimizationProfileCatalog.Features.Count, OptimizationProfileCatalog.Features.Select(x => x.Id).Distinct().Count());
    }

    [Theory]
    [InlineData("Lite")]
    [InlineData("Empresarial")]
    [InlineData("Economia")]
    public void NewProfilesCannotAuthorizeGamerOperations(string profile)
    {
        Assert.False(OptimizationProfileCatalog.AllowsOptimization(profile, "gamer.game-mode"));
        Assert.False(OptimizationProfileCatalog.AllowsOptimization(profile, "gamer-ultra.power-plan"));
    }

    [Fact]
    public void InvalidProfileHasNoFeatures()
    {
        Assert.Empty(OptimizationProfileCatalog.GetFeatures("unknown"));
    }

    [Theory]
    [InlineData("gamer-ultra")]
    [InlineData("gamer")]
    [InlineData("business")]
    [InlineData("lite")]
    [InlineData("economy")]
    public void PowerManagerUsesExactClosedAllowlistTargets(string profileId)
    {
        var result = OptimizationAuthorizationPolicy.Authorize(
            [new("power-manager." + profileId, OptimizationTargetKind.PowerPlan, "managed-scheme:" + profileId)]);
        Assert.True(result.Allowed);
        var external = OptimizationAuthorizationPolicy.Authorize(
            [new("power-manager." + profileId, OptimizationTargetKind.ExternalCommand, "powercfg.exe")]);
        Assert.False(external.Allowed);
    }
}


