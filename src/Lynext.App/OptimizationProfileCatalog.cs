namespace Lynext;

public sealed record OptimizationProfileDefinition(
    string Id,
    string Name,
    string Description,
    IReadOnlyList<string> OptimizationIds,
    bool IsImplemented);

public sealed record ProfileFeatureDefinition(
    string Id, string ProfileId, string Name, string Scope, string Preconditions,
    string Benefit, string Risk, string Query, string Action, string Restore,
    bool ChangesWindows, string Reference);

/// <summary>Profile capabilities are data, independent from display controls and selection.</summary>
public static class OptimizationProfileCatalog
{
    public static IReadOnlyList<ProfileFeatureDefinition> Features { get; } =
    [
        new("lite.startup-review", "lite", "Revisão de inicialização", "Leitura do usuário e máquina", "Acesso às chaves Run e pastas Startup", "Identificar itens de inicialização", "Impacto não medido; itens podem ser desconhecidos", "Enumerar sem alterar", "Abrir Configurações > Aplicativos > Inicialização", "Nenhuma alteração Lynext", false, "https://support.microsoft.com/pt-br/windows/experience/startup-boot/configure-startup-applications-in-windows"),
        new("lite.visual-review", "lite", "Efeitos visuais", "Configuração nativa por usuário/dispositivo", "Página disponível no Windows", "Ajustar preferência visual", "Pode afetar acessibilidade; FPS não garantido", "Nenhuma leitura Lynext", "Abrir Configurações de acessibilidade", "Reverter manualmente no Windows", false, "https://support.microsoft.com/pt-br/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows"),
        new("lite.background-review", "lite", "Atividade em segundo plano", "Por aplicativo compatível", "A opção depende de cada app e versão", "Revisar atividade opcional", "Notificações e sincronização podem ficar menos frequentes", "Nenhuma leitura Lynext", "Abrir uso da bateria/Configurações nativas", "Reverter manualmente no Windows", false, "https://support.microsoft.com/pt-br/windows/experience/performance-optimization/manage-background-activity-for-apps-in-windows"),
        new("lite.storage-review", "lite", "Armazenamento", "Configuração nativa", "Suporte varia por Windows", "Usar Sensor de armazenamento", "Exclusões pelo Windows dependem das opções escolhidas", "Nenhuma leitura Lynext", "Abrir Armazenamento do Windows", "Revisar e reverter opções no Windows", false, "https://support.microsoft.com/pt-br/windows/experience/storage-filemanagement/manage-drive-space-with-storage-sense"),
        new("business.compatibility-diagnostic", "business", "Triagem de compatibilidade", "Somente leitura local", "WMI/rede podem estar indisponíveis", "Expor indicadores básicos de suporte", "Não comprova funcionamento de ponta a ponta", "Interfaces, WMI de impressora e sinais locais de política", "Executar diagnóstico local a pedido", "Não aplicável; nenhuma configuração alterada", false, "https://support.microsoft.com/pt-br/windows/hardware/printer/share-a-printer-as-a-network-printer"),
        new("business.policy-review", "business", "Sinais de gerenciamento", "Leitura de chaves de política/inscrição", "Sinais não detectam todos os MDM/GPO", "Evitar sobrescrever administração organizacional", "Pode retornar desconhecido ou falso negativo", "Consultar sinais locais de Windows Update e Enrollment", "Orientar contato com administrador", "Não aplicável; políticas nunca alteradas", false, "https://learn.microsoft.com/pt-br/windows/deployment/update/waas-manage-updates-wufb"),
        new("economy.power-review", "economy", "Bateria e plano de energia", "Consulta local", "WMI e powercfg precisam estar disponíveis", "Identificar limites do dispositivo", "Leituras podem estar indisponíveis", "Win32_Battery; GetSystemPowerStatus; powercfg /getactivescheme e /list", "Analisar a pedido; abrir configurações nativas", "Não aplicável; plano não alterado", false, "https://learn.microsoft.com/pt-br/windows/win32/api/winbase/nf-winbase-getsystempowerstatus"),
        new("economy.power-reports", "economy", "Relatórios de energia", "Arquivo local em LocalAppData\\Lynext\\Reports", "Comando suportado; bateria/sleepstudy podem não existir", "Consultar bateria, eficiência ou espera moderna", "Geração pode demorar/exigir privilégio", "powercfg /batteryreport, /energy e /sleepstudy", "Executar somente após confirmação", "Excluir o relatório local manualmente", false, "https://learn.microsoft.com/pt-br/windows-hardware/design/device-experiences/powercfg-command-line-options"),
        new("economy.native-settings", "economy", "Ajustes nativos de energia", "Configuração por bateria/tomada", "Varia por hardware, Windows e política", "Escolher modo/tempos adequados", "Pode afetar desempenho ou disponibilidade", "O usuário consulta valores no Windows", "Abrir Energia e bateria", "Restaurar manualmente no Windows", false, "https://support.microsoft.com/pt-br/windows/experience/power-battery/power-settings-in-windows-11")
    ];
    public static IReadOnlyList<OptimizationProfileDefinition> Profiles { get; } =
    [
        new("gamer-ultra", "Lynext Ultra Performance", "Desempenho máximo do processador, com configurações de energia para jogos e tarefas exigentes.",
            ["gamer.game-mode", "gamer-ultra.power-plan", "power-manager.gamer-ultra"], true),
        new("gamer", "Lynext Gamer", "Perfil de desempenho para jogos, com gerenciamento de energia próprio.",
            ["gamer.game-mode", "power-manager.gamer"], true),
        new("lite", "Lynext Lite", "Perfil cotidiano baseado em Balanced, preservando o gerenciamento de CPU do Windows.", ["power-manager.lite"], true),
        new("business", "Lynext Empresarial", "Configuração conservadora baseada em Balanced, com foco em compatibilidade e previsibilidade.", ["power-manager.business"], true),
        new("economy", "Lynext Economia", "Perfil eficiente baseado em Balanced; respeita os recursos de bateria oferecidos pelo Windows e pelo equipamento.", ["power-manager.economy"], true)
    ];

