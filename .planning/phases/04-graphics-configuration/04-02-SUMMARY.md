---
phase: 04-graphics-configuration
plan: 02
subsystem: graphics-ui
tags: [swiftui, backend-picker, graphics-config, dxvk-settings, simple-advanced-toggle, selection-cards]

# Dependency graph
requires:
  - phase: 04-graphics-configuration
    provides: GraphicsBackend enum, GraphicsBackendResolver, BottleGraphicsConfig, graphicsBackend proxy on BottleSettings
  - phase: 03-process-lifecycle-management
    provides: ProcessRegistry.shared.getProcessCount, Wine.isWineserverRunning
provides:
  - BackendPickerView with 4 selection cards and inline compatibility warning
  - GraphicsConfigSection with Simple/Advanced toggle replacing DXVKConfigSection + MetalConfigSection
  - DXVKSettingsView with async toggle, HUD picker, and dxvk.conf management
  - Resolved backend display in BottleView navigation subtitle
affects: [04-03, 05-environment-inspector]

# Tech tracking
tech-stack:
  added: []
  patterns: [selection-card-grid, tiered-simple-advanced-ui, global-appstorage-preference]

key-files:
  created:
    - Whisky/Views/Bottle/BackendPickerView.swift
    - Whisky/Views/Bottle/GraphicsConfigSection.swift
    - Whisky/Views/Bottle/DXVKSettingsView.swift
  modified:
    - Whisky/Views/Bottle/ConfigView.swift
    - Whisky/Views/Bottle/BottleView.swift
    - Whisky.xcodeproj/project.pbxproj

key-decisions:
  - "Selection card 2x2 grid with LazyVGrid and custom BackendCard button (not standard Picker)"
  - "SF Symbols: sparkles (Recommended), display (D3DMetal), arrow.triangle.2.circlepath (DXVK), cup.and.saucer (WineD3D)"
  - "Wine.killBottle called synchronously (fire-and-forget) with Task sleep before re-checking process state"
  - "hasAdvancedSettingsConfigured uses inline default values instead of constructing BottleDXVKConfig (internal access)"
  - "Metal settings migrated inline into GraphicsConfigSection Advanced mode rather than separate MetalSettingsView"

patterns-established:
  - "Selection card grid: LazyVGrid + ButtonStyle(.plain) for custom selection card UIs"
  - "Tiered UI: @AppStorage global toggle with conditional content blocks for Simple/Advanced"
  - "Advanced badge pattern: detect non-default settings and show jump-link to Advanced mode"

# Metrics
duration: 5min
completed: 2026-02-09
---

# Phase 4 Plan 2: Graphics Configuration UI Summary

**Tiered Simple/Advanced graphics section with 4-card backend picker, DXVK settings with dxvk.conf management, and unified GraphicsConfigSection replacing separate DXVK and Metal sections**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-09T19:30:02Z
- **Completed:** 2026-02-09T19:35:30Z
- **Tasks:** 2
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments

- BackendPickerView renders 4 selection cards with icon, name, summary, tags, and Why? popover for Recommended
- GraphicsConfigSection with Simple/Advanced segmented toggle, running process warning, and advanced settings badge
- DXVKSettingsView with async toggle, HUD picker, and dxvk.conf file management (Open in Editor, Reveal in Finder, Reset)
- ConfigView simplified: unified GraphicsConfigSection replaces separate DXVKConfigSection + MetalConfigSection
- BottleView navigation subtitle shows resolved backend name when Auto is selected

## Task Commits

Each task was committed atomically:

1. **Task 1: Create BackendPickerView and GraphicsConfigSection with Simple mode** - `f18b0947` (feat)
2. **Task 2: Add Advanced mode content, DXVKSettingsView, and integrate into ConfigView** - `5ae400d4` (feat)

## Files Created/Modified

- `Whisky/Views/Bottle/BackendPickerView.swift` - 4-card selection grid with BackendCard, compatibility warning, Why? popover
- `Whisky/Views/Bottle/GraphicsConfigSection.swift` - Unified graphics section with Simple/Advanced toggle, running process warning, Metal settings
- `Whisky/Views/Bottle/DXVKSettingsView.swift` - DXVK controls (async, HUD, dxvk.conf) with active/inactive state
- `Whisky/Views/Bottle/ConfigView.swift` - Replaced DXVKConfigSection + MetalConfigSection with GraphicsConfigSection
- `Whisky/Views/Bottle/BottleView.swift` - Added navigationSubtitle showing resolved backend when Auto selected
- `Whisky.xcodeproj/project.pbxproj` - Added three new Swift files to Whisky target

## Decisions Made

- Selection cards use custom Button + BackendCard rather than standard Picker for richer visual layout
- SF Symbols chosen: sparkles, display, arrow.triangle.2.circlepath, cup.and.saucer
- Wine.killBottle is synchronous (fire-and-forget Task internally); stop button uses Task with sleep for re-check
- hasAdvancedSettingsConfigured uses !dxvkAsync (checking inverted default) instead of BottleDXVKConfig() constructor due to internal access level
- Metal settings inlined directly into GraphicsConfigSection Advanced mode rather than creating separate MetalSettingsView

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed BottleDXVKConfig internal access level**
- **Found during:** Task 1 (GraphicsConfigSection compilation)
- **Issue:** `BottleDXVKConfig().dxvkAsync` has internal access, inaccessible from Whisky app target
- **Fix:** Used `!bottle.settings.dxvkAsync` (inverted default check) instead of constructing BottleDXVKConfig
- **Files modified:** Whisky/Views/Bottle/GraphicsConfigSection.swift
- **Verification:** Build succeeds
- **Committed in:** f18b0947 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Trivial access level workaround. No scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Graphics configuration UI complete; ready for Plan 04-03 (per-program graphics overrides)
- All three new view files in the Xcode project and building cleanly
- DXVKConfigSection and MetalConfigSection still exist in the project but are no longer referenced by ConfigView

## Self-Check: PASSED

- All 3 created files exist on disk
- Both task commits (f18b0947, 5ae400d4) present in git log
- ConfigView contains no DXVKConfigSection or MetalConfigSection references
- GraphicsConfigSection contains @AppStorage("graphicsAdvancedMode")
- BackendPickerView iterates GraphicsBackend.allCases with 4 selection cards
- DXVKSettingsView disables controls via isDXVKActive
- BottleView contains .navigationSubtitle with GraphicsBackendResolver.resolve()

---
*Phase: 04-graphics-configuration*
*Completed: 2026-02-09*
