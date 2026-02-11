---
phase: 08-remaining-platform-issues
plan: 03
subsystem: dependencies
tags: [winetricks, dependency-management, process, asyncstream, plist]

# Dependency graph
requires:
  - phase: 02-configuration-foundation
    provides: "WinetricksVerbCache, Winetricks+InstalledVerbs loadInstalledVerbs infrastructure"
  - phase: 05-stability-diagnostics
    provides: "DiagnosisHistory, CrashCategory.dependenciesLoading for evidence-based recommendations"
  - phase: 07-game-compatibility-database
    provides: "GameMatcher, GameDBLoader, GameConfigVariant.winetricksVerbs for game DB recommendations"
provides:
  - "DependencyDefinition mapping display names to winetricks verbs (4 standard dependencies)"
  - "DependencyStatus with tiered confidence detection (authoritative/cached/heuristic/unknown)"
  - "DependencyManager orchestrator for status checking and evidence-based recommendations"
  - "Headless winetricks verb installation via Process with AsyncStream progress"
  - "BottleDependencyHistory for install attempt persistence"
affects: [08-06, 08-07]

# Tech tracking
tech-stack:
  added: []
  patterns: [caseless-enum-utility, asyncstream-process-execution, plist-sidecar-persistence, tiered-detection]

key-files:
  created:
    - "WhiskyKit/Sources/WhiskyKit/Whisky/BottleDependencyConfig.swift"
    - "Whisky/Utils/DependencyManager.swift"
    - "Whisky/Utils/Winetricks+Install.swift"
  modified:
    - "WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift"
    - "Whisky.xcodeproj/project.pbxproj"

key-decisions:
  - "DependencyDefinition and DependencyStatus at module scope in WhiskyKit (ClipboardPolicy pattern)"
  - "DependencyManager as caseless enum (GPUDetection/GameMatcher pattern) for static utility methods"
  - "Headless winetricks install via Process (not Terminal AppleScript) to attribute volume access to Whisky"
  - "Three evidence sources for recommendations: ClickOnce detection, crash diagnosis history, game database"
  - "dismissedDependencyRecommendations as Set<String> on ProgramSettings for per-program dismiss tracking"
  - "BottleDependencyHistory bounded to 20 entries with plist sidecar at bottleURL/dependency-history.plist"

patterns-established:
  - "Headless Process execution with AsyncStream progress: configureProcess + attachOutputHandlers + awaitCompletion"
  - "Evidence-based recommendations: never recommend speculatively, only from ClickOnce/crash/gameDB evidence"

# Metrics
duration: 9min
completed: 2026-02-11
---

# Phase 08 Plan 03: Dependency Tracking Data Layer Summary

