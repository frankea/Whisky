---
phase: 08-remaining-platform-issues
plan: 05
subsystem: input
tags: [gamecontroller, controller-monitoring, sdl, xinput, per-program-overrides]

# Dependency graph
requires:
  - phase: 08-remaining-platform-issues
    plan: 02
    provides: ControllerMonitor, ControllerInfo, useButtonLabels field in BottleInputConfig
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder, ProgramOverrides inherit/override pattern
provides:
  - Connected Controllers subpanel in InputConfigSection with live discovery
  - Per-program input overrides (useButtonLabels) in ProgramOverrideSettingsView
  - Input override SDL hints wired through programUser layer in WineEnvironment
affects: [08-remaining-platform-issues]

# Tech tracking
tech-stack:
  added: []
  patterns: [ControllerMonitor @StateObject integration, clipboard copy for diagnostics export]

key-files:
  created: []
  modified:
    - Whisky/Views/Bottle/InputConfigSection.swift
    - Whisky/Views/Programs/ProgramOverrideSettingsView.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift

key-decisions:
  - "Renamed existing 'Use Native Button Labels' toggle to 'Disable Controller Mapping' for clarity; new useButtonLabels toggle added separately"
  - "Connected Controllers subpanel collapsed by default with DisclosureGroup"
  - "Input overrides at programUser layer: controllerCompatibilityMode gates all SDL hint overrides"
  - "useButtonLabels and disableControllerMapping both control SDL_GAMECONTROLLER_USE_BUTTON_LABELS at program level (matching bottle behavior)"

patterns-established:
  - "ControllerMonitor lifecycle: @StateObject with onAppear/onDisappear start/stop pattern"
  - "Copy Controller Info: clipboard export pattern for diagnostics (name, type, connection, battery, history)"
  - "Input override gating: controller compat mode acts as gate for all SDL hint overrides at program level"

# Metrics
duration: 7min
completed: 2026-02-11
---

# Phase 8 Plan 5: Controller Panel UI and Per-Program Input Overrides Summary

**Connected Controllers subpanel with live discovery, type/connection/battery badges, Bluetooth warning, and per-program input overrides with useButtonLabels toggle**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-11T07:04:52Z
- **Completed:** 2026-02-11T07:11:47Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Connected Controllers subpanel in InputConfigSection with live GCController discovery, type/connection/battery badges
- Bluetooth inline warning banner when wireless controllers are connected
- Refresh and Copy Controller Info action buttons for diagnostics export
- Empty state with troubleshooting hint when no controllers detected
- Use Native Button Labels toggle bound to useButtonLabels from Plan 02
- Per-program input overrides with useButtonLabels in ProgramOverrideSettingsView
- Input SDL hints wired through programUser layer in WineEnvironment applyProgramOverrides

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Connected Controllers subpanel to InputConfigSection** - `74c19c8a` (feat)
2. **Task 2: Add per-program input overrides to ProgramOverrideSettingsView** - `469be0a4` (feat)

## Files Created/Modified
- `Whisky/Views/Bottle/InputConfigSection.swift` - Enhanced with ControllerMonitor integration, Connected Controllers DisclosureGroup, bluetooth warning, action buttons, battery display
- `Whisky/Views/Programs/ProgramOverrideSettingsView.swift` - Added useButtonLabels toggle to input controls, updated inherit summary and copy-on-enable
- `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift` - Added useButtonLabels optional field with decodeIfPresent and isEmpty check
- `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` - Added input override handling in applyProgramOverrides for SDL hints at programUser layer

## Decisions Made
- Renamed existing "Use Native Button Labels" toggle to "Disable Controller Mapping" for clarity, keeping both toggles functional since they serve different conceptual purposes (legacy mapping disable vs. explicit button label preference)
- Connected Controllers subpanel uses DisclosureGroup collapsed by default (per user decision) to avoid visual clutter when users don't need controller info
- Input override at program level uses controllerCompatibilityMode as a gate: when compat mode is overridden off, all SDL hints are removed at program layer; when on, individual hint overrides apply
- Copy Controller Info includes recent controller history entries for better diagnostics context

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed pre-existing SwiftLint function_body_length in DependencyConfigSection.swift**
- **Found during:** Task 1 (build verification)
- **Issue:** DependencyConfigSection.swift from Phase 08-03 had a function_body_length violation (52 lines, limit 50) that caused SwiftLint to fail the build
- **Fix:** Extracted `dependencyRowDetails` helper method from `dependencyRow` function
- **Files modified:** Whisky/Views/Bottle/DependencyConfigSection.swift
- **Verification:** Build passes without lint errors
- **Committed in:** 74c19c8a (Task 1 commit, included pre-existing staged files)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to unblock build. No scope creep.

## Issues Encountered
- Pre-existing uncommitted files from Phases 08-03/08-04 (DependencyConfigSection, DependencyInstallSheet, ConfigView, StatusToast, LaunchTimeBanner, project.pbxproj) were on disk but untracked/unstaged. Some were auto-staged by prior sessions. Task 1 commit included DependencyConfigSection and project.pbxproj changes that were already in the staging area.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Controller panel UI complete; ready for Phase 08-06 (Dependency Install UI) and 08-07 (Final Integration)
- Per-program input overrides fully functional with useButtonLabels wired through environment cascade
- All WhiskyKit tests pass (23/23)

## Self-Check: PASSED

- [x] InputConfigSection.swift exists
- [x] ProgramOverrideSettingsView.swift exists
- [x] ProgramOverrides.swift exists
- [x] WineEnvironment.swift exists
- [x] 08-05-SUMMARY.md exists
- [x] Commit 74c19c8a exists (Task 1)
- [x] Commit 469be0a4 exists (Task 2)

---
*Phase: 08-remaining-platform-issues*
*Completed: 2026-02-11*
