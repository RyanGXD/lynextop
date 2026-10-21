# Lynext Power Manager

## Official profiles

The interface and managed Windows schemes use these names: **Lynext Ultra Performance**, **Lynext Gamer**, **Lynext Empresarial**, **Lynext Lite**, and **Lynext Economia**. Internal profile IDs (`gamer-ultra`, `gamer`, `business`, `lite`, `economy`) remain stable so existing settings, backup files, and history entries remain readable.

Selecting a profile is a view operation. The Windows active scheme changes only after the user confirms **Configurar e ativar este plano**. The five custom schemes are derived from the built-in Balanced scheme and are registered in `%LOCALAPPDATA%\Lynext\PowerManager\plans.json`. The plan description includes a Lynext schema/profile marker; the app also checks the persisted GUID and exact expected friendly name. A same-name scheme with another GUID is reported as a collision and is not changed.

## Values

When a plan is first configured, all profiles set screen idle to AC 0 (Never) and DC 60 minutes; automatic sleep to AC 0 and DC 60 minutes; and disk idle to AC/DC 0 (Never). Ultra Performance and Gamer also set CPU minimum and maximum to 100% on AC and DC. Empresarial, Lite, and Economia do not write CPU settings, preserving the values inherited from Balanced. Economia does not claim to enable a device-specific efficiency feature; it offers Windows' native Energy and battery settings.

The disk timer may increase battery use on a notebook with an HDD. A CPU minimum of 100% may increase power use, heat, and fan noise, especially on battery; it is not an overclock and does not guarantee higher FPS.

## Create, configure, activate, restore

The first confirmed activation creates missing Lynext schemes once. Every GUID is saved immediately, so an interrupted creation can resume without adding duplicates. Existing schemes are never deleted or renamed. If a recorded plan is missing, a name collides, or ownership cannot be confirmed, activation stops and reports the problem. The active scheme GUID is captured before the first Lynext activation in `activation-backup.json`. A later restore switches to that GUID only if the currently active GUID still matches the last Lynext scheme; a conflict keeps the backup and makes no change. Lynext schemes and their settings are retained.

The service invokes only fixed `powercfg` operations and fixed Microsoft setting GUIDs. It checks exit codes, queries the setting after writes, and queries the active GUID after activation/restoration. A nonzero exit, unreadable value, permission failure, or mismatch does not report success. Settings backups are saved before values are changed. The app checks known machine power policy keys and fails closed when a policy is detected or the check itself fails. Selection never starts commands. The current app does not silently elevate; permission failures are surfaced for the user to handle.

## Compatibility and limits

Microsoft documents that Modern Standby systems use Balanced or plans derived from Balanced. Lynext therefore duplicates Balanced rather than replacing it. Modern Standby detection and the underlying device's policy can vary; powercfg accepting a command alone is not proof that the hardware honors the setting. Device policy, manufacturer firmware, and group policy can restrict settings. An unavailable or localized `powercfg` query can leave values unconfirmed; the app reports unknown rather than claiming success. Actual Modern Standby behavior, battery discharge, thermal response, and OEM restrictions require validation on representative Windows hardware. No Windows services, Store/Xbox/AppX, UAC, Defender, firewall, update, drivers, network, USB, printing, or audio policies are changed.

## Verification

Automated tests validate official names with stable IDs, common AC/DC values, CPU values only on the two gaming profiles, unknown-profile denial, selection being mutation-free, simulated one-time creation, Balanced preservation, external name collision, manual-change conflict handling, command failure, and restoration. Power-manager integration tests use a simulated `powercfg` runner and a temporary test data directory; they do not modify the test machine's power plans. Windows integration behavior must be verified in a disposable Windows VM or test device before broad rollout.

## Microsoft references

- [Powercfg command-line options](https://learn.microsoft.com/pt-br/windows-hardware/design/device-experiences/powercfg-command-line-options)
- [Power policy settings and Modern Standby plan support](https://learn.microsoft.com/en-us/windows/win32/power/power-policy-settings)
- [Power scheme management](https://learn.microsoft.com/en-us/windows/win32/power/managing-power-schemes)
- [PowerDuplicateScheme](https://learn.microsoft.com/en-us/windows/win32/api/powrprof/nf-powrprof-powerduplicatescheme)
- [Windows 11 power settings](https://support.microsoft.com/pt-br/windows/experience/power-battery/power-settings-in-windows-11)

