# Roadmap: Whisky Upstream Issue Resolution

## Overview

This roadmap delivers systematic resolution of 435+ upstream issues across 10 phases, starting with in-progress miscellaneous fixes and building through configuration foundation, graphics/audio/process management features, game compatibility, platform-specific fixes, and culminating in an integrated guided troubleshooting system. The configuration foundation (Phase 2) is the critical enabler: graphics, audio, game compatibility, and troubleshooting all depend on a clean environment variable cascade. Phases 3-4 (Process Lifecycle and Graphics Config) are parallel-capable after the foundation is in place.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Miscellaneous Fixes** - Close out PR #79 with ClickOnce, clipboard, temp files, and process cleanup
- [x] **Phase 2: Configuration Foundation** - Unify environment variable cascade into explicit EnvironmentBuilder
- [x] **Phase 3: Process Lifecycle Management** - Wineserver-level tracking with orphan detection and auto-cleanup
- [x] **Phase 4: Graphics Configuration** - D3DMetal/DXVK/wined3d backend control with tiered UI
- [x] **Phase 5: Stability & Diagnostics** - WINEDEBUG parsing and crash pattern classification
- [x] **Phase 6: Audio Troubleshooting** - Diagnostics-first audio remediation with limited settings
- [x] **Phase 7: Game Compatibility Database** - Bundled known-good configurations with one-click apply
- [ ] **Phase 8: Remaining Platform Issues** - Launcher, controller, and installation fixes
- [ ] **Phase 9: UI/UX & Feature Requests** - Polish and top community-requested features
- [ ] **Phase 10: Guided Troubleshooting** - Data-driven symptom/solution engine integrating all phases

## Phase Details

### Phase 1: Miscellaneous Fixes
**Goal**: In-progress PR #79 work is complete, delivering ClickOnce support, clipboard safety, temp file cleanup, and basic process resource management
**Depends on**: Nothing (in-progress work, close first)
**Requirements**: MISC-01, MISC-02, MISC-03, MISC-04
**Success Criteria** (what must be TRUE):
  1. ClickOnce applications can be deployed and managed within Whisky bottles
  2. Multiplayer games with rapid clipboard access (e.g., Risk of Rain 2) no longer trigger UI freezes
  3. Temporary files are automatically cleaned up when a bottle is closed or Whisky quits
  4. Zombie Wine processes do not accumulate after programs exit
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md -- WhiskyKit backend: fix ClickOnce username, refactor ClipboardManager result pattern, add per-bottle cleanup settings
- [x] 01-02-PLAN.md -- ClickOnce UI: surface apps in Programs list with badge, context menu, auto-detection
- [x] 01-03-PLAN.md -- Clipboard + lifecycle wiring: pre-launch clipboard check, temp file tracking, AppDelegate cleanup hooks, ConfigView settings

### Phase 2: Configuration Foundation
**Goal**: Environment variable cascade is explicit, conflict-free, and extensible so all downstream configuration features (graphics, audio, game profiles) build on a stable base
**Depends on**: Nothing (foundation work)
**Requirements**: CFGF-01, CFGF-02, CFGF-03, CFGF-04
**Success Criteria** (what must be TRUE):
  1. Environment variable precedence across all layers (Wine defaults, macOS fixes, bottle settings, launcher presets, game profiles, program settings, user overrides) is enforced by a single EnvironmentBuilder with documented layer ordering
  2. Programs can have per-program DLL override entries (WINEDLLOVERRIDES) that take effect at launch
  3. Programs track which winetricks verbs have been applied, visible in program settings
  4. No conflicting merge strategies exist between MacOSCompatibility, BottleSettings, and LauncherPresets -- a single code path resolves all layers
**Plans**: 4 plans

Plans:
- [x] 02-01-PLAN.md -- Core data models: EnvironmentBuilder, DLL override resolver, ProgramOverrides (TDD)
- [x] 02-02-PLAN.md -- Refactor environment construction to EnvironmentBuilder with 8-layer resolution
- [x] 02-03-PLAN.md -- Winetricks verb tracking: cache, discovery, and WinetricksView installed filter
- [x] 02-04-PLAN.md -- DLL override editor UI and per-program override settings

