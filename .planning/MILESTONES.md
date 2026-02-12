# Milestones

## v1.0 Upstream Issue Resolution (Shipped: 2026-02-12)

**Phases completed:** 10 phases, 50 plans
**Timeline:** 4 days (2026-02-08 to 2026-02-12)
**Stats:** 98 feat commits, 202 files modified, ~59,353 lines Swift
**Git range:** feat(01-01) to feat(10-07)

**Key accomplishments:**
- Unified environment variable cascade via EnvironmentBuilder with 8-layer resolution (Wine defaults through user overrides)
- D3DMetal/DXVK/wined3d graphics backend control with tiered Simple/Advanced UI and per-program overrides
- Crash pattern classification from WINEDEBUG output with remediation suggestions and diagnostic export
- Audio diagnostics with CoreAudio monitoring, step-by-step troubleshooting wizard, and Bluetooth disconnect detection
- 30-entry game compatibility database with one-click apply of known-good configurations
- Launcher fix guidance (Steam/EA/Rockstar/Epic), controller detection with SDL hints, dependency installation tracking
- Process lifecycle management with wineserver-aware tracking, orphan detection, and auto-cleanup
- Guided troubleshooting system: JSON-driven decision tree engine with 8 symptom flows, 15 automated checks, fix preview/apply/undo, and 4 entry points
- Resolution control, bottle duplication, console log persistence, and WhiskyCmd improvements
- 120+ localization entries across diagnostics, game config, and troubleshooting subsystems

---

