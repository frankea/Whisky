---
phase: 10-guided-troubleshooting
plan: 05
subsystem: troubleshooting
tags: [persistence, plist, session-store, history, fix-applicator, undo, atomic-writes, staleness-detection]

# Dependency graph
requires:
  - phase: 10-guided-troubleshooting
    provides: TroubleshootingSession, FixAttempt, PreflightData, SymptomCategory, TroubleshootingSessionStoring protocol, CheckResult types
  - phase: 05-stability-diagnostics
    provides: DiagnosisHistory/RemediationTimeline persistence patterns
  - phase: 04-graphics-configuration
    provides: GraphicsBackend enum for fix applicator backend switching
  - phase: 06-audio-troubleshooting
    provides: AudioDriverMode, AudioLatencyPreset for audio fix application
provides:
  - TroubleshootingSessionStore conforming to TroubleshootingSessionStoring protocol
  - TroubleshootingHistory bounded per-bottle completed session history (20 entries / 30 days)
  - TroubleshootingHistoryEntry redacted session summary struct
  - StalenessChange struct for "Since you left" resume banner
  - FixApplicator caseless enum with preview, apply, and undo for 10 fix types
  - FixPreview struct for diff-style change preview
affects: [10-06, 10-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TroubleshootingSessionStore: struct conforming to TroubleshootingSessionStoring with atomic plist I/O"
    - "TroubleshootingHistory: age-based eviction (30 days) + count-based FIFO eviction (20 entries)"
    - "FixApplicator: caseless enum with @MainActor static methods for preview/apply/undo"
    - "StalenessChange: value-object driving resume banner from preflight snapshot diff"

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingSessionStore.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingHistory.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingHistoryEntry.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/FixApplicator.swift
  modified: []

key-decisions:
  - "StalenessChange uses >50% or >5 delta threshold for process count significance"
  - "Audio driver and buffer size fixes return .pending result (registry writes are async)"
  - "FixApplicator delegates winetricks/dependency installs to existing infrastructure with .pending result"
  - "TroubleshootingHistory.save is non-throwing (logs errors internally) for simpler call sites"

patterns-established:
  - "Session persistence: save/load/delete/complete lifecycle with atomic plist I/O"
  - "Fix applicator pattern: preview (read-only) -> apply (capture before, mutate) -> undo (restore before)"
  - "Staleness detection: snapshot diff between stored and fresh preflight data"

# Metrics
duration: 10min
completed: 2026-02-12
---

# Phase 10 Plan 05: Session Persistence and Fix Application Summary

**TroubleshootingSessionStore with atomic plist persistence, 14-day staleness expiry, bounded history (20/30-day), and FixApplicator with preview/apply/undo for 10 fix types**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-12T04:03:36Z
- **Completed:** 2026-02-12T04:14:21Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Built TroubleshootingSessionStore conforming to TroubleshootingSessionStoring protocol with atomic plist I/O, 14-day staleness expiry, and bounded history archival
- TroubleshootingHistory with dual eviction (30-day age + 20-entry FIFO) following DiagnosisHistory pattern from Phase 5
- FixApplicator with 10 fix types covering graphics backend, DXVK async, audio driver, buffer size, enhanced sync, controller compat, winetricks, dependencies, diagnostics, and wineserver restart
- StalenessChange struct enables "Since you left" resume banner by diffing preflight snapshots

## Task Commits

Each task was committed atomically:

1. **Task 1: TroubleshootingSessionStore, TroubleshootingHistory, and TroubleshootingHistoryEntry** - `06ae6ac6` (feat)
2. **Task 2: FixApplicator with preview, apply, and undo** - `904e7833` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingSessionStore.swift` - Concrete TroubleshootingSessionStoring implementation with save/load/delete/complete lifecycle, staleness detection, and atomic writes
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingHistory.swift` - Bounded history with 20-entry / 30-day retention, plist persistence, and FIFO eviction
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingHistoryEntry.swift` - Redacted session summary (no raw logs) with symptom category, outcome, findings, and fix results
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FixApplicator.swift` - Caseless enum with preview/apply/undo for 10 fix types, FixPreview struct for diff display

## Decisions Made
- StalenessChange uses >50% or >5 delta threshold for process count to avoid false positives from normal process churn
- Audio driver and buffer size fixes return `.pending` result since the registry writes are async operations; the engine verify step confirms completion
- FixApplicator delegates winetricks verb and dependency installs to existing infrastructure with `.pending` result; the actual async operations are triggered by the UI layer
- TroubleshootingHistory.save() is non-throwing and logs errors internally for simpler call sites (following the pattern where callers rarely handle save errors)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TroubleshootingSessionStore ready for engine integration (Plan 06 wizard UI will inject it)
- FixApplicator ready for engine's applyFix/undoLastFix methods to delegate to
- TroubleshootingHistory ready for history view in wizard completion screen
- StalenessChange ready for resume banner UI in Plan 06

## Self-Check: PASSED

All 4 Swift files verified present. Both commits (06ae6ac6, 904e7833) verified in git log. swift build --package-path WhiskyKit succeeds. TroubleshootingSessionStore uses .atomic writes. TroubleshootingHistory evicts entries older than 30 days and caps at 20. Stale sessions (>14 days) return nil on load. FixApplicator.preview covers all 10 fixIds. FixApplicator.undo returns false for non-reversible fixes.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
