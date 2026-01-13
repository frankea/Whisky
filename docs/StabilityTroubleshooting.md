# Stability Troubleshooting (Issue #40)

This document is a contributor-facing playbook for triaging **critical stability issues**: crashes, hard freezes, reboots, and kernel panics.

## When to use this

Use this guide for reports like:
- macOS kernel panic / reboot during game launch or gameplay
- Complete system freeze requiring force reboot
- Whisky UI freezes (e.g., opening Bottle Configuration)
- Whisky crashes on launch or during WhiskyWine installation

## Quick mitigations (user-facing)

- **Enable Sequoia Compatibility Mode** (Bottle → Config → Metal): helps with macOS 15.x quirks.
- **Enable Stability Safe Mode** (Bottle → Config → Performance): applies conservative env overrides intended to reduce crash/freeze risk.
- **Disable DXR**: ray tracing can stress graphics paths on some systems.
- **Force D3D11**: can avoid D3D12/D3DMetal paths that trigger instability in some titles.
- **Kill Bottles** (menu item): use if Wine processes are stuck or the UI is unresponsive.

## Collect diagnostics (required for actionable triage)

### 1) Whisky Stability Diagnostics report

1. Open the affected bottle
2. Go to **Config**
3. Click **Generate Stability Diagnostics**
4. Export to file and attach it to the issue

Notes:
- The stability report is **bounded** (safe to share)
- It includes **environment keys only** (no values) to reduce privacy risk

### 2) Wine logs folder

In the app, use **Open Logs** (menu item) and attach the newest `.log` file(s) if requested.

Whisky also enforces log size limits (per-file cap + folder cap) to avoid runaway disk usage.

### 3) macOS crash/panic logs

For **kernel panics / reboots**:
- Collect the panic report from **Console.app** (System Reports / Panic reports)
- Include the exact error string if visible (e.g., `IOMFB int_handler_gated: failure: axi_rd_err`)

## Minimal repro template (paste into issues)

Please include:
- **Mac model** (e.g., M3 Max)
- **macOS version** (e.g., 15.2 / 15.4.1)
- **Whisky version** and **WhiskyWine version**
- **Game/app** and distribution (Steam/GOG/etc.)
- **Bottle settings toggles**: Sequoia compat, Safe Mode, DXVK, Force D3D11, DXR, Enhanced Sync
- **Steps to reproduce** (smallest possible)
- **Expected vs actual**
- Attach **Stability Diagnostics report** and any relevant logs

## Triage guidance (maintainers)

- If the report indicates a **UI freeze** correlated with Wine commands, prioritize investigating main-thread starvation or long-running Wine command aggregation.
- If it’s a **kernel panic**, treat it as likely **driver-level**. Focus on mitigations (Safe Mode / D3D11 / DXR off) and collecting high-quality repro data.
- If it’s a **WhiskyWine install failure**, confirm install is atomic and that errors are surfaced to the UI; validate tarball structure and version plist.

