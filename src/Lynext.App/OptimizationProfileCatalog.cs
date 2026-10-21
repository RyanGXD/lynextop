namespace Lynext;

public sealed record OptimizationProfileDefinition(
    string Id,
    string Name,
    string Description,
    IReadOnlyList<string> OptimizationIds,
    bool IsImplemented);

/// <summary>Profile capabilities are data, independent from display controls and selection.</summary>
public static class OptimizationProfileCatalog
{
    public static IReadOnlyList<OptimizationProfileDefinition> Profiles { get; } =
    [
        new("gamer-ultra", "Gamer Ultra", "Modo de Jogo e plano Alto desempenho opcional, quando compatível.",
            ["gamer.game-mode", "gamer-ultra.power-plan"], true),
        new("gamer", "Gamer", "Modo de Jogo do Windows; sem alterações adicionais de energia.",
            ["gamer.game-mode"], true),
        new("lite", "Lite", "Perfil em planejamento; sem funções implementadas.", [], false),
        new("business", "Empresarial", "Perfil em planejamento; sem funções implementadas.", [], false),
        new("economy", "Economia", "Perfil em planejamento; sem funções implementadas.", [], false)
    ];

    public static OptimizationProfileDefinition? FindByName(string name) =>
        Profiles.FirstOrDefault(profile => string.Equals(profile.Name, name, StringComparison.Ordinal));

    /// <summary>Selection is a pure view operation and never authorizes system changes.</summary>
    public static IReadOnlyList<string> GetSelectionOperations(string name) => [];

    public static bool AllowsOptimization(string profileName, string optimizationId) =>
        FindByName(profileName)?.OptimizationIds.Contains(optimizationId, StringComparer.Ordinal) == true;

    public static IReadOnlyList<string> GetVisiblePanels(string name) => name switch
    {
        "Gamer Ultra" => ["gamer-ultra"],
        "Gamer" => ["gamer"],
        "Lite" => ["lite"],
        "Empresarial" => ["business"],
        "Economia" => ["economy"],
        _ => []
    };
}

