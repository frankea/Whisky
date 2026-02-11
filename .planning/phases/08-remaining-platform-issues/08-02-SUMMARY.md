---
phase: 08-remaining-platform-issues
plan: 02
subsystem: input
tags: [gamecontroller, gccontroller, sdl, xinput, controller-monitoring]

# Dependency graph
requires:
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder and BottleSettings layer populator pattern
provides:
  - ControllerMonitor with real-time GCController discovery and type/connection/battery info
  - ControllerInfo model with type badges (PlayStation/Xbox/Generic) and connection badges (USB/Bluetooth)
  - ControllerHistoryEntry for diagnostics export
  - BottleInputConfig.useButtonLabels field for XInput vs Native labels SDL hint
affects: [08-remaining-platform-issues, controller-panel-ui]

# Tech tracking
tech-stack:
  added: [GameController framework]
  patterns: [nonisolated(unsafe) for observer storage in @MainActor deinit, notification-based controller monitoring]

key-files:
  created:
    - Whisky/Utils/ControllerMonitor.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleInputConfig.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
    - WhiskyKit/Tests/WhiskyKitTests/BottleInputConfigTests.swift
    - Whisky.xcodeproj/project.pbxproj

key-decisions:
  - "nonisolated(unsafe) for notification observer storage to satisfy Swift 6 deinit isolation requirements"
  - "useButtonLabels coexists with disableControllerMapping; either being true sets SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1"
  - "Explicit SDL_GAMECONTROLLER_USE_BUTTON_LABELS=0 emitted when compat mode on but labels disabled"

patterns-established:
  - "GameController notification pattern: register observers before calling GCController.controllers() to catch late discoveries"
  - "Controller type classification via productCategory string matching (DualSense/DualShock -> PlayStation, Xbox -> Xbox)"

# Metrics
duration: 8min
completed: 2026-02-11
---

# Phase 8 Plan 2: Controller Discovery Infrastructure Summary

**GCController-based real-time controller monitoring with type/connection/battery classification and SDL button labels config**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-11T06:48:52Z
- **Completed:** 2026-02-11T06:57:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- ControllerMonitor discovers connected controllers via GameController framework with real-time connect/disconnect notifications
- ControllerInfo model provides type badges (PlayStation/Xbox/Generic), connection badges (USB/Bluetooth), and battery level/state
- Recent controller history tracked for diagnostics export (bounded to 10 entries, deduped by name)
- BottleInputConfig extended with useButtonLabels field for XInput vs Native labels SDL hint
- All 12 BottleInputConfig tests pass including new useButtonLabels coverage

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ControllerMonitor with GCController integration** - `197a9944` (feat)
2. **Task 2: Extend BottleInputConfig with XInput/Native labels SDL hint** - `a9c7c718` (feat)

## Files Created/Modified
- `Whisky/Utils/ControllerMonitor.swift` - GCController wrapper with ControllerInfo, ControllerType, ConnectionType, ControllerHistoryEntry models and real-time monitoring
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleInputConfig.swift` - Added useButtonLabels field with defensive decoding
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - Added useButtonLabels proxy property and updated populateInputCompatibilityLayer
- `WhiskyKit/Tests/WhiskyKitTests/BottleInputConfigTests.swift` - Updated all tests for useButtonLabels field, added dedicated test
- `Whisky.xcodeproj/project.pbxproj` - Added ControllerMonitor.swift to Whisky target

## Decisions Made
- Used `nonisolated(unsafe)` for notification observer storage since Swift 6 prevents accessing @MainActor properties from deinit
- `useButtonLabels` and `disableControllerMapping` both control `SDL_GAMECONTROLLER_USE_BUTTON_LABELS`; either being true sets it to "1", both false sets "0" (explicit value emitted when compat mode is on)
- ControllerMonitor placed in Whisky app target (not WhiskyKit) since GameController framework is app-level

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Swift 6 deinit isolation error**
- **Found during:** Task 1 (ControllerMonitor creation)
- **Issue:** `deinit` cannot call `@MainActor`-isolated `stopMonitoring()` in Swift 6 strict concurrency
- **Fix:** Used `nonisolated(unsafe)` for observer storage and inlined cleanup in deinit
- **Files modified:** Whisky/Utils/ControllerMonitor.swift
- **Verification:** Build passes without concurrency errors
- **Committed in:** 197a9944 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary for Swift 6 compliance. No scope creep.

## Issues Encountered
- Pre-existing SwiftLint violations in other files (MacOSCompatibility.swift, LauncherPresets.swift, DependencyManager.swift) cause build to fail at lint phase, but ControllerMonitor.swift compiles and lints cleanly

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ControllerMonitor ready for controller panel UI (Phase 8 plan for controller section)
- BottleInputConfig.useButtonLabels ready for toggle binding in InputConfigSection
- ControllerHistoryEntry ready for diagnostics export integration

---
*Phase: 08-remaining-platform-issues*
*Completed: 2026-02-11*
