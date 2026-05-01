---
phase: 03-process-lifecycle-management
plan: 02
subsystem: ui
tags: [process-management, swiftui-table, viewmodel, polling, shutdown-orchestration, context-menu, localization]

# Dependency graph
requires:
  - phase: 03-01
    provides: WineProcess types, parseTasklistOutput, gracefulKillProcess, forceKillProcess, ProcessRegistry queries
provides:
  - ProcessesViewModel with hybrid polling, registry merging, and 3-step shutdown orchestration
  - Full Processes page with 6-column Table, toolbar filter, context menus, and shutdown overlay
  - Active Processes navigation link with running count badge in BottleView
  - 35 English localization entries for all process UI strings
affects: [03-03-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: [ObservableObject ViewModel with polling Task, extension-based struct decomposition for SwiftLint compliance, contextMenu(forSelectionType:) for Table rows]

key-files:
  created:
    - Whisky/View Models/ProcessesViewModel.swift
  modified:
    - Whisky/Views/Bottle/RunningProcessesView.swift
    - Whisky/Views/Bottle/BottleView.swift
    - Whisky/Localizable.xcstrings
    - Whisky.xcodeproj/project.pbxproj
    - WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift

key-decisions:
  - "ProcessRegistry.shared made public for app target access (was internal)"
  - "RunningProcessesView split into struct + 2 extensions for SwiftLint type_body_length (250 line limit)"
  - "contextMenu(forSelectionType: Int32.self) used for Table row context menus"
  - "Text(date, style: .relative) for launch time display instead of custom formatter"
  - "Shutdown refreshProcessListDuringShutdown temporarily resets shutdownState to bypass guard"

patterns-established:
  - "ViewModel extension: Extract table/detail/toolbar views into extensions when struct body exceeds 250 lines"
  - "Polling lifecycle: startPolling on .onAppear, stopPolling on .onDisappear with Task-based loop"

# Metrics
duration: 8min
completed: 2026-02-09
---

# Phase 3 Plan 2: Processes Page ViewModel and UI Summary

**ProcessesViewModel with 3s hybrid polling, 6-column Table with filter/context-menus/shutdown, and BottleView navigation integration**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-09T17:53:25Z
- **Completed:** 2026-02-09T18:01:16Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created ProcessesViewModel with ~3s polling loop, tasklist+registry merging, stale entry cleanup, and 3-step shutdown orchestration (graceful per-app, wineserver -k, SIGKILL)
- Rewrote RunningProcessesView from a basic 2-column table to a full Processes page with 6 columns (Name, PID, Memory, Started, Kind, Source), toolbar filter picker, context menus, keyboard shortcuts, shutdown overlay, and confirmation dialogs
- Enabled Processes navigation link in BottleView with running process count badge
- Added 35 English localization strings for all new process UI text

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ProcessesViewModel with hybrid update model and shutdown orchestration** - `e85d4a69` (feat)
2. **Task 2: Rewrite RunningProcessesView as full Processes page with Table, toolbar, and actions** - `cec8b0d8` (feat)

## Files Created/Modified
- `Whisky/View Models/ProcessesViewModel.swift` - ViewModel with polling, merging, kill actions, and shutdown orchestration
- `Whisky/Views/Bottle/RunningProcessesView.swift` - Full Processes page with Table, toolbar, context menus, detail drawer, shutdown overlay
- `Whisky/Views/Bottle/BottleView.swift` - Uncommented Processes navigation link with count badge
- `Whisky/Localizable.xcstrings` - 35 new English localization entries for process UI
- `Whisky.xcodeproj/project.pbxproj` - Added ProcessesViewModel.swift to Whisky target
- `WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift` - Made `shared` property public

## Decisions Made
- ProcessRegistry.shared made public for app target access (was internal, needed by ViewModel and BottleView badge)
- RunningProcessesView split into struct + 2 extensions for SwiftLint type_body_length compliance (250 line limit)
- Used contextMenu(forSelectionType: Int32.self) for Table row context menus (matches WineProcess.id type)
- Used Text(date, style: .relative) for launch time display (automatic updating without manual formatter)
- Shutdown refresh uses temporary state bypass rather than a separate refresh method to avoid code duplication

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Made ProcessRegistry.shared public**
- **Found during:** Task 1 (ProcessesViewModel creation)
- **Issue:** ProcessRegistry.shared had internal access, preventing use from Whisky app target
- **Fix:** Changed `static let shared` to `public static let shared`
- **Files modified:** WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift
- **Verification:** Build succeeds, ViewModel and BottleView can access ProcessRegistry.shared
- **Committed in:** e85d4a69 (Task 1 commit)

**2. [Rule 3 - Blocking] SwiftLint for_where violation fix**
- **Found during:** Task 1 (ProcessesViewModel creation)
- **Issue:** for-in with single if body triggers SwiftLint for_where rule
- **Fix:** Refactored to for-where clause pattern
- **Files modified:** Whisky/View Models/ProcessesViewModel.swift
- **Verification:** Build succeeds with no SwiftLint violations
- **Committed in:** e85d4a69 (Task 1 commit)

**3. [Rule 3 - Blocking] SwiftLint type_body_length violation**
- **Found during:** Task 2 (RunningProcessesView rewrite)
- **Issue:** Struct body exceeded 250 line limit (297 lines)
- **Fix:** Extracted Table/Detail/Toolbar/Helpers into two extensions
- **Files modified:** Whisky/Views/Bottle/RunningProcessesView.swift
- **Verification:** Build succeeds, struct body under 250 lines
- **Committed in:** cec8b0d8 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 blocking)
**Impact on plan:** All auto-fixes necessary for compilation. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ProcessesViewModel and RunningProcessesView are fully functional for Plan 03 integration testing
- All ViewModel methods are ready for use: startPolling, stopPolling, refreshProcessList, quitProcess, forceQuitProcess, stopBottle, forceStopBottle
- Localization strings are in place; translations will be handled via Crowdin

## Self-Check: PASSED

All files found, all commits verified.

---
*Phase: 03-process-lifecycle-management*
*Completed: 2026-02-09*
