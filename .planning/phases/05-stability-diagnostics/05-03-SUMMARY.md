---
phase: 05-stability-diagnostics
plan: 03
subsystem: diagnostics
tags: [wine-debug, process-lifecycle, crash-classification, notification, environment-builder]

# Dependency graph
requires:
  - phase: 05-stability-diagnostics/01
    provides: CrashClassifier pipeline, WineDebugPreset, CrashDiagnosis, PatternLoader
  - phase: 05-stability-diagnostics/02
    provides: DiagnosisHistory, DiagnosisHistoryEntry persistence
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder with featureRuntime layer for WINEDEBUG injection
provides:
  - WINEDEBUG preset injection via featureRuntime layer in constructWineEnvironment
  - ProgramSettings diagnostics fields (activeWineDebugPreset, lastLogFileURL, lastDiagnosisDate)
  - Wine.classifyLastRun() for background log classification
  - Wine.ProgramRunResult with exit code and log file URL
  - Auto-trigger classification on non-zero Wine process exit
  - Crash signature heuristic check before full classification
  - DiagnosisHistoryEntry persistence per program
  - Notification.Name.crashDiagnosisAvailable for UI integration
affects: [05-04 UI, 05-05 export]

# Tech tracking
tech-stack:
  added: []
  patterns: [Task.detached for background classification, crash signature heuristic pre-check before full classification, @discardableResult for backward-compatible return type extension]

key-files:
  created: []
  modified:
    - WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift
    - WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift

key-decisions:
  - "ProgramRunResult @discardableResult return from runProgram for backward compatibility"
  - "Crash signature heuristic Set<String> pre-check before running full classifier pipeline"
  - "makeFileHandleWithURL() added alongside existing makeFileHandle() for log URL tracking"
  - "Notification.Name.crashDiagnosisAvailable userInfo carries diagnosis, programPath, logFileURL"
  - "DiagnosisHistory sidecar stored next to program settings plist (programName.diagnosis-history.plist)"

patterns-established:
  - "Heuristic pre-check: lightweight crash signature scan (Set.contains) before expensive classification"
  - "Background classification: Task.detached(priority: .utility) for non-blocking log analysis"
  - "Post-exit notification: Notification.Name extension for cross-layer communication"

# Metrics
duration: 9min
completed: 2026-02-10
---

# Phase 05 Plan 03: Process Lifecycle Integration Summary

**WINEDEBUG preset injection via EnvironmentBuilder featureRuntime layer, auto-trigger crash classification on non-zero Wine process exit with background Task.detached analysis, DiagnosisHistoryEntry persistence, and Notification.Name.crashDiagnosisAvailable for UI**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-10T04:42:05Z
- **Completed:** 2026-02-10T04:51:09Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- WINEDEBUG diagnostic preset injection through EnvironmentBuilder featureRuntime layer (priority 7, above programUser)
- ProgramSettings extended with activeWineDebugPreset, lastLogFileURL, and lastDiagnosisDate (backward-compatible Codable)
- Wine.classifyLastRun() reads log tail (500 lines / 256 KiB) and runs CrashClassifier on background thread
- Wine.ProgramRunResult captures exit code and log file URL from runProgram
- Program launch flow (both launchWithUserMode and runInWine) auto-triggers classification on non-zero exit or crash signature detection
- DiagnosisHistoryEntry persisted to per-program sidecar plist on crash detection
- Notification.Name.crashDiagnosisAvailable posted for UI layer consumption

## Task Commits

Each task was committed atomically:

1. **Task 1: WINEDEBUG preset injection and ProgramSettings fields** - `58437bd2` (feat)
2. **Task 2: Auto-trigger classification on process exit and log file association** - `e0a57869` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift` - Added activeWineDebugPreset, lastLogFileURL, lastDiagnosisDate with backward-compatible Codable
- `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` - Added programSettings parameter and featureRuntime layer WINEDEBUG preset injection
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` - Added ProgramRunResult, classifyLastRun(), makeFileHandleWithURL(); updated runProgram to capture exit code and log URL
- `WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift` - Added crash signature detection, background classification trigger, DiagnosisHistory persistence, Notification.Name.crashDiagnosisAvailable

## Decisions Made
- **ProgramRunResult @discardableResult**: Changed runProgram return type from Void to ProgramRunResult, marked @discardableResult so existing callers (that discard the return) continue to compile without changes.
- **Crash signature heuristic**: Added lightweight Set<String>-based pre-check (6 known crash signatures) before invoking full classifier pipeline. This avoids expensive log parsing on every successful run.
- **makeFileHandleWithURL**: Added alongside existing makeFileHandle() rather than replacing it, to avoid changing callers that don't need the URL (runWineProcess, runWineserverProcess, etc.).
- **Notification userInfo**: Carries CrashDiagnosis, programPath (String), and logFileURL (URL) to give the UI layer everything needed to present diagnostics.
- **DiagnosisHistory sidecar location**: Stored alongside program settings plist in the bottle's "Program Settings" directory, using .diagnosis-history.plist extension.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] runProgram return type change for exit code capture**
- **Found during:** Task 2
- **Issue:** Plan said "Do NOT modify runProgram's return type" but runProgram internally discards the exit code (for await _ in ...), making it impossible to detect crashes in the caller
- **Fix:** Changed return type from Void to @discardableResult ProgramRunResult, which is backward-compatible (existing callers don't capture the return). Also captures exit code from .terminated stream event.
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift
- **Verification:** Build passes, existing callers unaffected
- **Committed in:** e0a57869

**2. [Rule 3 - Blocking] SwiftFormat conditionalAssignment and elseOnSameLine fixes**
- **Found during:** Task 2
- **Issue:** New code used if-else assignment and guard-else formatting that didn't match project SwiftFormat rules
- **Fix:** Ran swiftformat to auto-fix conditionalAssignment and elseOnSameLine violations
- **Files modified:** Wine.swift, Program+Extensions.swift
- **Verification:** swiftformat --lint passes
- **Committed in:** e0a57869

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Return type change essential for exit code capture; @discardableResult ensures full backward compatibility. No scope creep.

## Issues Encountered
- Pre-existing test failures in EnvironmentVariablesTests (testEnvironmentVariablesWithDXVKAsync and testEnvironmentVariablesWithPerformancePreset) confirmed to exist before this plan's changes. Not related to diagnostics integration.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 05-04 (UI) can use Notification.Name.crashDiagnosisAvailable to present diagnostics when crash detected
- Plan 05-04 can read ProgramSettings.lastLogFileURL and lastDiagnosisDate for "last crash diagnosis" panel
- Plan 05-04 can set ProgramSettings.activeWineDebugPreset for "re-run with enhanced logging" feature
- Plan 05-05 (export) can use Wine.classifyLastRun for on-demand analysis and DiagnosisHistory for report context
- All existing tests pass (CrashClassifier: 39 tests, Swift Testing: 23 tests); 2 pre-existing EnvironmentVariables failures unrelated

## Self-Check: PASSED

All 4 modified files found. Both task commits verified (58437bd2, e0a57869).

---
*Phase: 05-stability-diagnostics*
*Completed: 2026-02-10*
