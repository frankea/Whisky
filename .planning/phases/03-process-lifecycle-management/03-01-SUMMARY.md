---
phase: 03-process-lifecycle-management
plan: 01
subsystem: wine
tags: [process-management, tasklist, wineserver, csv-parsing, type-system]

# Dependency graph
requires: []
provides:
  - WineProcess struct and ProcessKind/ProcessSource/ShutdownState enums for process UI
  - Wine.isWineserverRunning for per-bottle liveness probe
  - Wine.parseTasklistOutput for tasklist CSV parsing
  - Wine.gracefulKillProcess and forceKillProcess for per-process termination
  - ProcessRegistry.getProcessCount and hasActiveProcesses for badge indicators
affects: [03-02-PLAN, 03-03-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: [Wine extension file per feature domain, static set lookup for process classification, quoted CSV field parsing]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Wine/WineProcessTypes.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/Wine+ProcessManagement.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift

key-decisions:
  - "ProcessKind.classify uses static Set<String> lookup for O(1) classification"
  - "parseTasklistOutput is a pure non-MainActor function for testability"
  - "File-level private logger used in extension (matching Wine.swift pattern)"
  - "clearRegistry made public for ViewModel shutdown cleanup"

patterns-established:
  - "Wine+Feature.swift: separate extension files for each feature domain"
  - "ProcessKind.classify: static set lookup with lowercased input for case-insensitive matching"

# Metrics
duration: 3min
completed: 2026-02-09
---

# Phase 3 Plan 1: Process Types and Wine Helpers Summary

**WineProcess type system with ProcessKind classification, tasklist CSV parser, wineserver -k0 probe, and per-process taskkill helpers**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-09T17:47:02Z
- **Completed:** 2026-02-09T17:50:28Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created WineProcess, ProcessKind, ProcessSource, and ShutdownState shared types for the entire process lifecycle feature
- Added Wine.parseTasklistOutput that handles quoted CSV fields with header skipping, replacing the inline parsing in RunningProcessesView
- Added Wine.isWineserverRunning using the non-spawning wineserver -k0 probe pattern
- Enhanced ProcessRegistry with efficient count queries (getProcessCount, hasActiveProcesses) and public clearRegistry

## Task Commits

Each task was committed atomically:

1. **Task 1: Create WineProcess shared type definitions** - `ff44319d` (feat)
2. **Task 2: Add Wine process helpers and enhance ProcessRegistry** - `a653c034` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Wine/WineProcessTypes.swift` - ProcessKind, ProcessSource, ShutdownState enums and WineProcess struct
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine+ProcessManagement.swift` - isWineserverRunning, parseTasklistOutput, gracefulKillProcess, forceKillProcess
- `WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift` - getProcessCount, hasActiveProcesses, public clearRegistry

## Decisions Made
- ProcessKind.classify uses static Set<String> lookup for O(1) classification (matching the plan's known-name set approach)
- parseTasklistOutput is a pure non-@MainActor function (no side effects, easy to unit test)
- Used file-level private logger in extension file, matching the pattern in Wine.swift
- clearRegistry changed from private to public so ViewModel can clear after shutdown

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All shared types and Wine helpers are ready for Plan 02 (BottleVM process monitoring) and Plan 03 (UI integration)
- ProcessKind.classify, parseTasklistOutput, and isWineserverRunning are the foundation the ViewModel will call
- ProcessRegistry count queries are ready for badge indicators

## Self-Check: PASSED

All files found, all commits verified.

---
*Phase: 03-process-lifecycle-management*
*Completed: 2026-02-09*
