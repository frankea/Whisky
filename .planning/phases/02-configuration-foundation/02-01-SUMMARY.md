---
phase: 02-configuration-foundation
plan: 01
subsystem: core-data-model
tags: [environment-builder, dll-override, program-overrides, codable, sendable, tdd]

# Dependency graph
requires:
  - phase: 01-miscellaneous-fixes
    provides: BottleCleanupConfig pattern (private stored, proxy properties)
provides:
  - EnvironmentBuilder with 8-layer cascade and provenance tracking
  - DLLOverrideResolver with per-DLL composition and DXVK warning generation
  - DLLOverrideMode/Entry structured data model for WINEDLLOVERRIDES
  - ProgramOverrides with optional-field inheritance pattern
  - ProgramSettings.overrides field (backward-compatible)
  - BottleSettings.dllOverrides proxy (backward-compatible)
affects: [02-02 refactor, 02-03 winetricks, 02-04 UI, 05-diagnostics]

# Tech tracking
tech-stack:
  added: []
  patterns: [layered-builder, per-dll-composition, optional-field-inheritance, provenance-tracking]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Wine/EnvironmentBuilder.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/DLLOverride.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift
    - WhiskyKit/Tests/WhiskyKitTests/EnvironmentBuilderTests.swift
    - WhiskyKit/Tests/WhiskyKitTests/DLLOverrideTests.swift
    - WhiskyKit/Tests/WhiskyKitTests/ProgramOverridesTests.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleWineConfig.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleDXVKConfig.swift

key-decisions:
  - "EnvironmentBuilder uses [String: String?] per layer to support explicit key removal via nil"
  - "DLLOverrideResolver.managed uses tuple array (entry, source) instead of separate dictionaries"
  - "displayName on DLLOverrideMode uses plain strings instead of localized strings (localization deferred to UI phase)"
  - "Added Sendable to EnhancedSync and DXVKHUD enums for ProgramOverrides compatibility"

patterns-established:
  - "Layered builder: accumulate entries per layer, resolve() materializes final dict + provenance"
  - "Per-DLL composition: structured [DLLOverrideEntry] is source of truth, string rendered only at resolve time"
  - "Optional-field inheritance: nil = inherit from parent, all-nil isEmpty check"
  - "Backward-compatible extension: decodeIfPresent with default for new fields on existing Codable types"

# Metrics
duration: 5min
completed: 2026-02-09
---

# Phase 2 Plan 1: EnvironmentBuilder, DLL Override Resolution, and ProgramOverrides Summary

**8-layer EnvironmentBuilder with provenance tracking, per-DLL override composition with DXVK conflict warnings, and optional-field ProgramOverrides for per-program setting inheritance**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-09T08:10:22Z
- **Completed:** 2026-02-09T08:16:14Z
- **Tasks:** 3 (TDD: RED, GREEN, REFACTOR)
- **Files modified:** 10 (6 created, 4 modified)

## Accomplishments
- EnvironmentBuilder resolves 8 ordered layers where later layers win per-key, with provenance metadata tracking which layer set each variable
- DLLOverrideResolver composes per-DLL overrides from managed, bottle custom, and program custom sources, generating warnings when DXVK-managed DLLs are overridden
- ProgramOverrides provides an optional-field pattern where nil means "inherit from bottle," with full Codable round-trip support
- ProgramSettings and BottleSettings extended with backward-compatible new fields (existing plists decode without error)
- 24 new tests covering layer resolution, DLL composition, Codable round-trips, and backward compatibility

## Task Commits

Each task was committed atomically:

1. **Task 1: RED - Write failing tests** - `9c506fcf` (test)
2. **Task 2: GREEN - Implement types** - `4ae7ae85` (feat)
3. **Task 3: REFACTOR - Format and clean up** - `02b84190` (refactor)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Wine/EnvironmentBuilder.swift` - EnvironmentLayer enum, EnvironmentProvenance struct, EnvironmentBuilder struct with set/setAll/remove/resolve
- `WhiskyKit/Sources/WhiskyKit/Whisky/DLLOverride.swift` - DLLOverrideMode enum, DLLOverrideEntry struct, DLLOverrideSource enum, DLLOverrideWarning struct, DLLOverrideResolver struct with dxvkPreset and resolve()
- `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift` - ProgramOverrides struct with 12 optional fields and isEmpty computed property
- `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift` - Added overrides: ProgramOverrides? field with custom init(from:) using decodeIfPresent
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - Added customDLLOverrides stored property and dllOverrides public proxy
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleWineConfig.swift` - Added Sendable conformance to EnhancedSync
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleDXVKConfig.swift` - Added Sendable conformance to DXVKHUD
- `WhiskyKit/Tests/WhiskyKitTests/EnvironmentBuilderTests.swift` - 8 tests for layer resolution and provenance tracking
- `WhiskyKit/Tests/WhiskyKitTests/DLLOverrideTests.swift` - 10 tests for DLL override composition, warnings, and presets
- `WhiskyKit/Tests/WhiskyKitTests/ProgramOverridesTests.swift` - 6 tests for isEmpty, Codable round-trip, and backward compatibility

## Decisions Made
- EnvironmentBuilder uses `[String: String?]` per layer where `nil` values represent explicit key removal (allows a higher layer to remove a key set by a lower layer)
- DLLOverrideResolver.managed stores tuples `(entry: DLLOverrideEntry, source: DLLOverrideSource)` to keep entry and source tightly coupled
- DLLOverrideMode.displayName uses plain strings instead of localized strings since no localization infrastructure exists yet in WhiskyKit; localization will be added when the UI phase introduces the DLL override editor
- Added Sendable conformance to existing `EnhancedSync` and `DXVKHUD` enums -- these are frozen value-type enums with no mutable state, so Sendable is safe and non-breaking

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added Sendable conformance to EnhancedSync and DXVKHUD**
- **Found during:** Task 2 (GREEN - implement types)
- **Issue:** ProgramOverrides declares Sendable conformance but stores Optional<EnhancedSync> and Optional<DXVKHUD>, which were not Sendable. Swift 6 strict concurrency mode rejects this.
- **Fix:** Added `Sendable` to the protocol conformance lists of `EnhancedSync` and `DXVKHUD` enums
- **Files modified:** BottleWineConfig.swift, BottleDXVKConfig.swift
- **Verification:** Full test suite passes, no Sendable warnings
- **Committed in:** 4ae7ae85 (Task 2 commit)

**2. [Rule 1 - Bug] Fixed DLLOverrideMode.displayName using non-existent Bundle.whiskyKit**
- **Found during:** Task 2 (GREEN - implement types)
- **Issue:** Initial implementation used `String(localized:bundle:.whiskyKit)` but `Bundle.whiskyKit` does not exist as an extension
- **Fix:** Changed to plain string literals matching the CONTEXT.md display names
- **Files modified:** DLLOverride.swift
- **Verification:** Code compiles, displayName returns correct strings
- **Committed in:** 4ae7ae85 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes necessary for compilation under Swift 6 strict concurrency. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- EnvironmentBuilder, DLLOverrideResolver, and ProgramOverrides are ready for Plan 02-02 (refactor existing environment construction to use EnvironmentBuilder)
- ProgramSettings.overrides is ready for Plan 02-04 (per-program override UI)
- BottleSettings.dllOverrides is ready for Plan 02-04 (DLL override editor UI)
- All types are Sendable, Codable, and Equatable -- safe for cross-actor use and persistence

## Self-Check: PASSED

- All 7 created files verified present on disk
- All 3 task commits verified in git log (9c506fcf, 4ae7ae85, 02b84190)
- 24 tests pass (8 EnvironmentBuilder + 10 DLLOverride + 6 ProgramOverrides)
- Full WhiskyKit test suite passes with no regressions
- SwiftFormat lint passes on all modified/created files

---
*Phase: 02-configuration-foundation*
*Completed: 2026-02-09*
