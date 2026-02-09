# Requirements: Whisky Upstream Issue Resolution

**Defined:** 2026-02-08
**Core Value:** Every tracking issue (#40-#50) has a concrete response — code fix, configuration UI, or in-app guidance

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Configuration Foundation

- [ ] **CFGF-01**: Environment variable precedence is explicit and documented across Wine defaults, macOS fixes, bottle settings, launcher presets, game profiles, program settings, and user overrides
- [ ] **CFGF-02**: Conflicting override strategies in MacOSCompatibility, BottleSettings, and LauncherPresets are refactored into a single EnvironmentBuilder
- [ ] **CFGF-03**: ProgramSettings supports DLL override entries (WINEDLLOVERRIDES per-program)
- [ ] **CFGF-04**: ProgramSettings supports winetricks verb tracking per-program

### Graphics Configuration

- [ ] **GFXC-01**: User can toggle between D3DMetal, DXVK, and wined3d graphics backends per bottle
- [ ] **GFXC-02**: Graphics settings UI uses tiered Simple/Advanced layout to avoid overwhelming users
- [ ] **GFXC-03**: User can configure DXVK-specific settings (async shader compilation, HUD) per bottle
- [ ] **GFXC-04**: User can override graphics backend per program (overrides bottle-level setting)
- [ ] **GFXC-05**: DXVK config file management with user-editable settings exposed in UI

### Audio Troubleshooting

- [ ] **AUDT-01**: User can view CoreAudio device detection status and sample rate information in-app
- [ ] **AUDT-02**: User can access in-app audio troubleshooting guide with step-by-step remediation
- [ ] **AUDT-03**: User can configure up to 3-4 audio-related Wine settings per bottle (FAudio/dsound selection, sample rate override)
- [ ] **AUDT-04**: Audio diagnostics panel detects Bluetooth device disconnects and sample rate mismatches

### Process Management

- [ ] **PROC-01**: ProcessRegistry tracks wineserver PID per WINEPREFIX for accurate bottle-level lifecycle awareness
- [ ] **PROC-02**: Orphan Wine processes are detected and user is prompted to clean them up
- [ ] **PROC-03**: Wine processes auto-terminate when user closes a bottle or quits Whisky
- [ ] **PROC-04**: RunningProcessesView shows live process status with wineserver-aware tracking
- [ ] **PROC-05**: User can force-kill individual Wine processes or all processes in a bottle

### Stability & Diagnostics

- [ ] **STAB-01**: WINEDEBUG error patterns are parsed and classified from Wine output (access violations, GPU errors, DLL load failures)
- [ ] **STAB-02**: Known crash patterns are detected and matched to suggested remediation steps
- [ ] **STAB-03**: GPU crash pattern detection provides specific guidance for IOMFB and Metal errors
- [ ] **STAB-04**: Diagnostic reports include classified error summary alongside raw logs

### Game Compatibility

- [ ] **GAME-01**: Bundled JSON database contains known-good configurations for top 20-50 commonly reported games
- [ ] **GAME-02**: User can view per-game troubleshooting notes and recommended settings from the compatibility database
- [ ] **GAME-03**: User can apply recommended game configuration with one click (sets env vars, DLL overrides, winetricks)
- [ ] **GAME-04**: Compatibility entries include version tuples (Wine version, macOS version) with staleness warnings

### Guided Troubleshooting

- [ ] **TRBL-01**: Data-driven troubleshooting engine loads symptom/solution mappings from JSON
- [ ] **TRBL-02**: User can navigate troubleshooting guides for graphics issues (black screen, artifacts, low FPS)
- [ ] **TRBL-03**: User can navigate troubleshooting guides for audio issues (crackling, missing sound, stuttering)
- [ ] **TRBL-04**: User can navigate troubleshooting guides for launcher issues (Steam, EA, Rockstar, Epic)
- [ ] **TRBL-05**: Troubleshooting guides include automated diagnostic checks (setting verification, file existence, log pattern matching)

### Remaining Launcher Issues

- [ ] **LNCH-01**: Steam download stall detection with guidance to change download region or restart
- [ ] **LNCH-02**: macOS 15.4+ Steam compatibility documented with workaround guidance
- [ ] **LNCH-03**: EA App troubleshooting guidance with known working configuration
- [ ] **LNCH-04**: Rockstar Games Launcher troubleshooting guidance with LauncherPatcher.exe recommendation

### Remaining Controller Issues

- [ ] **CTRL-01**: Controller detection persists across sessions without requiring Mac reboot
- [ ] **CTRL-02**: Microphone permission request flow implemented for apps requiring mic access
- [ ] **CTRL-03**: Per-controller mapping improvements for DualShock 4, DualSense, and Xbox controllers
- [ ] **CTRL-04**: Retina mode mouse position scaling fix for fullscreen games

### Remaining Installation Issues

- [ ] **INST-01**: In-app dependency installation guide for DirectX, .NET Framework, and vcruntime
- [ ] **INST-02**: Permission flow improvements to reduce repeated volume access prompts
- [ ] **INST-03**: Dependency installation status tracking showing what's installed per bottle

### Remaining UI/UX

- [ ] **UIUX-01**: GPTK update dialog simplified to remove unnecessary extra confirmation step
- [ ] **UIUX-02**: Desktop shortcut creation handles paths with spaces correctly
- [ ] **UIUX-03**: WhiskyCmd improvements for reliable app launching and output display
- [ ] **UIUX-04**: Build Version and Retina Mode show actual values instead of "N/A"

### Feature Requests

- [ ] **FEAT-01**: User can toggle App Nap management per bottle for improved stability
- [ ] **FEAT-02**: User can duplicate an existing bottle for experimentation
- [ ] **FEAT-03**: User can change display resolution for Windows apps
- [ ] **FEAT-04**: Console output persists after program termination for diagnostic review

### Miscellaneous

- [ ] **MISC-01**: ClickOnceManager handles ClickOnce application deployment and management
- [ ] **MISC-02**: Clipboard handling prevents freezes in multiplayer games (Risk of Rain 2 pattern)
- [ ] **MISC-03**: Temp file cleanup runs automatically on bottle close or app quit
- [ ] **MISC-04**: Wine process cleanup automation prevents resource leaks from zombie processes

## v2 Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Community Features

- **COMM-01**: Community-contributed game compatibility reports (ProtonDB-style)
- **COMM-02**: Shared winetricks preset library
- **COMM-03**: Remote game configuration sync

### Advanced Features

- **ADVF-01**: VR/OpenXR passthrough to host OS
- **ADVF-02**: HDR display support
- **ADVF-03**: Steam Remote Play integration
- **ADVF-04**: Force Feedback controller support

## Out of Scope

| Feature | Reason |
|---------|--------|
| Wine/GPTK source code patches | Whisky consumes Wine binaries, doesn't build them |
| DXMT compilation/bundling | Separate project; include if available upstream |
| Anti-cheat compatibility (Denuvo, EAC) | Kernel-level, not solvable in app layer |
| Kernel-mode driver support | macOS limitation |
| Game-specific Wine patches | Wine/Proton upstream responsibility |
| Full community compat database | Decays fast, tiny macOS contributor base; use curated JSON instead |
| Mobile app | Web/desktop focus for this milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CFGF-01 | Phase 2 | Pending |
| CFGF-02 | Phase 2 | Pending |
| CFGF-03 | Phase 2 | Pending |
| CFGF-04 | Phase 2 | Pending |
| GFXC-01 | Phase 4 | Pending |
| GFXC-02 | Phase 4 | Pending |
| GFXC-03 | Phase 4 | Pending |
| GFXC-04 | Phase 4 | Pending |
| GFXC-05 | Phase 4 | Pending |
| AUDT-01 | Phase 6 | Pending |
| AUDT-02 | Phase 6 | Pending |
| AUDT-03 | Phase 6 | Pending |
| AUDT-04 | Phase 6 | Pending |
| PROC-01 | Phase 3 | Pending |
| PROC-02 | Phase 3 | Pending |
| PROC-03 | Phase 3 | Pending |
| PROC-04 | Phase 3 | Pending |
| PROC-05 | Phase 3 | Pending |
| STAB-01 | Phase 5 | Pending |
| STAB-02 | Phase 5 | Pending |
| STAB-03 | Phase 5 | Pending |
| STAB-04 | Phase 5 | Pending |
| GAME-01 | Phase 7 | Pending |
| GAME-02 | Phase 7 | Pending |
| GAME-03 | Phase 7 | Pending |
| GAME-04 | Phase 7 | Pending |
| TRBL-01 | Phase 10 | Pending |
| TRBL-02 | Phase 10 | Pending |
| TRBL-03 | Phase 10 | Pending |
| TRBL-04 | Phase 10 | Pending |
| TRBL-05 | Phase 10 | Pending |
| LNCH-01 | Phase 8 | Pending |
| LNCH-02 | Phase 8 | Pending |
| LNCH-03 | Phase 8 | Pending |
| LNCH-04 | Phase 8 | Pending |
| CTRL-01 | Phase 8 | Pending |
| CTRL-02 | Phase 8 | Pending |
| CTRL-03 | Phase 8 | Pending |
| CTRL-04 | Phase 8 | Pending |
| INST-01 | Phase 8 | Pending |
| INST-02 | Phase 8 | Pending |
| INST-03 | Phase 8 | Pending |
| UIUX-01 | Phase 9 | Pending |
| UIUX-02 | Phase 9 | Pending |
| UIUX-03 | Phase 9 | Pending |
| UIUX-04 | Phase 9 | Pending |
| FEAT-01 | Phase 9 | Pending |
| FEAT-02 | Phase 9 | Pending |
| FEAT-03 | Phase 9 | Pending |
| FEAT-04 | Phase 9 | Pending |
| MISC-01 | Phase 1 | Pending |
| MISC-02 | Phase 1 | Pending |
| MISC-03 | Phase 1 | Pending |
| MISC-04 | Phase 1 | Pending |

**Coverage:**
- v1 requirements: 54 total
- Mapped to phases: 54
- Unmapped: 0

---
*Requirements defined: 2026-02-08*
*Last updated: 2026-02-08 after roadmap creation*