    public static OptimizationProfileDefinition? FindByName(string name) =>
        Profiles.FirstOrDefault(profile => string.Equals(profile.Name, name, StringComparison.Ordinal)
            || string.Equals(profile.Id, name, StringComparison.Ordinal)
            || (profile.Id == "gamer-ultra" && name == "Gamer Ultra")
            || (profile.Id == "gamer" && name == "Gamer")
            || (profile.Id == "business" && name == "Empresarial")
            || (profile.Id == "lite" && name == "Lite")
            || (profile.Id == "economy" && name == "Economia"));

    /// <summary>Selection is a pure view operation and never authorizes system changes.</summary>
    public static IReadOnlyList<string> GetSelectionOperations(string name) => [];

    public static IReadOnlyList<ProfileFeatureDefinition> GetFeatures(string name)
    {
        var profile = FindByName(name);
        return profile is null ? [] : Features.Where(feature => feature.ProfileId == profile.Id).ToArray();
    }

    public static bool AllowsOptimization(string profileName, string optimizationId) =>
        FindByName(profileName)?.OptimizationIds.Contains(optimizationId, StringComparer.Ordinal) == true;

    public static IReadOnlyList<string> GetVisiblePanels(string name) => name switch
    {
        "Gamer Ultra" or "Lynext Ultra Performance" or "gamer-ultra" => ["gamer-ultra"],
        "Gamer" or "Lynext Gamer" or "gamer" => ["gamer"],
        "Lite" or "Lynext Lite" or "lite" => ["lite"],
        "Empresarial" or "Lynext Empresarial" or "business" => ["business"],
        "Economia" or "Lynext Economia" or "economy" => ["economy"],
        _ => []
    };
}


