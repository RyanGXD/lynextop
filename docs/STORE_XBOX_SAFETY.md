# Microsoft Store, Xbox and Windows settings safety

## Audit findings

The desktop profile service on `rebuild/desktop-installer` currently changes only the current user's `AutoGameModeEnabled` value and, after a separate confirmation and positive no-battery detection, the active power scheme. It does not change UAC, Store/Xbox services, Windows policies, or AppX packages. Its backups retain the prior value and its restore path checks for conflicts.

The legacy `PerformanceApp.ps1`, still linked from the root PowerShell menu, exposed batch and manual actions that changed Game DVR/capture, HAGS, Power Throttling, multimedia network and responsiveness values, GPU task priorities, custom power schemes, and NVIDIA power limits. Several operations swallowed errors and still printed success; the generic restore wrote backup values without checking whether the current state had changed. The inspected code contains no `EnableLUA`/UAC modification, Store/Xbox service mutation, AppX removal, or debloat operation. This code establishes a credible risk to Game Bar capture and ambiguous Windows tuning state, but it does not establish the cause of the reported Microsoft Store UAC prompt.

The old performance module is now a warning-only stub. Existing backup files are preserved. Their legacy format records pre-change values but not per-setting applied values or later external changes, so the new diagnostic compares the current state and reports uncertainty; it never restores those legacy values automatically.

## Protection and diagnostics

`OptimizationAuthorizationPolicy` is a closed allowlist used before profile activation and restoration. Only the exact current-user Game Mode value and the exact active power-plan operation are approved. Service, package, external-command, protected UAC/Store/security policy and unknown changes are rejected as a whole. Each approved catalog item documents its justification, preconditions, risks, query, apply and restore behavior.

The Store/Xbox diagnostic reads UAC values, enumerates relevant services with state/start mode/dependencies, queries Store/App Installer/Gaming Services/Xbox packages and recent AppX deployment errors, and checks Lynext histories and legacy backups. Missing services are reported as absent. Demand-start services are not treated as broken just because they are stopped. No Windows settings are modified by diagnosis.

If and only if `EnableLUA` is explicitly observed as DWORD `0` and no organization policy value is present, the UI offers one consented repair: set `EnableLUA=1`, verify the read-back, report the observed old value, log the result, and request a Windows restart. It refuses if the value is absent, has an unexpected type, changed since the report, or is managed by an organization policy. The report includes the detected Windows edition/version/build. No other policy or service repair is automated.

## Limits

No cause has been confirmed from this repository audit alone. The affected PC still needs the diagnostic report and an actual Store installation attempt after any chosen repair/restart. A successful compile does not establish Store or Xbox health.