### Phase 3: Process Lifecycle Management
**Goal**: Users have accurate visibility into Wine process state per bottle and can manage the full process lifecycle from the UI
**Depends on**: Nothing (independent of configuration cascade; process tracking is OS-level)
**Requirements**: PROC-01, PROC-02, PROC-03, PROC-04, PROC-05
**Success Criteria** (what must be TRUE):
  1. ProcessRegistry tracks wineserver PID per WINEPREFIX, reflecting actual bottle-level process state rather than individual Wine child PIDs
  2. Orphan Wine processes are detected and the user is prompted with cleanup options
  3. Closing a bottle or quitting Whisky terminates associated Wine processes automatically via wineserver integration
  4. RunningProcessesView shows live, wineserver-aware process status with real-time updates
  5. User can force-kill individual Wine processes or all processes in a bottle from the UI
**Plans**: 3 plans

Plans:
- [x] 03-01-PLAN.md -- Core process types (WineProcess, ProcessKind), Wine helpers (wineserver probe, tasklist parsing, taskkill), ProcessRegistry enhancements
- [x] 03-02-PLAN.md -- ProcessesViewModel with hybrid polling and full Processes page UI (Table, toolbar, filters, context menus, shutdown orchestration)
- [x] 03-03-PLAN.md -- Running indicators in sidebar, startup orphan detection, pre-deletion process checks, enhanced quit behavior

### Phase 4: Graphics Configuration
**Goal**: Users can control graphics backend selection and DXVK settings per bottle and per program through a clear, tiered UI that avoids settings overload
**Depends on**: Phase 2 (graphics settings flow through EnvironmentBuilder cascade)
**Requirements**: GFXC-01, GFXC-02, GFXC-03, GFXC-04, GFXC-05
**Success Criteria** (what must be TRUE):
  1. User can toggle between D3DMetal, DXVK, and wined3d graphics backends per bottle from the settings UI
  2. Graphics settings UI presents a Simple mode by default with an Advanced toggle for power users
  3. DXVK-specific settings (async shader compilation, HUD overlay) are configurable per bottle in Advanced mode
  4. Per-program graphics backend override is available and takes precedence over the bottle-level setting
  5. DXVK configuration file is managed through the UI with user-editable settings exposed
**Plans**: 3 plans

Plans:
- [x] 04-01-PLAN.md -- GraphicsBackend data model, BottleGraphicsConfig, GraphicsBackendResolver, BottleSettings integration, ProgramOverrides extension, WineEnvironment update
- [x] 04-02-PLAN.md -- BackendPickerView selection cards, GraphicsConfigSection with Simple/Advanced toggle, DXVKSettingsView, dxvk.conf management, ConfigView integration
- [x] 04-03-PLAN.md -- Per-program graphics override in ProgramOverrideSettingsView, per-program override notes in GraphicsConfigSection, program list badge

### Phase 5: Stability & Diagnostics
**Goal**: Wine error output is automatically classified so users receive actionable crash guidance instead of raw logs
**Depends on**: Phase 3 (process tracking provides context for which process generated errors)
**Requirements**: STAB-01, STAB-02, STAB-03, STAB-04
**Success Criteria** (what must be TRUE):
  1. WINEDEBUG output is parsed and classified into categories: access violations, GPU errors, DLL load failures, and other patterns
  2. Known crash patterns are matched to specific remediation suggestions displayed to the user
  3. GPU-specific crash patterns (IOMFB faults, Metal compilation errors) produce targeted troubleshooting guidance
  4. Diagnostic report exports include a classified error summary section alongside the raw log
**Plans**: 5 plans

Plans:
- [x] 05-01-PLAN.md -- Core classifier pipeline: CrashPattern types, CrashClassifier, patterns.json, remediations.json, WineDebugPreset, unit tests (TDD)
- [x] 05-02-PLAN.md -- Persistence and export: DiagnosisHistory, RemediationTimeline, Redactor, DiagnosticExporter (ZIP + Markdown)
- [x] 05-03-PLAN.md -- Process integration: WINEDEBUG preset injection via EnvironmentBuilder, auto-trigger classification on process exit
- [x] 05-04-PLAN.md -- Core diagnostics UI: DiagnosticsView split layout, RemediationCardView, LogViewerView (NSTextView)
- [x] 05-05-PLAN.md -- Export UI, diagnosis history, entry points (Program settings, Bottle settings, Help menu), localization

