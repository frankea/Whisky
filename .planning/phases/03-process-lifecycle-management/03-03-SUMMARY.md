---
phase: 03-process-lifecycle-management
plan: 03
subsystem: ui, process-management
tags: [swiftui, sidebar-badge, orphan-detection, wineserver, nsalert, process-lifecycle]

# Dependency graph
requires:
  - phase: 03-01
    provides: Wine+ProcessManagement helpers (isWineserverRunning, killBottle, ProcessRegistry)
  - phase: 03-02
    provides: ProcessesViewModel and RunningProcessesView for process monitoring
provides:
  - Sidebar running process count badge and orphan warning icon
  - Pre-deletion process check with NSAlert confirmation
  - Startup orphan Wine process detection and policy-based auto-cleanup
  - Per-bottle CloseWithProcessesPolicy for navigation-away confirmation
  - Enhanced app quit with ProcessRegistry cleanup and logging
affects: [04-graphics-audio, 05-performance-tuning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Periodic async probe pattern (60s interval with Task cancellation)"
    - "NSAlert with checkbox accessory for remember-choice dialogs"
    - "Startup sweep with policy-based auto-cleanup via detached Task"

key-files:
  created: []
  modified:
    - Whisky/Views/Bottle/BottleListEntry.swift
    - Whisky/Extensions/Bottle+Extensions.swift
    - Whisky/AppDelegate.swift
    - Whisky/Views/ContentView.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleCleanupConfig.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
    - Whisky/Localizable.xcstrings

key-decisions:
  - "Close confirmation dialog placed in ContentView (not BottleView) because SwiftUI onDisappear fires after view removal, making dialog presentation impossible from the disappearing view"
  - "Used NSAlert with checkbox accessory for remember-choice UX (matching existing showRemoveAlert pattern)"
  - "Extracted sweepOrphanProcesses to @MainActor method to avoid Swift 6 region-based isolation checker bug with Task.detached { @MainActor in }"
  - "showProcessCloseAlert extracted to ContentView extension for SwiftLint type_body_length compliance"

patterns-established:
  - "Periodic probe pattern: Task loop with 60s sleep + isCancelled check for low-overhead polling"
  - "Navigation-away confirmation: onChange(of: selected) with NSAlert for process-aware navigation"

# Metrics
duration: 7min
completed: 2026-02-09
---

# Phase 3 Plan 3: Process Lifecycle Integration Summary

**Sidebar running badge with orphan detection, pre-deletion process safety, startup orphan sweep, and navigation-away confirmation dialog**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-09T18:07:04Z
- **Completed:** 2026-02-09T18:14:01Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Sidebar bottle list entries show blue capsule badge with running process count
- Orange warning icon appears for bottles with orphan Wine processes (wineserver active but no tracked processes)
- Bottle deletion checks for running processes and shows NSAlert confirmation before stopping and removing
- Startup orphan sweep probes all bottles and auto-cleans only when kill-on-quit policy is active
- Navigation-away confirmation dialog offers "Keep Running" (default) / "Stop Bottle" with "Remember for this bottle" checkbox
- App quit now clears ProcessRegistry for killed bottles and logs policy decisions

## Task Commits

Each task was committed atomically:

1. **Task 1: Add running badge, pre-deletion check, and close confirmation** - `50d7d9da` (feat)
2. **Task 2: AppDelegate startup orphan sweep and enhanced quit behavior** - `be32b4cb` (feat)

## Files Created/Modified
- `Whisky/Views/Bottle/BottleListEntry.swift` - Running count badge, orphan icon, periodic probe (60s)
- `Whisky/Extensions/Bottle+Extensions.swift` - Async remove(delete:) with process check and NSAlert
- `Whisky/AppDelegate.swift` - Startup orphan sweep, ProcessRegistry cleanup on quit, logging
- `Whisky/Views/ContentView.swift` - Close-with-processes confirmation dialog, async remove caller
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleCleanupConfig.swift` - CloseWithProcessesPolicy enum
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - closeWithProcessesPolicy proxy
- `Whisky/Localizable.xcstrings` - 10 new localization strings

## Decisions Made
- **Close confirmation in ContentView, not BottleView:** SwiftUI's `.onDisappear` fires after view removal, making it impossible to present a dialog from the disappearing BottleView. The confirmation is instead triggered from ContentView's `onChange(of: selected)` where the selection state lives.
- **NSAlert with checkbox:** Matches the existing `showRemoveAlert` pattern for consistent UX. The checkbox allows "Remember for this bottle" to persist the policy choice.
- **Extracted sweepOrphanProcesses method:** Swift 6's region-based isolation checker has a bug with `Task.detached { @MainActor in }`. Extracting to a `@MainActor` method called from a regular `Task` resolves this.
- **ContentView extension for type_body_length:** `showProcessCloseAlert` extracted to extension to keep ContentView struct body under SwiftLint's 250-line limit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Close confirmation dialog moved from BottleView to ContentView**
- **Found during:** Task 1 (BottleView changes)
- **Issue:** Plan specified adding confirmationDialog to BottleView, but SwiftUI's onDisappear fires after view removal -- the dialog cannot be presented from a view that's being destroyed
- **Fix:** Placed the confirmation logic in ContentView using onChange(of: selected) and NSAlert with checkbox
- **Files modified:** Whisky/Views/ContentView.swift (instead of Whisky/Views/Bottle/BottleView.swift)
- **Verification:** Build succeeds, dialog correctly shows when navigating away from bottle with processes
- **Committed in:** 50d7d9da

**2. [Rule 3 - Blocking] Swift 6 region-based isolation checker bug workaround**
- **Found during:** Task 2 (AppDelegate orphan sweep)
- **Issue:** `Task.detached { @MainActor in }` triggers compiler error "pattern that the region based isolation checker does not understand how to check"
- **Fix:** Extracted sweep logic to `@MainActor private func sweepOrphanProcesses()` called from `Task { await self.sweepOrphanProcesses() }`
- **Files modified:** Whisky/AppDelegate.swift
- **Verification:** Build succeeds with no compiler errors
- **Committed in:** be32b4cb

**3. [Rule 3 - Blocking] SwiftLint type_body_length in ContentView**
- **Found during:** Task 1 (ContentView changes)
- **Issue:** Adding showProcessCloseAlert method pushed ContentView struct body to 274 lines (limit: 250)
- **Fix:** Extracted method to `extension ContentView` below the struct definition
- **Files modified:** Whisky/Views/ContentView.swift
- **Verification:** SwiftLint passes, build succeeds
- **Committed in:** 50d7d9da

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All fixes necessary for correctness and compilation. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 3 (Process Lifecycle Management) is now complete with all 3 plans executed
- Process tracking (03-01), process UI (03-02), and lifecycle integration (03-03) provide full process awareness
- Ready for Phase 4 (Graphics & Audio) or Phase 5 (Performance Tuning) as specified in roadmap

---
*Phase: 03-process-lifecycle-management*
*Completed: 2026-02-09*
