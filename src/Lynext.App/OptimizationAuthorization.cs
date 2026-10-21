namespace Lynext;

public enum OptimizationTargetKind
{
    RegistryValue,
    PowerPlan,
    Service,
    AppxPackage,
    ExternalCommand
}

public sealed record OptimizationChange(string OptimizationId, OptimizationTargetKind Kind, string Target);
public sealed record OptimizationAuthorization(bool Allowed, string Reason);
public sealed record OptimizationCatalogEntry(
    string Id, string Justification, string Preconditions, string Risks,
    string StateQuery, string ApplyOperation, string RestoreOperation,
    OptimizationTargetKind Kind, string Target);

/// <summary>Closed allowlist for every system change made by the desktop optimization profiles.</summary>
public static class OptimizationAuthorizationPolicy
{
    public static IReadOnlyList<OptimizationCatalogEntry> Catalog { get; } =
    [
        new("gamer.game-mode", "Expose the Windows Game Mode setting for the current user; no measured FPS gain is claimed.",
            "Windows current-user GameBar key is writable and the value is absent or a DWORD.",
            "Changes only the current user's Game Mode preference.",
            "Read AutoGameModeEnabled before and after the write.",
            "Set AutoGameModeEnabled=1 for the current user.",
            "Restore only the value captured before Lynext changed it, after conflict checking.",
            OptimizationTargetKind.RegistryValue, @"HKCU\Software\Microsoft\GameBar\AutoGameModeEnabled"),
        new("gamer-ultra.power-plan", "Offer Windows High Performance only as an explicit user choice.",
            "The plan exists, battery detection positively confirms no battery, and the user explicitly accepts.",
            "May increase power use, heat and fan noise; no FPS gain is claimed.",
            "Read active scheme GUID before and after powercfg.",
            "Change the active power scheme to the built-in High Performance scheme.",
            "Return to the captured original GUID only if the active scheme still matches Lynext's applied GUID.",
            OptimizationTargetKind.PowerPlan, "active-power-scheme")
    ];

    private static readonly IReadOnlyDictionary<string, OptimizationCatalogEntry> Approved =
        Catalog.ToDictionary(entry => entry.Id, StringComparer.Ordinal);

    private static readonly HashSet<string> ProtectedServices = new(StringComparer.OrdinalIgnoreCase)
    {
        "AppXSvc", "ClipSVC", "InstallService", "LicenseManager", "BITS", "DoSvc",
        "GamingServices", "GamingServicesNet", "XblAuthManager", "XblGameSave",
        "XboxNetApiSvc", "XboxGipSvc", "wuauserv", "UsoSvc", "TrustedInstaller",
        "CryptSvc", "msiserver"
    };

    public static OptimizationAuthorization Authorize(IEnumerable<OptimizationChange> changes)
    {
        ArgumentNullException.ThrowIfNull(changes);
        var requested = changes.ToArray();
        if (requested.Length == 0)
            return new(false, "A operação não declarou alterações; a política nega por padrão.");

        foreach (var change in requested)
        {
            if (change is null || string.IsNullOrWhiteSpace(change.OptimizationId) || string.IsNullOrWhiteSpace(change.Target))
                return new(false, "Alteração sem identificação completa; a política nega por padrão.");
            if (change.Kind is OptimizationTargetKind.ExternalCommand or OptimizationTargetKind.Service or OptimizationTargetKind.AppxPackage)
                return new(false, $"O catálogo não autoriza comandos externos nem alterações de serviços ou pacotes ({change.Target}).");
            if (change.Kind == OptimizationTargetKind.Service && ProtectedServices.Contains(change.Target))
                return new(false, $"O serviço protegido {change.Target} não pode ser alterado.");
            if (IsProtectedRegistryPath(change.Target))
                return new(false, $"A configuração protegida {change.Target} não pode ser alterada pelo otimizador.");
            if (!Approved.TryGetValue(change.OptimizationId, out var approved)
                || approved.Kind != change.Kind
                || !string.Equals(approved.Target, change.Target, StringComparison.OrdinalIgnoreCase))
                return new(false, $"A alteração {change.OptimizationId} não está aprovada no catálogo fechado.");
        }

        return new(true, "Todas as alterações correspondem exatamente ao catálogo aprovado.");
    }

    private static bool IsProtectedRegistryPath(string target)
    {
        var normalized = target.Replace('/', '\\').Trim().TrimEnd('\\');
        return normalized.StartsWith("HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\Installer", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("HKLM\\SOFTWARE\\Policies\\Microsoft\\WindowsStore", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows Defender", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("HKLM\\SOFTWARE\\Policies\\Microsoft\\WindowsFirewall", StringComparison.OrdinalIgnoreCase)
            || normalized.StartsWith("HKLM\\SYSTEM\\CurrentControlSet\\Services\\", StringComparison.OrdinalIgnoreCase)
            || normalized.Contains("\\Appx", StringComparison.OrdinalIgnoreCase)
            || normalized.Contains("\\AppModel", StringComparison.OrdinalIgnoreCase);
    }
}
