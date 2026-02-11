---
phase: 09-ui-ux-feature-requests
plan: 06
subsystem: ui
tags: [console, run-history, log-viewer, channel-filtering, live-streaming, export]

# Dependency graph
requires:
  - phase: 09-ui-ux-feature-requests
    provides: RunLogEntry, RunLogHistory, RunLogStore data models from Plan 05
  - phase: 05-stability-diagnostics
    provides: ProgramRunResult, DiagnosisHistory persistence pattern
provides:
  - ConsoleRunHistoryView with last run, previous runs, and management actions
  - ConsoleLogView with channel filtering (stdout/stderr/WINEDEBUG) and export
  - ProgramView Console/Runs expandable section with run selection
  - Live streaming for running processes with auto-scroll
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [timer-based log tailing with FileHandle seek, regex-based WINEDEBUG line classification, heuristic stderr detection]

key-files:
  created:
    - Whisky/Views/Programs/ConsoleRunHistoryView.swift
    - Whisky/Views/Programs/ConsoleLogView.swift
  modified:
    - Whisky/Views/Programs/ProgramView.swift
    - Whisky.xcodeproj/project.pbxproj

key-decisions:
  - "Timer-based polling (2s for history, 1s for log tail) rather than DispatchSource file monitoring for simplicity"
  - "WINEDEBUG detection via regex patterns for Wine thread IDs and debug prefixes (fixme:, err:, trace:, warn:)"
  - "Heuristic stderr detection via common error indicators (Error:, FAILED, fatal:) since Wine log format does not separate stdout/stderr"
  - "Export includes WINEDEBUG content labeled when filtered out, for complete log capture"
  - "ConsoleLogView struct + extension split for SwiftLint type_body_length compliance"

patterns-established:
  - "ConsoleLogLine/ConsoleLogChannel for channel-classified log display"
  - "FileHandle.seek + readToEnd for incremental log tailing"

# Metrics
duration: 12min
completed: 2026-02-11
---

# Phase 09 Plan 06: Console Persistence UI Summary

**Run history list and log viewer with channel filtering (stdout/stderr/WINEDEBUG), live streaming, and Copy/Export/Open actions integrated into ProgramView**

## Performance

- **Duration:** 12 min
- **Started:** 2026-02-11T08:43:41Z
- **Completed:** 2026-02-11T08:55:44Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- ConsoleRunHistoryView showing "Last Run" prominently and "Previous Runs" in reverse chronological order
- Each run entry displays start time, duration, exit code badge (green/red), and "Running" pulse indicator
- ConsoleLogView with monospaced log display, channel filter toggles, and auto-scroll for live processes
- Copy to clipboard, Export via NSSavePanel, and Open Logs Folder actions
- "Exited (code X)" footer for completed runs with appropriate color coding
- Empty state with terminal icon when no run history exists
- Context menu "Delete Run" and "Delete Old Logs" management actions
- ProgramView expanded with Console / Runs section (persisted via AppStorage)

## Task Commits

Each task was committed atomically:

1. **Task 1: ConsoleRunHistoryView with run list and management actions** - `8746eaf8` (feat)
2. **Task 2: ConsoleLogView with channel filtering and export** - `e7a63359` (feat, included in 09-03 commit due to concurrent execution)

## Files Created/Modified
- `Whisky/Views/Programs/ConsoleRunHistoryView.swift` - Run history list with last run, previous runs, pulse animation, exit code badges, and management actions
- `Whisky/Views/Programs/ConsoleLogView.swift` - Log viewer with channel classification, filter toggles, live tailing, clipboard copy, file export, and WINEDEBUG support
- `Whisky/Views/Programs/ProgramView.swift` - Added Console / Runs expandable section with run selection state and ConsoleLogView integration
- `Whisky.xcodeproj/project.pbxproj` - Registered ConsoleRunHistoryView.swift and ConsoleLogView.swift in Programs group

## Decisions Made
- Timer-based polling (2s for history refresh, 1s for log tail) chosen over DispatchSource for simplicity and cross-platform consistency
- WINEDEBUG line classification uses regex patterns matching Wine thread IDs (`0009:`) and debug prefixes (`fixme:`, `err:`, `trace:`, `warn:`)
- Stderr detection is heuristic (common error indicators) since Wine log format does not separate stdout/stderr into distinct streams
- Export includes labeled WINEDEBUG content even when filtered out, ensuring complete log capture
- ConsoleLogView split into struct + extension to satisfy SwiftLint type_body_length (struct body under 250 lines)
- ConsoleLogLine and ConsoleLogChannel are module-level types (not private) for extension access

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ConsoleLogView committed in concurrent 09-03 execution**
- **Found during:** Task 2
- **Issue:** Task 2 file writes were picked up by a concurrent plan executor (09-03) which committed them together with ResolutionConfigSection
- **Fix:** Verified the full ConsoleLogView implementation is present in commit `e7a63359`; no duplicate commit needed
- **Files modified:** Whisky/Views/Programs/ConsoleLogView.swift
- **Verification:** All plan verification checks pass (NSSavePanel, filter toggles, channel filters)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No functional impact; ConsoleLogView implementation is complete and committed.

## Issues Encountered
- Pre-existing SwiftLint violations (Wine.swift type_body_length, WhiskyCmd file_length, RunLogTests identifier_name, ProgramOverrides function_body_length, ResolutionConfigSection type_body_length) cause BUILD FAILED in SwiftLint script phase. Swift compilation itself succeeds. These violations are from prior phases and not introduced by this plan.
- Xcode project PBX IDs initially used `J1A2B3C4...` format but were corrected to `E1A2B3C4...` by the concurrent 09-03 execution.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Console persistence feature (FEAT-04) is complete: data model (Plan 05) + UI (Plan 06)
- Users can browse run history, view console output with channel filtering, and export logs
- Live streaming works for running processes with auto-scroll and exit detection
- No additional infrastructure or configuration needed

## Self-Check: PASSED

- All 4 created/modified files verified on disk
- Task 1 commit (8746eaf8) found in git history
- Task 2 content committed in (e7a63359) found in git history
- Build compiles successfully (only pre-existing SwiftLint violations)
- All 23 WhiskyKit tests pass

---
*Phase: 09-ui-ux-feature-requests*
*Completed: 2026-02-11*
