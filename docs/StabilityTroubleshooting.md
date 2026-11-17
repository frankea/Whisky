# Stability Troubleshooting Guide

**Feature:** Stability Troubleshooting (frankea/Whisky#40)  
**Last Updated:** November 16, 2026

---

This document is a contributor-facing playbook for triaging **critical stability issues**: crashes, hard freezes, reboots, and kernel panics.

## When to Use This

Use this guide for reports like:
- macOS kernel panic / reboot during game launch or gameplay
- Complete system freeze requiring force reboot
- Whisky UI freezes (e.g., opening Bottle Configuration)
- Whisky crashes on launch or during WhiskyWine installation

## Quick Mitigations (User-Facing)

- **macOS 15.x fixes are automatic:** Whisky applies its macOS 15.3 and 15.4 fixes on every launch; there is no setting to turn on.
- **Disable DXR** (Bottle Configuration > Graphics > Advanced > Metal > DirectX Raytracing; off by default and only shown on Macs with hardware ray tracing): ray tracing can stress graphics paths on some systems.
- **Kill All Bottles** (File menu, Shift-Command-K, and the Whisky menu bar item when **Show Whisky in the menu bar** is on in Settings): terminates Wine processes for all bottles; use when those processes are stuck or the UI is unresponsive. To stop one bottle, use **Stop Bottle** on its **Running Processes** page, or click the orange mark the sidebar shows next to a bottle whose processes were started outside Whisky.

## Collect Diagnostics (Required for Actionable Triage)

### 0) Crash diagnosis (for crashes)

After a program crashes, open the bottle's **Bottle Configuration** > **Diagnostics** and use **View Latest Diagnosis** or **Export Diagnostic Report…** (a ZIP; leave **Include sensitive details** off). Help > **Run Diagnostics…** (Shift-Command-D) analyzes any program's last log, and **Start Guided Troubleshooting** walks through checks for common symptoms.

### 1) Stability Diagnostics Report

1. Open the affected bottle
2. Go to **Bottle Configuration**
3. In the **Stability** section, click **Generate Stability Diagnostics**
4. Click **Export to File** and attach it to the issue

Notes:
- The stability report is **bounded**: the environment section lists variable names only, and the log section is limited to the last 200 lines of the newest log
- It includes the logs folder path and that log tail as written, so look it over for personal paths or details before attaching it

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
- **Bottle settings**: Graphics Backend, DirectX Raytracing, Enhanced Sync, and whether Game Porting Toolkit is imported
- **Steps to reproduce** (smallest possible)
- **Expected vs actual**
- Attach **Stability Diagnostics report** and any relevant logs

## Triage Guidance (Maintainers)

- If the report indicates a **UI freeze** correlated with Wine commands, prioritize investigating main-thread starvation or long-running Wine command aggregation.
- If it’s a **kernel panic**, treat it as likely **driver-level**. Focus on mitigations (DXR off, a different graphics backend) and collecting high-quality repro data.
- If it’s a **WhiskyWine install failure**, ask for the text from **Copy Diagnostics** on the setup error screen. If setup says a network filter or sign-in page answered instead of the download, the user needs to allow the sites it names. A failed update leaves the current runtime in place and is offered again at the next launch.

