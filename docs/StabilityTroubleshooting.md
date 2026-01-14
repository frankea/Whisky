# Feature: Stability Troubleshooting (frankea/Whisky#40)
**Last Updated:** January 13, 2026

---

This document is a contributor-facing playbook for triaging **critical stability issues**: crashes, hard freezes, reboots, and kernel panics.

## When to Use This

Use this guide for reports like:
- macOS kernel panic / reboot during game launch or gameplay
- Complete system freeze requiring force reboot
- Whisky UI freezes (e.g., opening Bottle Configuration)
- Whisky crashes on launch or during WhiskyWine installation

## Quick Mitigations (User-Facing)

- **Enable Sequoia Compatibility Mode** (Bottle → Config → Metal → “Sequoia Compatibility Mode”): helps with macOS 15.x quirks.
- **Disable DXR**: ray tracing can stress graphics paths on some systems.
- **Force D3D11**: can avoid D3D12/D3DMetal paths that trigger instability in some titles.
- **Kill All Bottles** (menu item): terminates Wine processes for all bottles; use when those processes are stuck or the UI is unresponsive.

## Collect Diagnostics (Required for Actionable Triage)

### 1) Stability Diagnostics Report (If Available)

If you're on a build that includes the Stability Diagnostics button (see `frankea/Whisky#56`), collect this report first:

1. Open the affected bottle
2. Go to **Config**
3. If you see a **Stability** section, click **Generate Stability Diagnostics**
4. Export to file and attach it to the issue

If you don't see this button/section, skip this step and attach Wine logs instead (below).

Notes:
- The stability report is **bounded** (safe to share)
- It includes **environment keys only** (no values) to reduce privacy risk

### 2) Wine logs folder

In the app, use **Open Logs Folder** (menu item) and attach the newest `.log` file(s) if requested.

Whisky also enforces log size limits (per-file cap + folder cap) to avoid runaway disk usage.

### 3) macOS crash/panic logs

For **kernel panics / reboots**:
- Collect the panic report from **Console.app** (System Reports / Panic reports)
- Include the exact error string if visible (e.g., `IOMFB int_handler_gated: failure: axi_rd_err`)

## Minimal Repro Template (Paste Into Issues)

Please include:
- **Mac model** (e.g., M3 Max)
- **macOS version** (e.g., 15.2 / 15.4.1)
- **Whisky version** and **WhiskyWine version**
- **Game/app** and distribution (Steam/GOG/etc.)
- **Bottle settings toggles**: Sequoia compat, DXVK, Force D3D11, DXR, Enhanced Sync
- **Steps to reproduce** (smallest possible)
- **Expected vs actual**
- Attach **Stability Diagnostics report** (if available) and any relevant logs

## Triage Guidance (Maintainers)

- If the report indicates a **UI freeze** correlated with Wine commands, prioritize investigating main-thread starvation or long-running Wine command aggregation.
- If it’s a **kernel panic**, treat it as likely **driver-level**. Focus on mitigations (D3D11 / DXR off) and collecting high-quality repro data.
- If it’s a **WhiskyWine install failure**, collect the exact error message, validate tarball structure/version plist, and attach relevant logs.

