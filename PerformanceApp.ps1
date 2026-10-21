#requires -version 5.1
# Legacy performance presets were removed because they changed undocumented Windows
# settings and their rollback could overwrite user changes. Do not add optimization
# commands here; the desktop app owns the allowlisted, reversible profile catalog.
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show(
    "Os presets antigos de desempenho foram desativados por segurança. Eles alteravam configurações de Game DVR, GPU, rede e energia sem uma autorização centralizada e recuperação confiável. Use o aplicativo Lynext Desktop para os perfis Gamer/Gamer Ultra e o diagnóstico da Microsoft Store/Xbox. Backups antigos foram preservados em %LOCALAPPDATA%\Lynext para análise; nenhum valor será restaurado automaticamente.",
    "Lynext — módulo legado desativado",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Warning
) | Out-Null
exit 0
