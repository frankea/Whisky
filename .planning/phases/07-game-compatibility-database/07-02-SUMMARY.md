---
phase: 07-game-compatibility-database
plan: 02
subsystem: database
tags: [matching-algorithm, tiered-scoring, fuzzy-search, steam-appid, game-database]

# Dependency graph
requires:
  - phase: 07-game-compatibility-database
    plan: 01
    provides: "GameDBEntry, MatchResult, MatchTier, GameDBLoader, CompatibilityRating"
provides:
  - "GameMatcher -- tiered scoring algorithm (hard/strong/fuzzy)"
  - "ProgramMetadata -- input struct for matching programs against database"
  - "GameDBLoader tests validating Bundle.module JSON loading"
  - "searchEntries -- case-insensitive tokenized title/alias search"
affects: [07-03, 07-04, 07-05, 07-06]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Three-tier confidence scoring (hard 0.95-1.0, strong 0.7-0.9, fuzzy 0.3-0.6)", "Generic exe denylist with -0.3 penalty for false-match prevention", "Caseless enum for stateless matching utilities (GPUDetection pattern)"]

key-files:
  created:
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/GameMatcher.swift"
    - "WhiskyKit/Tests/WhiskyKitTests/GameMatcherTests.swift"
  modified: []

key-decisions:
  - "GameMatcher as caseless enum following GPUDetection pattern for static utility namespace"
  - "bestMatch returns nil for ambiguous results (gap < 0.1) unless top is hardIdentifier tier"
  - "Fuzzy score capped at 0.69 to stay below strong heuristic tier boundary"
  - "Variant auto-selection prefers isDefault; no strict constraint filtering (soft preference)"

patterns-established:
  - "ProgramMetadata as the standard input struct for game matching operations"
  - "Tokenized search: split on non-alphanumeric, lowercase, prefix matching"
  - "Score tiers map directly to MatchTier enum values for downstream UX decisions"

# Metrics
duration: 4min
completed: 2026-02-10
---

# Phase 7 Plan 02: Loader & Matcher Summary

**Tiered game matching algorithm with hard identifiers (Steam App ID), strong heuristics (exe name), fuzzy token matching, generic exe penalty, and case-insensitive search**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-10T22:22:15Z
- **Completed:** 2026-02-10T22:26:17Z
- **Tasks:** 2
- **Files modified:** 2 created

## Accomplishments
- GameDBLoader tests validate Bundle.module JSON loading, full field decoding, and ISO 8601 date parsing
- GameMatcher implements three-tier scoring: hard identifiers (Steam App ID at 1.0, fingerprint at 0.95), strong heuristics (exe name at 0.85-0.90), and fuzzy token matching (0.3-0.6)
- Generic executable denylist (launcher.exe, setup.exe, etc.) applies -0.3 penalty to prevent false matches
- bestMatch returns nil for ambiguous close scores (within 0.1 gap), except for hard identifier matches which always win
- searchEntries provides case-insensitive tokenized search across titles and aliases
- 13 tests pass covering all tiers, penalties, ambiguity detection, and search functionality

## Task Commits

Each task was committed atomically:

1. **Task 1: Create GameDBLoader tests** - `12e9514d` (test)
2. **Task 2: Implement GameMatcher tiered scoring algorithm** - `37caafec` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameMatcher.swift` - Tiered matching algorithm with ProgramMetadata, match(), bestMatch(), searchEntries()
- `WhiskyKit/Tests/WhiskyKitTests/GameMatcherTests.swift` - 13 tests for loader and all matching tiers

## Decisions Made
- **GameMatcher as caseless enum**: Follows GPUDetection pattern for stateless utility namespace with only static methods.
- **bestMatch ambiguity handling**: Returns nil when top-2 scores are within 0.1 gap, but hard identifier matches (Steam App ID) always return since they are definitive.
- **Fuzzy score ceiling**: Capped at 0.69 to maintain clear separation from strong heuristic tier (0.7+).
- **Soft variant selection**: Auto-selects isDefault variant without strict constraint exclusion -- tested architecture is a preference, not a hard filter.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Moved aside untracked GameApplicatorTests.swift from future plan**
- **Found during:** Task 2 (build verification)
- **Issue:** An untracked GameApplicatorTests.swift from a future plan (07-04) was present on disk and caused Swift 6 actor isolation compilation errors
- **Fix:** Temporarily moved file to /tmp during build/test, restored afterward (file remains untracked)
- **Files modified:** None committed
- **Verification:** Build and all 13 tests pass with file moved aside

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Essential for compilation. No scope creep.

## Issues Encountered
- GameDBLoader.swift, GameDB.json, and Package.swift resources path already existed from Plan 07-07 (executed out of order). Task 1 focused on adding the loader tests rather than re-creating existing infrastructure.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GameMatcher scoring algorithm ready for Plan 03 (UI integration)
- ProgramMetadata struct ready for automatic metadata extraction from Bottle programs
- searchEntries ready for search UI implementation
- bestMatch ambiguity handling ready for "Possible matches" UI flow

## Self-Check: PASSED

All 5 files verified on disk. Both commit hashes (12e9514d, 37caafec) found in git log.

---
*Phase: 07-game-compatibility-database*
*Completed: 2026-02-10*