### Phase 6: Audio Troubleshooting
**Goal**: Users can diagnose and address common macOS Wine audio problems through in-app diagnostics and a focused set of effective settings (max 3-4)
**Depends on**: Phase 2 (audio settings flow through EnvironmentBuilder cascade)
**Requirements**: AUDT-01, AUDT-02, AUDT-03, AUDT-04
**Success Criteria** (what must be TRUE):
  1. User can view CoreAudio device detection status and current sample rate information within Whisky
  2. An in-app audio troubleshooting guide walks users through step-by-step remediation for common issues (crackling, missing sound, stuttering)
  3. Up to 3-4 audio-related Wine settings (FAudio/dsound selection, sample rate override) are configurable per bottle
  4. Audio diagnostics panel detects Bluetooth device disconnects and sample rate mismatches with specific guidance
**Plans**: 5 plans

Plans:
- [x] 06-01-PLAN.md -- Audio device data models, CoreAudio monitoring, and unit tests (TDD)
- [x] 06-02-PLAN.md -- BottleAudioConfig, BottleSettings integration, Wine audio registry helpers
- [x] 06-03-PLAN.md -- Audio probes (CoreAudio, Wine registry, test exe), troubleshooting engine state machine
- [x] 06-04-PLAN.md -- Audio section UI (status, test buttons, Simple/Advanced settings, findings)
- [x] 06-05-PLAN.md -- Troubleshooting wizard UI, device change alerts, deep-links, localization

### Phase 7: Game Compatibility Database
**Goal**: Users can look up known-good configurations for common games and apply them with one click, reducing trial-and-error configuration
**Depends on**: Phase 2 (game profiles apply via EnvironmentBuilder), Phase 4 (graphics settings are the primary configuration axis for games)
**Requirements**: GAME-01, GAME-02, GAME-03, GAME-04
**Success Criteria** (what must be TRUE):
  1. A bundled JSON database contains verified configurations for 20-50 commonly reported games, indexed by executable name and Steam App ID
  2. User can view per-game troubleshooting notes and recommended settings from within the app
  3. One-click "Apply recommended configuration" sets environment variables, DLL overrides, and winetricks verbs for a matched game
  4. Compatibility entries display version tuples (Wine version, macOS version, last verified date) with staleness warnings for outdated data
**Plans**: 7 plans

Plans:
- [ ] 07-01-PLAN.md -- Core data models: GameDBEntry, CompatibilityRating, MatchResult, GameConfigSnapshot, SteamAppManifest (TDD)
- [ ] 07-02-PLAN.md -- GameDBLoader JSON resource loading and GameMatcher tiered scoring algorithm (TDD)
- [ ] 07-03-PLAN.md -- GameConfigApplicator apply/revert/snapshot and StalenessChecker
- [ ] 07-04-PLAN.md -- GameConfigurationView global list with search, filters, and BottleView navigation
- [ ] 07-05-PLAN.md -- GameEntryDetailView 6-section layout, GameConfigPreviewSheet with diff, GameVariantPickerView
- [ ] 07-06-PLAN.md -- Contextual integration: banners, program settings suggestions, config revert, localization
- [ ] 07-07-PLAN.md -- GameDB.json population with 25-30 verified game configuration entries

