---
phase: 09-ui-ux-feature-requests
plan: 05
subsystem: data-model
tags: [run-log, persistence, plist, wine-integration, process-tracking]

# Dependency graph
requires:
  - phase: 05-stability-diagnostics
    provides: ProgramRunResult, makeFileHandleWithURL, DiagnosisHistory persistence pattern
provides:
  - RunLogEntry and RunLogHistory data models with Codable persistence
  - RunLogStore caseless enum for per-program run history persistence
  - Wine.runProgram integration creating and updating run log entries
  - ProgramRunResult.runLogEntryId for UI correlation
affects: [09-06-run-history-ui]

# Tech tracking
tech-stack:
  added: []
  patterns: [per-program sidecar plist persistence, auto-pruning bounded history, run log entry lifecycle]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Whisky/RunLog.swift
    - WhiskyKit/Tests/WhiskyKitTests/RunLogTests.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift

key-decisions:
  - "Run history stored in separate .run-history.plist per program (not in ProgramSettings) to avoid bloating main settings"
  - "Log file names stored as relative paths (not absolute URLs) so entries survive bottle moves"
  - "RunLogStore as caseless enum following GPUDetection/DiagnosisHistory pattern for static utility namespace"
  - "Auto-cleanup of log files for pruned entries during append"
  - "Plist encoding rounds Date to whole seconds (acceptable for run log timestamps)"

patterns-established:
  - "RunLogEntry lifecycle: create on start -> persist running state -> update on exit -> persist completed state"
  - "Bounded history with caller-returned pruned entries for cleanup coordination"

# Metrics
duration: 6min
completed: 2026-02-11
---

# Phase 09 Plan 05: Console Persistence Data Model Summary

**RunLogEntry/RunLogHistory data models with plist persistence and Wine.runProgram integration for per-program run tracking**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-11T08:30:51Z
- **Completed:** 2026-02-11T08:37:11Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- RunLogEntry struct tracking id, startTime, endTime, exitCode, logFileName, programName, and WINEDEBUG metadata
- RunLogHistory with auto-pruning at 10 entries per program, returning pruned entries for log file cleanup
- RunLogStore persistence to separate .run-history.plist file per program in Program Settings directory
- Wine.runProgram creates entry on start and updates on exit with exit code and WINEDEBUG flag
- ProgramRunResult extended with runLogEntryId for console UI correlation (Plan 06)
- 22 unit tests covering entry lifecycle, pruning, Codable round-trip, and persistence

## Task Commits

Each task was committed atomically:

1. **Task 1: RunLogEntry and RunLogHistory data models with persistence** - `9f46cb8f` (feat)
2. **Task 2: Integrate RunLog with Wine.runProgram process execution** - `2ffb4b1d` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Whisky/RunLog.swift` - RunLogEntry, RunLogHistory, RunLogStore data models with Codable persistence
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` - RunLog integration in runProgram; ProgramRunResult extended with runLogEntryId
- `WhiskyKit/Tests/WhiskyKitTests/RunLogTests.swift` - 22 unit tests for entry lifecycle, pruning, Codable round-trip, persistence

## Decisions Made
- Run history stored in separate `.run-history.plist` per program (not in ProgramSettings) to avoid bloating main settings file
- Log file names stored as relative paths (not absolute URLs) so entries survive bottle moves
- RunLogStore as caseless enum following the GPUDetection/DiagnosisHistory pattern for static utility namespace
- Auto-cleanup of log files for pruned entries during append in Wine.runProgram
- Plist encoding rounds Date to whole seconds; test accuracy tolerance set to 1.0s accordingly

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Plist PropertyListEncoder rounds Date to whole seconds, causing Codable round-trip equality checks to fail with sub-second precision. Fixed test assertions to use field-by-field comparison with 1.0s accuracy tolerance for timestamps.
- URL.path() vs URL.path(percentEncoded:) returns different formats; fixed test to use path(percentEncoded: false) for consistent path string comparison.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Data foundation complete for Plan 06 (run history UI)
- RunLogStore.load/save API ready for UI layer to display and manage run history
- ProgramRunResult.runLogEntryId enables direct navigation to log entries from run completion
- Existing dual streaming (UI + disk) already in place; no changes needed for console output

## Self-Check: PASSED

- All 3 created/modified files verified on disk
- Both task commits (9f46cb8f, 2ffb4b1d) found in git history
- Build succeeds, 22/22 RunLog tests pass

---
*Phase: 09-ui-ux-feature-requests*
*Completed: 2026-02-11*
