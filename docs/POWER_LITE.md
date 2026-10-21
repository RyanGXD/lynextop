# Lynext Lite

## Purpose and interface

Lynext Lite is an everyday profile for reviewing startup, optional background activity, resource use, and storage without disabling Windows components. Its screen is independent. Selecting it only changes the view. **Ativar Lynext Lite** asks for confirmation and configures/activates the Lite scheme through the shared Power Manager; it does not close applications, disable startup items, change services, or delete files.

## Read-only local analysis

The on-demand analysis reads Windows version/build, processor and logical/physical core count, installed and available memory, ready fixed-drive capacity, current power source/battery observations, active power plan and supported screen/sleep values, startup registry Run entries and Startup folders, process working set/path/company metadata, and Lynext's own history summary. Process CPU is an approximate 700 ms sample normalized by logical processor count. Process metadata and paths can be unavailable due to access restrictions or process exit. Company metadata is not a signature check. No process is ranked as unnecessary, and no process can be terminated from this screen. No telemetry is uploaded.

The report keeps unavailable readings explicit. CPU and memory are a momentary sample and vary with open applications. A high value is informational and is not a recommendation to close an application. The process inventory is capped to the top 20 by sampled CPU and working set; the report shows up to eight rows.

## Startup, background activity, visual effects, and storage

Startup inventory is read-only; it lists recognized Run/Startup locations and never edits unknown entries. The user can open **Configurações > Aplicativos > Inicialização** to review individual items and the Windows-provided impact indicator. The Lynext does not invent impact ratings. Windows Settings remains the control for activity in the background because support varies by app type and Windows version; restricting activity can delay notifications and synchronization.

Visual effects and accessibility options are linked to native Windows Settings. The Lynext does not change arbitrary visual registry values or accessibility settings. Storage is reported by fixed drive; cleanup is left to Storage Sense/Cleanup recommendations, which preview categories before the user removes them. The Lynext never deletes Downloads, documents, application caches, shader caches, recovery data, or update files.

## Power plan

The shared Power Manager derives all Lynext plans from Balanced and preserves the original Balanced plan. Lite sets screen idle to AC 0/DC 60 minutes, sleep idle to AC 0/DC 60 minutes, and disk idle to AC/DC 0. It does not set CPU minimum or maximum, so those values remain inherited from the Balanced-derived scheme. Values are queried and verified; conflicts, unavailable settings, policy signals, and unsupported output fail closed. The app can restore the previously active plan when its conflict checks pass; it retains the created plans.

## Protected Windows components and Registry

Lite introduces no registry writes, service changes, package/AppX commands, process termination, or external scripts. The central `OptimizationAuthorizationPolicy` is a closed allowlist for the existing Gamer features and shared Power Manager. Lite's diagnostic features do not authorize mutation operations. Store/AppX/licensing, Xbox/Gaming Services/Game Pass/Minecraft, Windows Update, Defender/SmartScreen/Firewall, UAC, networking, audio, USB, printing, drivers, VPN and account synchronization are not modified.

No bulk service recommendations or popular registry tweaks are applied. There is no Lynext cleanup operation; cleanup uses Windows' own preview and selection controls.

## Compatibility and recovery limits

Process path, publisher metadata, WMI, battery sensors, storage availability, and power-setting localization vary by Windows/device. Missing information is reported as unknown or unavailable. Task Manager's startup impact is not reproduced because the supported impact data is not generally exposed through the APIs used here. Individual startup toggles, per-app background permission writes, process close actions, and visual registry writes are intentionally not implemented; native Windows controls are linked where available. Modern Standby/OEM policies can restrict legacy power schemes; actual battery, thermal, startup timing, app notification, and restore behavior still need testing on representative physical Windows devices.

## Sources

- [Configure startup applications in Windows](https://support.microsoft.com/pt-br/windows/experience/startup-boot/configure-startup-applications-in-windows)
- [Tips to improve PC performance in Windows](https://support.microsoft.com/pt-br/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows)
- [Manage drive space with Storage Sense](https://support.microsoft.com/pt-br/windows/experience/storage-filemanagement/manage-drive-space-with-storage-sense)
- [Storage settings in Windows](https://support.microsoft.com/pt-br/windows/experience/storage-filemanagement/storage-settings-in-windows)
- [Launch Windows Settings](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings)
- [Process.TotalProcessorTime](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.totalprocessortime)
- [Manage power schemes](https://learn.microsoft.com/en-us/windows/win32/power/managing-power-schemes)
- [Powercfg command-line options](https://learn.microsoft.com/pt-br/windows-hardware/design/device-experiences/powercfg-command-line-options)

## Tests and validation

Unit tests use constructed process samples and fake power command runners; they do not alter the test machine's Registry, services, processes, or power schemes. They verify CPU sampling math, unknown process handling, explicit unavailable values, profile separation, and power-plan conflict behavior. A CI build and complete test run are required for each source change. Physical-device validation is still needed for WMI/Modern Standby/OEM settings and real startup or resource behavior.