**DependencyDefinition/Status models with tiered detection via WinetricksVerbCache, headless Process installer with AsyncStream progress, and evidence-based recommendations from crash diagnosis and game database**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-11T06:49:21Z
- **Completed:** 2026-02-11T06:58:35Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- 4 standard dependencies mapped (vcruntime, dotnet48, directx, directx_audio) with display names and winetricks verbs
- Tiered status detection using existing loadInstalledVerbs infrastructure with authoritative/cached confidence levels
- Headless winetricks verb installation via Process with async streaming progress (not Terminal AppleScript)
- Evidence-based recommendations from ClickOnce detection, crash diagnosis history, and game database entries
- Install attempt history persisted as plist sidecar for diagnostics export (bounded to 20 entries)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DependencyDefinition and DependencyStatus models** - `7a51f988` (feat)
2. **Task 2: Create DependencyManager and headless winetricks installer** - `ecef396e` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleDependencyConfig.swift` - DependencyCategory, DependencyDefinition, DependencyConfidence, DependencyInstallStatus, DependencyStatus, DependencyInstallAttempt, BottleDependencyHistory models
- `Whisky/Utils/DependencyManager.swift` - Caseless enum orchestrator for dependency status checking and evidence-based recommendations
- `Whisky/Utils/Winetricks+Install.swift` - Headless winetricks verb installation via Process with AsyncStream progress streaming
- `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift` - Added dismissedDependencyRecommendations property with defensive decoding
- `Whisky.xcodeproj/project.pbxproj` - Added DependencyManager.swift and Winetricks+Install.swift to Whisky target

## Decisions Made
- DependencyDefinition and related types placed at module scope in WhiskyKit for reuse across targets (follows ClipboardPolicy pattern)
- DependencyManager as caseless enum with static methods (follows GPUDetection/GameMatcher pattern)
- Headless winetricks installation via Foundation.Process to keep volume access attributed to Whisky rather than Terminal
- Three evidence sources for recommendations: ClickOnce programs always get dotnet48, dependenciesLoading crash history triggers vcruntime/directx, game DB winetricksVerbs cross-referenced with standard definitions
- Per-program dismiss tracking via Set<String> on ProgramSettings (not a separate sidecar) for simplicity
- BottleDependencyHistory uses 20-entry bound (larger than DiagnosisHistory's 5 since install attempts are less frequent)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added dismissedDependencyRecommendations to ProgramSettings**
- **Found during:** Task 2 (DependencyManager implementation)
- **Issue:** DependencyManager.dismissRecommendation needs a storage field on ProgramSettings for dismissed recommendation IDs
- **Fix:** Added `dismissedDependencyRecommendations: Set<String>?` property with defensive `decodeIfPresent` in custom init
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift
- **Verification:** WhiskyKit tests pass, build succeeds
- **Committed in:** ecef396e (Task 2 commit)

**2. [Rule 3 - Blocking] Added new files to Xcode project**
- **Found during:** Task 2 (build verification)
- **Issue:** Xcode project uses explicit PBXBuildFile/PBXFileReference entries; new Swift files not compiled without project registration
- **Fix:** Added PBXFileReference, PBXBuildFile, group membership, and Sources build phase entries for both new app-target files
- **Files modified:** Whisky.xcodeproj/project.pbxproj
- **Verification:** xcodebuild compiles both files successfully
- **Committed in:** ecef396e (Task 2 commit)

**3. [Rule 1 - Bug] Fixed ProgramMetadata constructor call**
- **Found during:** Task 2 (DependencyManager implementation)
- **Issue:** Plan referenced non-existent parameters (steamManifestPath, fingerprint) in ProgramMetadata init
- **Fix:** Used correct init signature: exeName, exeURL, installPath (matching GameMatcher.swift definition)
- **Files modified:** Whisky/Utils/DependencyManager.swift
- **Verification:** Build succeeds
- **Committed in:** ecef396e (Task 2 commit)

**4. [Rule 1 - Bug] Fixed MatchResult property name**
- **Found during:** Task 2 (DependencyManager implementation)
- **Issue:** Plan referenced `selectedVariant` but actual property is `recommendedVariant`
- **Fix:** Changed to `match.recommendedVariant` (matching MatchResult.swift definition)
- **Files modified:** Whisky/Utils/DependencyManager.swift
- **Verification:** Build succeeds
- **Committed in:** ecef396e (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (2 blocking, 2 bug)
**Impact on plan:** All auto-fixes necessary for compilation and correctness. No scope creep.

## Issues Encountered
- Build fails from pre-existing SwiftLint errors in LauncherPresets.swift and MacOSCompatibility.swift (not introduced by this plan). Swift compilation and linking succeed. The new files pass SwiftLint without errors.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Dependency models and data layer ready for UI integration in plan 08-06 (Dependency Config Section)
- DependencyManager.checkDependencies provides the status data source for the Config view
- Winetricks.installVerb provides the headless installation backend for the install button
- BottleDependencyHistory ready for inclusion in diagnostic exports

## Self-Check: PASSED

- [x] BottleDependencyConfig.swift exists
- [x] DependencyManager.swift exists
- [x] Winetricks+Install.swift exists
- [x] 08-03-SUMMARY.md exists
- [x] Commit 7a51f988 found in log
- [x] Commit ecef396e found in log

---
*Phase: 08-remaining-platform-issues*
*Completed: 2026-02-11*
