# Whisky Upstream Issue Resolution

## What This Is

A systematic effort to address all 435+ upstream issues from whisky-app/whisky, organized into 10 tracking categories (#40-#50) on the frankea/Whisky fork. The project covers app-layer fixes, Wine configuration exposure in the UI, and in-app troubleshooting guidance for issues that live at the Wine/GPTK/driver layer. The fork aims to be a meaningfully better Whisky than the unmaintained upstream across every issue category.

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

### Active

<!-- Current scope. Building toward these. -->

- [ ] Complete #50 miscellaneous fixes (ClickOnceManager, process management, clipboard, temp files) — PR #79 in progress
- [ ] Graphics configuration UI exposing DXVK/D3DMetal/MoltenVK settings with per-game guidance (#43)
- [ ] Audio troubleshooting configuration: FAudio/dsound/GStreamer settings and in-app guidance (#44)
- [ ] Remaining Steam & launcher issues: download stalls, UI glitches, macOS 15.4 compatibility (#41)
- [ ] Remaining controller issues: detection persistence, per-controller mapping, microphone permissions (#42)
- [ ] Remaining stability issues: GPU crash patterns, memory management, resource cleanup (#40)
- [ ] Remaining installation issues: dependency installation guidance, permission flow (#45)
- [ ] Game compatibility workaround database and in-app guidance (#48)
- [ ] Remaining UI/UX: GPTK update dialog, shortcut path escaping, WhiskyCmd improvements (#49)
- [ ] Feature requests: App Nap management, duplicate bottles, resolution control, console persistence (#47)
- [ ] Wine process auto-termination and cleanup (#50)
- [ ] In-app troubleshooting guides for Wine-layer issues (graphics, audio, game-specific)

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

Whisky is a macOS SwiftUI app for managing Wine bottles and running Windows applications. The upstream project (whisky-app/whisky) is no longer under active development, with 435+ open issues. This fork (frankea/Whisky) has already made significant progress:

- **28 PRs merged** addressing stability, launchers, UI/UX, controllers, installation, and infrastructure
- **1 open PR** (#79) for miscellaneous fixes on `issue-50-miscellaneous-fixes` branch
- **4 feature branches** with unmerged work: issue-50 (8 commits), test-coverage (10 commits), UI/UX (2 commits), controller (2 commits)
- **Tracking issues #40-#50** provide organized categorization of all upstream problems
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
| Configuration + guidance for Wine-layer issues | Can't patch Wine; expose settings and help users self-serve | — Pending |
| Fold PR #79 into project plan | Part of #50 tracking, treat as in-progress work | — Pending |
| Include all branch work in baseline | Account for unmerged work on 4 feature branches | — Pending |
| Every tracking issue gets a response | Comprehensive coverage ensures no upstream problem ignored | — Pending |

---
*Last updated: 2026-02-08 after initialization*
