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
        Assert.Equal(new[] { "gamer.game-mode" }, OptimizationProfileCatalog.FindByName("Gamer")!.OptimizationIds);
        Assert.Equal(new[] { "gamer.game-mode", "gamer-ultra.power-plan" },
            OptimizationProfileCatalog.FindByName("Gamer Ultra")!.OptimizationIds);
    }

    [Theory]
    [InlineData("Lite")]
    [InlineData("Empresarial")]
    [InlineData("Economia")]
    public void PlannedProfilesHaveNoCapabilitiesOrOperations(string profile)
    {
        var definition = OptimizationProfileCatalog.FindByName(profile)!;
        Assert.False(definition.IsImplemented);
        Assert.Empty(definition.OptimizationIds);
        Assert.Empty(OptimizationProfileCatalog.GetSelectionOperations(profile));
    }
}

