---
phase: 04-graphics-configuration
plan: 03
subsystem: graphics-ui
tags: [swiftui, per-program-overrides, graphics-backend, override-badge, inherit-override-pattern]

# Dependency graph
requires:
  - phase: 04-graphics-configuration
    provides: GraphicsBackend enum, BottleGraphicsConfig, graphicsBackend proxy on BottleSettings, ProgramOverrides.graphicsBackend
  - phase: 02-configuration-foundation
    provides: ProgramOverrideSettingsView inherit/override pattern, DLLOverrideResolver
provides:
  - GraphicsBackend picker in per-program override graphics group
  - DXVK sub-controls conditional on overridden backend being .dxvk
  - "Per-program overrides active" note in Simple mode with jump to Advanced
  - Per-program override list in Advanced mode showing backend names
  - Program list badge icon for programs with graphics overrides
affects: [05-environment-inspector]

# Tech tracking
tech-stack:
  added: []
  patterns: [backend-conditional-dxvk-controls, per-program-override-badge]

key-files:
  created: []
  modified:
    - Whisky/Views/Programs/ProgramOverrideSettingsView.swift
    - Whisky/Views/Bottle/GraphicsConfigSection.swift
    - Whisky/Views/Programs/ProgramsView.swift

key-decisions:
  - "graphicsBackend replaces dxvk as sentinel for graphics override group"
  - "Standalone DXVK toggle removed from override controls (backend picker implies DXVK is active)"
  - "computedManagedOverrides checks graphicsBackend == .dxvk instead of bottle.settings.dxvk"

patterns-established:
  - "Override badge pattern: slider.horizontal.3 icon with .help tooltip on program list items"
  - "Per-program override info in Advanced mode: list programs with overridden settings and values"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 4 Plan 3: Per-Program Graphics Overrides Summary

**Per-program graphics backend picker with conditional DXVK controls, override badge on program list, and bidirectional override awareness in GraphicsConfigSection Simple/Advanced modes**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T19:38:18Z
- **Completed:** 2026-02-09T19:41:20Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- ProgramOverrideSettingsView graphics group now includes GraphicsBackend picker with all 4 cases (Recommended, D3DMetal, DXVK, WineD3D)
- DXVK async/HUD sub-controls only visible when overridden backend is .dxvk; standalone DXVK toggle removed
- Copy-on-enable copies bottle's graphicsBackend alongside existing dxvk/dxvkAsync/dxvkHud fields
- GraphicsConfigSection Simple mode shows "Per-program overrides active" note with jump to Advanced when any program has graphics backend override
- GraphicsConfigSection Advanced mode shows per-program override list with program names and overridden backend display names
- Program list items show slider badge icon with "Graphics overridden" tooltip when graphics override is active

## Task Commits

Each task was committed atomically:

1. **Task 1: Update ProgramOverrideSettingsView with graphics backend override** - `0f6f5468` (feat)
2. **Task 2: Add per-program override notes and program badge** - `f358c655` (feat)

## Files Created/Modified

- `Whisky/Views/Programs/ProgramOverrideSettingsView.swift` - Graphics backend picker, conditional DXVK controls, graphicsBackendBinding, updated sentinel and copy-on-enable
- `Whisky/Views/Bottle/GraphicsConfigSection.swift` - programsWithGraphicsOverrides computed property, Simple mode override note, Advanced mode per-program override info list
- `Whisky/Views/Programs/ProgramsView.swift` - Graphics override badge icon on ProgramItemView with tooltip

## Decisions Made

- graphicsBackend replaces dxvk as the sentinel for "graphics group is overridden" (aligns with backend-first data model from Plan 04-01)
- Standalone DXVK toggle removed from per-program override controls since the backend picker already determines whether DXVK is active
- computedManagedOverrides updated to check graphicsBackend == .dxvk instead of the legacy bottle.settings.dxvk Bool

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 4 (Graphics Configuration) is now complete: data model (04-01), bottle-level UI (04-02), and per-program overrides (04-03) all implemented
- All three files build cleanly, all 23 tests pass, formatting clean across 168 files
- Ready for Phase 5 (Environment Inspector) which will build on the environment variable composition from Phase 2

## Self-Check: PASSED
