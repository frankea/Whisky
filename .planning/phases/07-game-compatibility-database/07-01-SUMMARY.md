---
phase: 07-game-compatibility-database
plan: 01
subsystem: database
tags: [codable, json, plist, swift-testing, game-database, steam-acf]

# Dependency graph
requires:
  - phase: 02-configuration-foundation
    provides: "GraphicsBackend enum, EnhancedSync enum, DLLOverrideEntry model"
  - phase: 04-graphics-configuration
    provides: "GraphicsBackend with .recommended/.d3dMetal/.dxvk/.wined3d cases"
provides:
  - "GameDBEntry -- core game database entry model with variants"
  - "CompatibilityRating -- 5-tier rating enum (works/playable/unverified/broken/notSupported)"
  - "MatchResult/MatchTier -- tiered confidence scoring types"
  - "GameConfigSnapshot -- plist serialization for undo/revert"
  - "SteamAppManifest -- ACF parser for Steam App ID extraction"
  - "GameConfigVariantSettings -- settings map to BottleSettings property names"
affects: [07-02, 07-03, 07-04, 07-05, 07-06, 07-07]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Defensive decodeIfPresent with safe defaults for all optional JSON fields", "String-based EnhancedSync decoding fallback for JSON database readability", "Caseless enum for utility namespace (SteamAppManifest, following GPUDetection pattern)"]

key-files:
  created:
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBEntry.swift"
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBRating.swift"
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/MatchResult.swift"
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/GameConfigSnapshot.swift"
    - "WhiskyKit/Sources/WhiskyKit/GameDatabase/SteamAppManifest.swift"
    - "WhiskyKit/Tests/WhiskyKitTests/GameDatabaseTests.swift"
  modified: []

key-decisions:
  - "EnhancedSync decoded from plain strings in JSON database with fallback to native Codable format"
  - "GameConfigVariantSettings fields map 1:1 to BottleSettings property names for zero-translation apply"
  - "Single snapshot file per bottle (GameConfigSnapshot.plist) for single-undo design"
  - "programSettingsData keyed by String (URL string) instead of URL for Codable simplicity"

patterns-established:
  - "GameDatabase module namespace: WhiskyKit/Sources/WhiskyKit/GameDatabase/"
  - "JSON database entries use plain string values for enums without String raw values"
  - "GameConfigSnapshot plist save/load/delete static methods on the struct itself"

# Metrics
duration: 6min
completed: 2026-02-10
---

# Phase 7 Plan 01: Data Models Summary

**Codable game database models with 5-tier ratings, variant settings, ACF parsing, and plist snapshot undo**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-10T22:07:22Z
- **Completed:** 2026-02-10T22:13:33Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Defined complete GameDBEntry schema with variants, fingerprints, constraints, notes, known issues, and provenance
- CompatibilityRating enum with 5 tiers, Comparable ordering, SF Symbol names, and localized display names
- GameConfigVariantSettings maps directly to BottleSettings property names for zero-translation config application
- SteamAppManifest parses Valve ACF/VDF format and locates steam_appid.txt in exe directory hierarchy
- GameConfigSnapshot round-trips through PropertyListEncoder/Decoder with save/load/delete file I/O
- 16 tests covering all data model types, Codable round-trips, optional defaults, ACF parsing, and snapshot persistence

## Task Commits

Each task was committed atomically:

1. **Task 1: Define GameDBEntry, GameConfigVariant, and supporting types** - `0be5c008` (feat)
2. **Task 2: Define GameConfigSnapshot with plist serialization** - `49242a21` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBRating.swift` - CompatibilityRating enum with 5 tiers, Comparable, SF Symbols
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBEntry.swift` - GameDBEntry, GameConfigVariant, GameConfigVariantSettings, ExeFingerprint, GameConstraints, TestedWith, KnownIssue, Provenance
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/MatchResult.swift` - MatchResult struct and MatchTier enum for tiered confidence scoring
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/SteamAppManifest.swift` - ACF parser, bottle-wide manifest scan, per-exe steam_appid.txt lookup
- `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameConfigSnapshot.swift` - Plist-serializable settings snapshot with save/load/delete
- `WhiskyKit/Tests/WhiskyKitTests/GameDatabaseTests.swift` - 16 tests for all data models

## Decisions Made
- **EnhancedSync JSON encoding**: EnhancedSync uses Swift's auto-synthesized Codable (keyed enum `{"esync":{}}`), but the JSON database uses plain strings for readability. Added string-first decoding with fallback in GameConfigVariantSettings.
- **Settings field mapping**: GameConfigVariantSettings fields are named identically to BottleSettings properties (graphicsBackend, dxvk, enhancedSync, etc.) so the applicator can set values without a translation layer.
- **Single-file snapshot**: One GameConfigSnapshot.plist per bottle, overwritten on each apply, matching the research document's single-undo recommendation.
- **programSettingsData key type**: Used `[String: Data]` instead of `[URL: Data]` since URL has complex Codable behavior; the string representation is sufficient for key-based lookup.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed EnhancedSync JSON decoding mismatch**
- **Found during:** Task 1 (test verification)
- **Issue:** EnhancedSync enum has no String raw value, so it encodes as `{"esync":{}}` not `"esync"`. The JSON database schema uses plain strings for human readability.
- **Fix:** Added string-first decoding in GameConfigVariantSettings.init(from:) that maps "none"/"esync"/"msync" to the enum, with fallback to native Codable format.
- **Files modified:** WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBEntry.swift
- **Verification:** testGameDBEntryDecodesFromJSON passes with plain string "esync" in JSON
- **Committed in:** 0be5c008 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for JSON database interoperability. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All core data models ready for Plan 02 (GameDBLoader JSON loading)
- GameDBEntry schema matches the research document's JSON design
- GameConfigSnapshot ready for Plan 04 (GameConfigApplicator undo/revert)
- MatchResult/MatchTier ready for Plan 03 (GameMatcher scoring)
- SteamAppManifest ready for Plan 03 (hard identifier matching)

## Self-Check: PASSED

All 7 files verified on disk. Both commit hashes (0be5c008, 49242a21) found in git log.

---
*Phase: 07-game-compatibility-database*
*Completed: 2026-02-10*
