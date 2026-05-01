---
phase: 01-miscellaneous-fixes
plan: 03
subsystem: integration
tags: [clipboard, cleanup, lifecycle, configview, tempfile, swiftui]

# Dependency graph
requires:
  - phase: 01-miscellaneous-fixes/01
    provides: "ClipboardCheckResult, ClipboardPolicy, BottleCleanupConfig, KillOnQuitPolicy"
provides:
  - "Pre-launch clipboard check wired into program launch flow"
  - "TempFileTracker integration in runInTerminal and openTerminal"
  - "Per-bottle killOnQuit overrides in applicationWillTerminate"
  - "Orphan temp file cleanup on app launch (24h threshold)"
  - "CleanupConfigSection with clipboard policy and kill-on-quit pickers"
  - "Zombie process notification infrastructure"
affects: [02-environment-builder, 03-process-lifecycle]

# Tech tracking
tech-stack:
  added: []
  patterns: ["pre-launch hook pattern (clipboard check before Wine execution)", "per-bottle policy override pattern (killOnQuit inheriting from global)"]

key-files:
  created:
    - "Whisky/Views/Bottle/CleanupConfigSection.swift"
  modified:
    - "WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift"
    - "Whisky/Extensions/Bottle+Extensions.swift"
    - "Whisky/Views/Programs/ProgramsView.swift"
    - "Whisky/AppDelegate.swift"
    - "Whisky/Views/Bottle/ConfigView.swift"
    - "Whisky/Views/ContentView.swift"
    - "Whisky/Localizable.xcstrings"
    - "Whisky.xcodeproj/project.pbxproj"

key-decisions:
  - "Clipboard check called from ProgramItemView before launchWithUserMode, not inside it, to keep toast display in app layer"
  - "NSAlert for needsUserDecision shown in WhiskyKit extension (established pattern with showRunError)"
  - "Startup zombie process sweep deferred to Phase 3 (ProcessRegistry is session-based, cannot detect orphans from prior crashes)"
  - "CleanupConfigSection extracted to separate file to resolve SwiftLint type_body_length on ConfigView"

patterns-established:
  - "Pre-launch hook: performClipboardCheck() called before Wine execution, returns result for caller to handle toast"
  - "Per-bottle policy override: bottle.settings.killOnQuit cascades inherit/alwaysKill/neverKill over global killOnTerminate"
  - "Notification.Name extension for cross-component toast communication (zombieProcessesCleaned)"

# Metrics
duration: 8min
completed: 2026-02-09
---

# Phase 1 Plan 3: Integration Layer Summary

**Pre-launch clipboard checks with per-bottle policy, TempFileTracker wiring into script lifecycle, and AppDelegate cleanup hooks with per-bottle killOnQuit overrides**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-09T04:38:48Z
- **Completed:** 2026-02-09T04:47:23Z
- **Tasks:** 2
- **Files modified:** 9 (8 modified + 1 created)

## Accomplishments
- Every program launch now checks clipboard via ClipboardManager with per-bottle policy applied
- Known multiplayer launchers get auto-clear with info toast; unknown programs with large clipboard get blocking NSAlert
- Temp script files tracked by TempFileTracker with retry-based cleanup replacing raw FileManager.removeItem
- AppDelegate performs per-bottle killOnQuit policy override and synchronous temp file cleanup on quit
- Orphaned temp files from previous sessions cleaned up asynchronously on launch (24h threshold)
- ConfigView has new Cleanup section with clipboard policy picker and kill-on-quit picker

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire clipboard check and temp file tracking into launch flow** - `b428aa42` (feat)
2. **Task 2: Add lifecycle hooks and cleanup settings UI** - `e0fb6ad4` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift` - Added performClipboardCheck(), showClipboardAlert(), TempFileTracker.register in runInTerminal
- `Whisky/Extensions/Bottle+Extensions.swift` - Added TempFileTracker.register and cleanupWithRetry in openTerminal
- `Whisky/Views/Programs/ProgramsView.swift` - Added clipboard check before launch with auto-cleared toast
- `Whisky/AppDelegate.swift` - Added startup temp cleanup, per-bottle killOnQuit, synchronous quit cleanup, Notification.Name extension
- `Whisky/Views/Bottle/CleanupConfigSection.swift` - New cleanup settings section with two pickers
- `Whisky/Views/Bottle/ConfigView.swift` - Integrated CleanupConfigSection, added cleanupSectionExpanded state
- `Whisky/Views/ContentView.swift` - Added zombieProcessesCleaned notification observer for toast
- `Whisky/Localizable.xcstrings` - Added 13 localization strings for cleanup UI and toasts
- `Whisky.xcodeproj/project.pbxproj` - Added CleanupConfigSection.swift to build targets

## Decisions Made
- Clipboard check called from ProgramItemView (app layer) rather than inside launchWithUserMode (WhiskyKit) to keep toast display in the layer that owns the toast binding
- NSAlert for needsUserDecision shown from WhiskyKit Program extension, consistent with existing showRunError pattern
- Startup zombie process sweep deferred to Phase 3 -- ProcessRegistry is session-based and cannot detect orphans from previous crash sessions without system-level process scanning
- Extracted CleanupConfigSection to its own file to stay within SwiftLint's 250-line type body limit on ConfigView

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extracted CleanupConfigSection to resolve SwiftLint type_body_length**
- **Found during:** Task 2 (ConfigView cleanup section)
- **Issue:** Adding inline Section to ConfigView exceeded SwiftLint's 250-line struct body limit (253 lines)
- **Fix:** Extracted cleanup UI into `CleanupConfigSection.swift` following existing pattern (InputConfigSection, LauncherConfigSection)
- **Files modified:** `Whisky/Views/Bottle/CleanupConfigSection.swift` (created), `ConfigView.swift`, `project.pbxproj`
- **Verification:** Build succeeds, SwiftLint passes
- **Committed in:** e0fb6ad4 (Task 2 commit)

**2. [Rule 3 - Blocking] Deferred startup zombie process sweep**
- **Found during:** Task 2 (AppDelegate startup hooks)
- **Issue:** Plan referenced `ProcessRegistry.shared.sweepOrphanedProcesses()` which does not exist. ProcessRegistry is session-based (in-memory singleton) and is empty on fresh app launch after a crash, making orphan detection impossible without system-level process scanning.
- **Fix:** Implemented temp file cleanup on startup (filesystem-based, works correctly). Deferred zombie process sweep to Phase 3 which will add proper process lifecycle tracking. Added notification infrastructure for future use.
- **Files modified:** `Whisky/AppDelegate.swift`
- **Verification:** Build succeeds, startup cleanup for temp files works
- **Committed in:** e0fb6ad4 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes necessary for correctness. No scope creep. Zombie sweep deferred to proper phase.

## Issues Encountered
None beyond the deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All clipboard, temp file, and cleanup infrastructure from Phase 1 is now fully integrated
- Zombie process sweep infrastructure (notification, toast observer) is ready for Phase 3
- Per-bottle cleanup settings persist via BottleCleanupConfig plist serialization
- All 23 WhiskyKit tests pass, app builds successfully

---
*Phase: 01-miscellaneous-fixes*
*Completed: 2026-02-09*
