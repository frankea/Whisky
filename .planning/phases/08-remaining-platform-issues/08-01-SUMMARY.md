---
phase: 08-remaining-platform-issues
plan: 01
subsystem: wine-environment
tags: [environment-builder, launcher-presets, macos-compatibility, provenance, fix-metadata]

# Dependency graph
requires:
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder with layer-based cascade and provenance tracking
provides:
  - FixCategory enum for classifying environment variable fixes
  - LauncherFixDetail struct with key/value/reason/category for launcher presets
  - MacOSFix struct with version-gated fix registry and activeFixes() query
  - EnvironmentBuilder provenance entries with optional reason field
  - set(_:_:layer:reason:) overload for reason-annotated environment entries
affects: [08-remaining-platform-issues, ui-environment-inspector]

# Tech tracking
tech-stack:
  added: []
  patterns: [fix-registry-pattern, reason-annotated-provenance, caseless-enum-registry]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Wine/LauncherFixDetails.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Wine/LauncherPresets.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/MacOSCompatibility.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/EnvironmentBuilder.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift

key-decisions:
  - "FixCategory enum at module scope (ClipboardPolicy pattern) for shared use by LauncherFixDetail and MacOSFix"
  - "MacOSCompatibilityFixes as caseless enum (GPUDetection pattern) for static registry namespace"
  - "fixDetails() extracted to LauncherFixDetails.swift extension for SwiftLint file_length compliance"
  - "WINEESYNC conditional logic preserved as special case in applyMacOSCompatibilityFixes (state-dependent)"
  - "Reason storage as separate per-layer dictionary in EnvironmentBuilder (not embedded in layers dict)"

patterns-established:
  - "Fix registry pattern: static array of typed fix structs with version gating and reason strings"
  - "Reason-annotated provenance: set(_:_:layer:reason:) for human-readable fix explanations in UI"

# Metrics
duration: 13min
completed: 2026-02-11
---

# Phase 08 Plan 01: Fix Metadata and Provenance Summary

**Structured fix metadata with FixCategory enum, LauncherFixDetail/MacOSFix structs, and reason-annotated EnvironmentBuilder provenance**

## Performance

- **Duration:** 13 min
- **Started:** 2026-02-11T06:49:06Z
- **Completed:** 2026-02-11T07:02:08Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Added FixCategory enum and LauncherFixDetail struct for per-launcher structured fix metadata across all 7 launchers
- Refactored MacOSCompatibility to use a static MacOSFix registry with version-gated entries and human-readable reasons
- Extended EnvironmentBuilder provenance with optional reason field, wired through platform and launcher layers
- Zero breaking changes to existing environmentOverrides() and applyMacOSCompatibilityFixes() APIs

## Task Commits

Each task was committed atomically:

1. **Task 1: Add structured fix metadata to LauncherPresets and MacOSCompatibility** - `47b60bdf` (feat)
2. **Task 2: Extend EnvironmentBuilder provenance with reason field** - `43f945cd` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Wine/LauncherPresets.swift` - Added FixCategory enum, LauncherFixDetail struct, note on environmentOverrides()
- `WhiskyKit/Sources/WhiskyKit/Wine/LauncherFixDetails.swift` - Extension with fixDetails() returning structured metadata per launcher
- `WhiskyKit/Sources/WhiskyKit/Wine/MacOSCompatibility.swift` - Added MacOSFix struct, MacOSCompatibilityFixes registry, activeFixes() query
- `WhiskyKit/Sources/WhiskyKit/Wine/EnvironmentBuilder.swift` - Added reason field to provenance Entry, set overload with reason, reasons storage
- `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` - Wired platform layer to use MacOSFix reasons, launcher layer to use fixDetails reasons

## Decisions Made
- FixCategory placed at module scope following ClipboardPolicy pattern for shared use by both LauncherFixDetail and MacOSFix
- MacOSCompatibilityFixes implemented as caseless enum (GPUDetection pattern) for static registry namespace
- fixDetails() extracted to separate extension file (LauncherFixDetails.swift) because adding it to LauncherPresets.swift exceeded SwiftLint 400-line file_length limit
- WINEESYNC conditional logic kept as special case in applyMacOSCompatibilityFixes() because it depends on existing environment state (cannot be a simple registry entry)
- Reason storage uses separate per-layer dictionary rather than embedded in the layers dict to avoid changing the String? value type semantics

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extracted fixDetails() to separate file for SwiftLint compliance**
- **Found during:** Task 2 (during xcode build verification)
- **Issue:** Adding fixDetails() to LauncherPresets.swift pushed it to 458 lines, exceeding the 400-line SwiftLint file_length limit
- **Fix:** Extracted fixDetails() into LauncherFixDetails.swift as a LauncherType extension
- **Files modified:** LauncherPresets.swift, LauncherFixDetails.swift (new)
- **Verification:** SwiftLint passes, xcode build succeeds
- **Committed in:** 43f945cd (Task 2 commit)

**2. [Rule 1 - Bug] Removed superfluous swiftlint disable command**
- **Found during:** Task 2 (during xcode build verification)
- **Issue:** After refactoring MacOSCompatibility.swift, a `swiftlint:disable:next identifier_name` on `allVersions` was no longer needed (no violation triggered)
- **Fix:** Removed the superfluous disable command
- **Files modified:** MacOSCompatibility.swift
- **Verification:** SwiftLint passes without warnings
- **Committed in:** 43f945cd (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes necessary for build compliance. No scope creep.

## Issues Encountered
- 2 pre-existing test failures in EnvironmentVariablesTests (testEnvironmentVariablesWithDXVKAsync, testEnvironmentVariablesWithPerformancePreset) confirmed as pre-existing by testing on clean git state before changes

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Fix metadata structs ready for UI integration in environment inspector views
- activeFixes() API ready for displaying platform-level fix provenance
- Reason field flows through all resolution paths for launcher and macOS compatibility layers

## Self-Check: PASSED

All files verified present. Both commits (47b60bdf, 43f945cd) confirmed in git log.

---
*Phase: 08-remaining-platform-issues*
*Completed: 2026-02-11*
