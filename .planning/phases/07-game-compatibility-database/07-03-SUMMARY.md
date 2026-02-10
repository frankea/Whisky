---
phase: 07-game-compatibility-database
plan: 03
subsystem: database
tags: [game-database, applicator, staleness, snapshot, settings-mutation, plist, undo-revert]

# Dependency graph
requires:
  - phase: 07-game-compatibility-database
    plan: 01
    provides: "GameDBEntry, GameConfigVariant, GameConfigVariantSettings, GameConfigSnapshot, TestedWith"
  - phase: 02-configuration-foundation
    provides: "BottleSettings, DLLOverrideEntry, EnhancedSync, GraphicsBackend"
provides:
  - "GameConfigApplicator -- apply/revert game configurations to bottles via BottleSettings mutation"
  - "ConfigChange -- before/after diff preview grouped by category with high-impact flags"
  - "StalenessChecker -- 3-trigger freshness detection for game database entries"
  - "StalenessResult/StalenessReason -- structured staleness output with warning message"
affects: [07-04, 07-05, 07-06]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Caseless enum for stateless utility (GameConfigApplicator, StalenessChecker)", "PropertyListEncoder snapshot before mutation for lossless undo", "DLL override deduplication by name with variant-wins precedence", "Version string parsing for staleness comparison (major.minor.patch)"]

key-files:
  created:
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/GameConfigApplicator.swift"
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/StalenessChecker.swift"
    - "WhiskyKit/Tests/WhiskyKitTests/GameApplicatorTests.swift"
  modified: []

key-decisions:
  - "DLL override deduplication by name during apply: variant value wins over existing"
  - "Full BottleSettings snapshot (not delta) for simple and reliable undo"
  - "Staleness thresholds: 90 days, >1 minor macOS delta, different Wine major"
  - "ConfigChange preview uses string descriptions for all value types (no generics needed)"

patterns-established:
  - "GameConfigApplicator.apply() returns snapshot for caller to track/display"
  - "StalenessChecker.check() returns structured result with isStale, reasons, warningMessage"
  - "Test fixtures use Bottle(bottleUrl:) with temp directory and default Metadata.plist"

# Metrics
duration: 6min
completed: 2026-02-10
---

# Phase 7 Plan 03: Config Applicator & Staleness Summary

**One-click apply/revert engine with PropertyListEncoder snapshots, DLL override deduplication, preview diff, and 3-trigger staleness detection**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-10T22:22:25Z
- **Completed:** 2026-02-10T22:28:40Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- GameConfigApplicator applies variant settings to BottleSettings via direct property mutation (no translation layer), with PropertyListEncoder snapshot for lossless undo
- DLL overrides appended with deduplication by name (variant value wins), preserving existing overrides
- Preview diff generates ConfigChange array grouped by category (Graphics, Performance, DLL Overrides, Environment Variables, Winetricks) with high-impact flags
- StalenessChecker detects stale entries via 90-day threshold, macOS minor version delta >1, and Wine major version mismatch, returning structured StalenessResult with user-friendly warning message
- 19 tests passing: 10 applicator tests (apply, revert, DLL dedup, preview, multi-setting) + 9 staleness tests (fresh, date-expired, macOS mismatch, Wine mismatch, multiple reasons, boundary cases)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement GameConfigApplicator with apply and revert** - `27c98fc2` (feat)
2. **Task 2: Implement StalenessChecker for entry freshness detection** - `90a0df21` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameConfigApplicator.swift` - Apply/revert engine with snapshot, preview diff, pending winetricks verbs
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/StalenessChecker.swift` - Staleness detection with 3-trigger logic and structured result
- `WhiskyKit/Tests/WhiskyKitTests/GameApplicatorTests.swift` - 19 tests for applicator and staleness checker

## Decisions Made
- **DLL override deduplication**: During apply, variant overrides replace existing entries with the same DLL name rather than appending duplicates. This follows the plan's "deduplicate by DLL name, prefer variant value" specification.
- **Full snapshot approach**: The snapshot captures the entire BottleSettings via PropertyListEncoder, not a delta. This is simpler and matches the documented trade-off: "Revert restores settings to their exact state before apply."
- **ConfigChange string descriptions**: Preview uses human-readable strings for all values (e.g., "ESync", "Enabled"/"Disabled") rather than generic value types. This simplifies the UI layer.
- **Staleness thresholds**: Exactly match CONTEXT.md specification: >90 days for date, >1 minor release for macOS, different major for Wine.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed test values to match actual BottleSettings defaults**
- **Found during:** Task 1 (test verification)
- **Issue:** Tests assumed dxvkAsync defaults to false and enhancedSync defaults to .none, but actual defaults are dxvkAsync=true and enhancedSync=.msync
- **Fix:** Corrected test values: apply dxvkAsync=false (not true) to differ from default; apply enhancedSync=.esync (not .msync) in preview test
- **Files modified:** WhiskyKit/Tests/WhiskyKitTests/GameApplicatorTests.swift
- **Verification:** All 19 tests pass after correction
- **Committed in:** 27c98fc2 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Test value correction only. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GameConfigApplicator ready for UI integration in Plan 05 (preview sheet, apply action)
- StalenessChecker ready for UI display in Plan 05 (staleness warning banner in detail/preview views)
- ConfigChange model ready for diff preview in GameConfigPreviewSheet
- PendingWinetricksVerbs ready for preflight display in UI

## Self-Check: PASSED

All 3 files verified on disk. Both commit hashes (27c98fc2, 90a0df21) found in git log.

---
*Phase: 07-game-compatibility-database*
*Completed: 2026-02-10*