### Phase 8: Remaining Platform Issues
**Goal**: Launcher, controller, and installation issues from upstream tracking categories are resolved through code fixes and in-app guidance
**Depends on**: Phase 2 (launcher workaround configs use environment cascade)
**Requirements**: LNCH-01, LNCH-02, LNCH-03, LNCH-04, CTRL-01, CTRL-02, CTRL-03, CTRL-04, INST-01, INST-02, INST-03
**Success Criteria** (what must be TRUE):
  1. Steam download stalls are detected with in-app guidance to change download region or restart steamwebhelper
  2. macOS 15.4+ launcher compatibility issues (Steam, EA, Rockstar) have documented workarounds accessible in-app
  3. Controller detection persists across sessions without requiring Mac reboot, and per-controller mapping works for DualShock 4, DualSense, and Xbox controllers
  4. In-app dependency installation guide covers DirectX, .NET Framework, and vcruntime with per-bottle status tracking showing what is installed
  5. Permission flow improvements reduce repeated volume access prompts during bottle and program operations
**Plans**: TBD

Plans:
- [ ] 08-01: TBD
- [ ] 08-02: TBD
- [ ] 08-03: TBD
- [ ] 08-04: TBD

### Phase 9: UI/UX & Feature Requests
**Goal**: Polish and feature enhancements that improve daily usability and address top community-requested capabilities
**Depends on**: Phase 2 (configuration foundation for feature settings), Phase 3 (process management for App Nap and console persistence)
**Requirements**: UIUX-01, UIUX-02, UIUX-03, UIUX-04, FEAT-01, FEAT-02, FEAT-03, FEAT-04
**Success Criteria** (what must be TRUE):
  1. GPTK update dialog is streamlined to a single confirmation step without an unnecessary extra dialog
  2. Desktop shortcuts and terminal commands handle paths with spaces correctly, and WhiskyCmd reliably launches apps with visible output
  3. User can toggle App Nap management per bottle and duplicate an existing bottle for experimentation
  4. User can change display resolution for Windows apps, and console output persists after program termination for diagnostic review
  5. Build Version and Retina Mode display actual values instead of "N/A" in bottle settings
**Plans**: TBD

Plans:
- [ ] 09-01: TBD
- [ ] 09-02: TBD
- [ ] 09-03: TBD

### Phase 10: Guided Troubleshooting
**Goal**: Users can navigate interactive, data-driven troubleshooting flows that diagnose and resolve common issues by integrating diagnostics, compatibility data, and configuration from all previous phases
**Depends on**: Phase 4 (graphics config), Phase 5 (stability diagnostics), Phase 6 (audio diagnostics), Phase 7 (game compatibility data)
**Requirements**: TRBL-01, TRBL-02, TRBL-03, TRBL-04, TRBL-05
**Success Criteria** (what must be TRUE):
  1. A data-driven troubleshooting engine loads symptom/solution decision trees from bundled JSON without hardcoded logic
  2. Troubleshooting guides for graphics issues (black screen, artifacts, low FPS) are navigable in-app with step-by-step flows
  3. Troubleshooting guides for audio issues (crackling, missing sound, stuttering) are navigable in-app with step-by-step flows
  4. Troubleshooting guides for launcher issues (Steam, EA, Rockstar, Epic) are navigable in-app with step-by-step flows
  5. Guides include automated diagnostic checks that verify current settings, check file existence, and match log patterns before suggesting manual steps
**Plans**: TBD

Plans:
- [ ] 10-01: TBD
- [ ] 10-02: TBD
- [ ] 10-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10
Note: Phases 3 and 4 are parallel-capable (no mutual dependencies). Phases 5 and 6 are parallel-capable.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Miscellaneous Fixes | 3/3 | ✓ Complete | 2026-02-09 |
| 2. Configuration Foundation | 4/4 | ✓ Complete | 2026-02-09 |
| 3. Process Lifecycle Management | 3/3 | ✓ Complete | 2026-02-09 |
| 4. Graphics Configuration | 3/3 | ✓ Complete | 2026-02-09 |
| 5. Stability & Diagnostics | 5/5 | ✓ Complete | 2026-02-10 |
| 6. Audio Troubleshooting | 5/5 | ✓ Complete | 2026-02-10 |
| 7. Game Compatibility Database | 7/7 | ✓ Complete | 2026-02-10 |
| 8. Remaining Platform Issues | 0/TBD | Not started | - |
| 9. UI/UX & Feature Requests | 0/TBD | Not started | - |
| 10. Guided Troubleshooting | 0/TBD | Not started | - |
