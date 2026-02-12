# Whisky Upstream Issue Resolution

## What This Is

A systematically enhanced fork of whisky-app/whisky that addresses all 435+ upstream issues across 10 tracking categories (#40-#50). Delivers unified configuration management, graphics/audio/process controls, game compatibility database, stability diagnostics, and an integrated guided troubleshooting system. The fork is a meaningfully better Whisky than the unmaintained upstream across every issue category.

## Core Value

Every tracking issue (#40-#50) has a concrete response — whether that's a code fix, a configuration UI, or in-app guidance — so no upstream problem goes unaddressed.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Stability diagnostics export for crash/freeze triage — PR #56
- ✓ Wine log capping to prevent disk fill (187GB+ logs) — PR #54
- ✓ Wine prefix repair button for corrupted prefixes — PR #66
- ✓ Launcher compatibility mode with auto-detection (Steam, Epic, GOG, EA, Ubisoft, Rockstar) — PR #53
- ✓ Wine upgrade from 7.7 to 11.0 fixing steamwebhelper — PR #53
- ✓ Controller compatibility SDL settings (HIDAPI, background events, mapping) — PR #74
- ✓ Bottle creation error surfacing with diagnostics — PR #62
- ✓ WhiskyWine download diagnostics with copy-to-clipboard — PR #65
- ✓ Wine prefix validation before winetricks — PR #66
- ✓ Launch feedback toast notifications — PR #67
- ✓ Missing English translations for localization fallback — PR #69
- ✓ Archive progress with toast notifications — PR #75
- ✓ Greyed-out bottle warning icon and quick remove — PR #75
- ✓ IconCache for faster program list loading — PR #75
- ✓ Terminal launch command escaping fix — PR #73
- ✓ WhiskyCmd run command and config retry UX — PR #77
- ✓ Feature requests implementation batch — PR #76
- ✓ Shared program launch logic refactor — PR #70
- ✓ WhiskyKit test coverage at 83% — PR #78
- ✓ SwiftFormat integration — PR #38
- ✓ DocC documentation for WhiskyKit public API — PR #37
- ✓ os.log Logger replacing print statements — PR #32
- ✓ Large file refactoring — PR #33
- ✓ Proper @MainActor thread safety — PR #27
- ✓ CI consolidation with test execution — PR #28
- ✓ macOS 15 deployment target — PR #39
- ✓ CFGF-01: EnvironmentBuilder with 8-layer resolution — v1.0
- ✓ CFGF-02: Single EnvironmentBuilder code path resolving all layers — v1.0
- ✓ CFGF-03: Per-program DLL override entries (WINEDLLOVERRIDES) — v1.0
- ✓ CFGF-04: Per-program winetricks verb tracking — v1.0
- ✓ GFXC-01: D3DMetal/DXVK/wined3d backend control per bottle — v1.0
- ✓ GFXC-02: Tiered Simple/Advanced graphics settings UI — v1.0
- ✓ GFXC-03: DXVK async shader compilation and HUD per bottle — v1.0
- ✓ GFXC-04: Per-program graphics backend override — v1.0
- ✓ GFXC-05: DXVK config file management via UI — v1.0
- ✓ PROC-01: ProcessRegistry with wineserver PID per WINEPREFIX — v1.0
- ✓ PROC-02: Orphan Wine process detection with cleanup prompts — v1.0
- ✓ PROC-03: Auto-terminate Wine processes on bottle close/app quit — v1.0
- ✓ PROC-04: RunningProcessesView with live wineserver-aware tracking — v1.0
- ✓ PROC-05: Force-kill individual or all Wine processes from UI — v1.0
- ✓ STAB-01: WINEDEBUG output parsing and classification — v1.0
- ✓ STAB-02: Crash pattern matching with remediation suggestions — v1.0
- ✓ STAB-03: GPU-specific crash pattern detection (IOMFB, Metal) — v1.0
- ✓ STAB-04: Diagnostic report exports with classified error summary — v1.0
- ✓ AUDT-01: CoreAudio device detection status and sample rate display — v1.0
- ✓ AUDT-02: In-app audio troubleshooting guide with step-by-step remediation — v1.0
- ✓ AUDT-03: Audio Wine settings per bottle (FAudio/dsound, sample rate) — v1.0
- ✓ AUDT-04: Bluetooth disconnect and sample rate mismatch detection — v1.0
- ✓ GAME-01: 30-entry bundled game compatibility database — v1.0
- ✓ GAME-02: Per-game troubleshooting notes and recommended settings — v1.0
- ✓ GAME-03: One-click apply recommended game configuration — v1.0
- ✓ GAME-04: Version tuples with staleness warnings for compatibility entries — v1.0
- ✓ LNCH-01: Steam download stall detection with guidance — v1.0
- ✓ LNCH-02: macOS 15.4+ Steam compatibility workaround guidance — v1.0
- ✓ LNCH-03: EA App troubleshooting guidance with known working config — v1.0
- ✓ LNCH-04: Rockstar Games Launcher troubleshooting guidance — v1.0
- ✓ CTRL-01: Controller detection persistence across sessions — v1.0
- ✓ CTRL-02: Microphone permission request flow — v1.0
- ✓ CTRL-03: Per-controller mapping for DualShock 4, DualSense, Xbox — v1.0
- ✓ CTRL-04: Retina mode mouse position scaling — v1.0
- ✓ INST-01: In-app dependency installation guide (DirectX, .NET, vcruntime) — v1.0
- ✓ INST-02: Permission flow improvements for volume access — v1.0
- ✓ INST-03: Dependency installation status tracking per bottle — v1.0
- ✓ UIUX-01: GPTK update dialog simplified to single confirmation step — v1.0
- ✓ UIUX-02: Desktop shortcuts handle paths with spaces — v1.0
- ✓ UIUX-03: WhiskyCmd improvements for reliable app launching — v1.0
- ✓ UIUX-04: Build Version and Retina Mode show actual values — v1.0
- ✓ FEAT-01: App Nap management per bottle — v1.0
- ✓ FEAT-02: Bottle duplication for experimentation — v1.0
- ✓ FEAT-03: Display resolution control for Windows apps — v1.0
- ✓ FEAT-04: Console output persistence after program termination — v1.0
- ✓ MISC-01: ClickOnce application deployment and management — v1.0
- ✓ MISC-02: Clipboard handling prevents multiplayer game freezes — v1.0
- ✓ MISC-03: Automatic temp file cleanup on bottle close/app quit — v1.0
- ✓ MISC-04: Wine process cleanup automation — v1.0
- ✓ TRBL-01: Data-driven troubleshooting engine with JSON flows — v1.0
- ✓ TRBL-02: Graphics troubleshooting guides (black screen, artifacts, low FPS) — v1.0
- ✓ TRBL-03: Audio troubleshooting guides (crackling, missing sound, stuttering) — v1.0
- ✓ TRBL-04: Launcher troubleshooting guides (Steam, EA, Rockstar, Epic) — v1.0
- ✓ TRBL-05: Automated diagnostic checks in troubleshooting guides — v1.0

### Active

<!-- Current scope. Building toward these. -->

(No active requirements — v1.0 milestone complete. Start `/gsd:new-milestone` for next milestone.)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Patching Wine/GPTK source code — Whisky consumes Wine binaries, not builds them
- VR/OpenXR support — requires significant Wine-level work beyond app scope
- HDR support — requires Wine/macOS graphics pipeline changes
- DXMT compilation/bundling — separate project, may be included if available upstream
- Anti-cheat system compatibility (Denuvo, EAC) — kernel-level, not solvable in app layer
- Kernel-mode driver support — macOS limitation
- Game-specific patches — Wine/Proton upstream responsibility

## Context

Whisky is a macOS SwiftUI app for managing Wine bottles and running Windows applications. The upstream project (whisky-app/whisky) is no longer under active development, with 435+ open issues. This fork (frankea/Whisky) has shipped v1.0:

- **v1.0 shipped** with 10 phases, 50 plans, 98 feat commits across 202 files (~59K lines Swift)
- **54 requirements delivered** covering configuration, graphics, audio, process management, stability, game compatibility, troubleshooting, launchers, controllers, installation, UI/UX, and features
- **All tracking issues #40-#50 addressed** with code fixes, configuration UI, or in-app guidance
- **Key subsystems built**: EnvironmentBuilder (8-layer cascade), CrashClassifier (pattern matching), GameDB (30 entries), TroubleshootingFlowEngine (8 symptom flows)
- **Codebase map** available in `.planning/codebase/` with architecture, stack, conventions, testing, and concerns documentation

The app is built with Swift/SwiftUI, targeting macOS 15+, using SwiftFormat 0.58.7 and SwiftLint. WhiskyKit is the core Swift package containing Wine execution, bottle management, and PE file parsing logic.

## Constraints

- **Tech stack**: Swift/SwiftUI, macOS 15+ only — all fixes must be in Swift
- **Wine binary**: Consumes WhiskyWine builds (currently Wine 11.0) — cannot modify Wine source
- **Code quality**: SwiftFormat 0.58.7 enforced in CI, SwiftLint with no force unwrapping, GPL v3 headers required
- **Localization**: All user-facing strings must be localized (EN strings file), translations on Crowdin
- **Public repo**: No mention of AI/Claude in committed files (commit messages, code comments, docs, PRs)
- **Upstream compatibility**: Changes should be submittable upstream if the project revives

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Configuration + guidance for Wine-layer issues | Can't patch Wine; expose settings and help users self-serve | ✓ Good |
| Fold PR #79 into project plan | Part of #50 tracking, treat as in-progress work | ✓ Good |
| Include all branch work in baseline | Account for unmerged work on 4 feature branches | ✓ Good |
| Every tracking issue gets a response | Comprehensive coverage ensures no upstream problem ignored | ✓ Good |
| EnvironmentBuilder 8-layer cascade | Single code path for all env var resolution | ✓ Good |
| Tiered Simple/Advanced UI for settings | Avoids overwhelming users while exposing power features | ✓ Good |
| JSON-driven troubleshooting flows | Extensible without code changes, data-driven decision trees | ✓ Good |
| Caseless enum pattern for utility namespaces | Consistent pattern across GPUDetection, GameMatcher, FlowLoader, etc. | ✓ Good |
| Module-scope enums for shared types | ClipboardPolicy, GraphicsBackend, etc. at module scope for easier imports | ✓ Good |
| Bundled curated game DB over community compat | Small macOS contributor base would lead to rapid data decay | ✓ Good |

---
*Last updated: 2026-02-12 after v1.0 milestone*
