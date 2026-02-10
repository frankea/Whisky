---
phase: 05-stability-diagnostics
plan: 01
subsystem: diagnostics
tags: [crash-classification, regex, json, swift-concurrency, tdd, wine-debug]

# Dependency graph
requires:
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder pattern for WINEDEBUG integration
provides:
  - CrashClassifier pipeline (classify log text into CrashDiagnosis)
  - CrashPattern/CrashCategory/ConfidenceTier/DiagnosisMatch/RemediationAction data types
  - PatternLoader for JSON-backed pattern database (Bundle.module SPM resources)
  - WineDebugPreset enum for WINEDEBUG channel configuration
  - patterns.json with 22 patterns covering all 7 category groups
  - remediations.json with 9 action definitions
affects: [05-02 persistence, 05-03 process integration, 05-04 UI, 05-05 export]

# Tech tracking
tech-stack:
  added: [Swift Regex, SPM resource bundles]
  patterns: [caseless enum for stateless utilities (PatternLoader), substring prefilter before regex, nonisolated(unsafe) for non-Sendable Regex in Sendable struct]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashClassifier.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashPattern.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashCategory.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/ConfidenceTier.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashDiagnosis.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosisMatch.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/RemediationAction.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/PatternLoader.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/WineDebugPreset.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/remediations.json
    - WhiskyKit/Tests/WhiskyKitTests/CrashClassifierTests.swift
  modified:
    - WhiskyKit/Package.swift

key-decisions:
  - "nonisolated(unsafe) for Regex storage in CrashPattern (Swift 6 Sendable compliance)"
  - "SPM .process() flattens resource directories; PatternLoader loads without subdirectory path"
  - "Added otherUnknown pattern (wine-nonzero-exit) to ensure all 7 categories have coverage"
  - "WineDebugPreset uses presetDescription instead of description to avoid shadowing CustomStringConvertible"

patterns-established:
  - "Substring prefilter: check String.contains() before Regex evaluation for performance"
  - "PatternLoader as caseless enum (following GPUDetection pattern)"
  - "Eager regex compilation at CrashClassifier init, lazy compilation in CrashPattern.match()"
  - "Versioned JSON resource schema (version field for future migration)"

# Metrics
duration: 7min
completed: 2026-02-10
---

# Phase 05 Plan 01: Crash Classification Pipeline Summary

**Line-by-line Wine log classifier with 22 regex patterns across 7 crash categories, substring prefilter optimization, 3-tier confidence model, and 9 remediation action definitions**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-10T04:30:45Z
- **Completed:** 2026-02-10T04:38:27Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments
- Complete crash classification data model: CrashCategory (7 cases), CrashPattern, PatternSeverity, ConfidenceTier (3-tier from numeric score), DiagnosisMatch, RemediationAction (4 action types, 3 risk levels), CrashDiagnosis
- CrashClassifier 5-step pipeline: split lines, match patterns with substring prefilter fast-path, aggregate by category, sort by confidence+severity, collect remediation IDs
- JSON pattern database: 22 patterns covering DLL failures (6), crash/fatal (4), graphics (5), prefix (2), networking (2), anti-cheat (2), other (1); 9 remediation actions
- WineDebugPreset with 4 curated WINEDEBUG channel presets (normal, crash, dllLoad, verbose)
- 39 unit tests: pattern loading, confidence tiers, severity ordering, per-pattern positive matches, classifier pipeline for each category, multi-match sorting, prefilter optimization, remediation collection

## Task Commits

Each task was committed atomically:

1. **Task 1: Data Types, JSON Resources, and PatternLoader** - `544b8288` (feat)
2. **Task 2: CrashClassifier, WineDebugPreset, and Test Coverage** - `f1d437dc` (feat)

_TDD tasks: types and tests created together due to Swift compilation requirements_

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashCategory.swift` - 7-case enum with displayName and sfSymbol
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashPattern.swift` - Pattern struct with substring prefilter and lazy regex compilation
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/ConfidenceTier.swift` - 3-tier enum with score-based init
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashDiagnosis.swift` - Classification result with remediation resolution
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosisMatch.swift` - Individual match with pattern, line, captures
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/RemediationAction.swift` - Action definitions with type, risk, undo path
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/PatternLoader.swift` - JSON loading from Bundle.module with debug/release failure modes
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashClassifier.swift` - 5-step classification pipeline
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/WineDebugPreset.swift` - WINEDEBUG channel presets
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json` - 22 pattern definitions (version 1)
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/remediations.json` - 9 action definitions (version 1)
- `WhiskyKit/Tests/WhiskyKitTests/CrashClassifierTests.swift` - 39 unit tests
- `WhiskyKit/Package.swift` - Added .process("Diagnostics/Resources/") for SPM resource bundle

## Decisions Made
- **nonisolated(unsafe) for Regex**: Swift 6 strict concurrency requires Sendable on CrashPattern, but Foundation.Regex is not Sendable. Used `nonisolated(unsafe)` since the regex is compiled once and thereafter read-only.
- **SPM .process() resource handling**: `.process()` flattens directory structure in the bundle, so PatternLoader uses `Bundle.module.url(forResource:withExtension:)` without subdirectory parameter.
- **otherUnknown category coverage**: Added `wine-nonzero-exit` pattern to ensure all 7 categories have at least one pattern, fulfilling the "covers all 7 category groups" requirement.
- **presetDescription property name**: Used `presetDescription` instead of `description` on WineDebugPreset to avoid shadowing CustomStringConvertible.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed SPM resource loading path**
- **Found during:** Task 1 (PatternLoader)
- **Issue:** PatternLoader used `subdirectory: "Diagnostics/Resources"` but SPM `.process()` flattens directory structure
- **Fix:** Removed subdirectory parameter from Bundle.module.url() calls
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Diagnostics/PatternLoader.swift
- **Verification:** Tests pass, resources load successfully
- **Committed in:** 544b8288

**2. [Rule 1 - Bug] Fixed Sendable compliance for CrashPattern**
- **Found during:** Task 1 (CrashPattern)
- **Issue:** Stored `Regex<AnyRegexOutput>?` property prevented Sendable conformance under Swift 6
- **Fix:** Added `nonisolated(unsafe)` annotation since regex is effectively immutable after compilation
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashPattern.swift
- **Verification:** Builds clean under Swift 6 strict concurrency
- **Committed in:** 544b8288

**3. [Rule 2 - Missing Critical] Added otherUnknown category pattern**
- **Found during:** Task 1 (test revealed gap)
- **Issue:** patterns.json had no pattern for the `otherUnknown` category, failing the "all 7 categories" requirement
- **Fix:** Added `wine-nonzero-exit` pattern for non-zero Wine process exit codes
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json
- **Verification:** testPatternsCoversAllCategories passes
- **Committed in:** 544b8288

---

**Total deviations:** 3 auto-fixed (1 blocking, 1 bug, 1 missing critical)
**Impact on plan:** All fixes necessary for correctness and completeness. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All data types and classifier pipeline ready for consumption by subsequent plans
- Plan 05-02 (persistence) can use CrashDiagnosis for storage
- Plan 05-03 (process integration) can use CrashClassifier.classify() and WineDebugPreset
- Plan 05-04 (UI) can use CrashCategory.displayName/sfSymbol and ConfidenceTier.displayName
- Plan 05-05 (export) can use CrashDiagnosis and RemediationAction

## Self-Check: PASSED

All 13 files found. Both task commits verified (544b8288, f1d437dc).

---
*Phase: 05-stability-diagnostics*
*Completed: 2026-02-10*
