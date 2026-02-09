---
phase: 02-configuration-foundation
plan: 02
subsystem: wine-environment
tags: [environment-builder, layer-resolution, program-overrides, dll-composition, launch-logging]

# Dependency graph
requires:
  - phase: 02-01
    provides: "EnvironmentBuilder, DLLOverrideResolver, ProgramOverrides model types"
provides:
  - "constructWineEnvironment with 8-layer EnvironmentBuilder resolution"
  - "Layer populator methods on BottleSettings (bottleManaged, launcherManaged, inputCompatibility)"
  - "ProgramOverrides wired through programUser layer in all launch paths"
  - "DLLOverrideResolver-based WINEDLLOVERRIDES composition"
  - "Safe launch summary logging with provenance tracking"
affects: [02-04, phase-03, phase-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Layer populator pattern: BottleSettings populates EnvironmentBuilder layers via inout parameter"
    - "DLL override return pattern: populators return [(entry, source)] tuples for DLLOverrideResolver"
    - "Safe launch logging: non-sensitive key allowlist for operational visibility"
    - "Deprecated wrapper: environmentVariables(wineEnv:) delegates to new populators for backward compatibility"

key-files:
  created: []
  modified:
    - WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift
    - WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift
    - WhiskyKit/Tests/WhiskyKitTests/EnvironmentVariablesTests.swift
    - WhiskyKit/Tests/WhiskyKitTests/BottleLauncherConfigTests.swift
    - WhiskyKit/Tests/WhiskyKitTests/LauncherDiagnosticsTests.swift

key-decisions:
  - "Kept environmentVariables(wineEnv:) as deprecated wrapper for backward compatibility rather than removing it"
  - "DLLOverrideResolver produces per-DLL alphabetically sorted format instead of comma-grouped -- both valid Wine syntax"
  - "Extracted isValidEnvKey to extension to satisfy SwiftLint type_body_length on Wine class"
  - "ProgramOverrides passed through Wine.runProgram rather than changing Program.generateEnvironment return type"

patterns-established:
  - "Layer populator: BottleSettings methods take inout EnvironmentBuilder, return DLL override entries"
  - "Safe logging: allowlisted keys only, no WINEPREFIX paths or user-set custom env vars"
  - "Program override wiring: settings.overrides flows through launchWithUserMode -> runProgram -> constructWineEnvironment"

# Metrics
duration: 45min
completed: 2026-02-09
---

# Phase 2 Plan 2: Environment Builder Integration Summary

**Refactored all Wine environment construction into EnvironmentBuilder with 8-layer resolution, DLLOverrideResolver-based WINEDLLOVERRIDES composition, ProgramOverrides flowing through programUser layer, and safe launch logging**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-02-09T03:00:00Z
- **Completed:** 2026-02-09T03:50:24Z
- **Tasks:** 2
- **Files modified:** 37 (7 substantive + 30 formatting)

## Accomplishments

- Replaced ad-hoc mutable-dict environment construction with deterministic 8-layer EnvironmentBuilder resolution
- Removed dead code (constructWineServerEnvironment) and deprecated the old environmentVariables(wineEnv:) API
- Wired ProgramOverrides through all launch paths (launchWithUserMode, runInWine) to the programUser layer
- Added safe launch summary logging with non-sensitive key allowlist and provenance tracking
- WINEDLLOVERRIDES now composed per-DLL via DLLOverrideResolver with alphabetical sorting
- Added 7 new tests for layer populators, program overrides, and DLL composition

## Task Commits

Each task was committed atomically:

1. **Task 1: Refactor constructWineEnvironment and BottleSettings into EnvironmentBuilder layers** - `d7cc482a` (refactor)
2. **Task 2: Wire EnvironmentBuilder through all launch paths and add launch logging** - `0b1975c8` (feat)
3. **Formatting cleanup** - `b83dfb4c` (chore)

## Files Created/Modified

- `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` - Central constructWineEnvironment using EnvironmentBuilder with 8 layers, applyProgramOverrides, logLaunchSummary
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - Layer populator methods (populateBottleManagedLayer, populateLauncherManagedLayer, populateInputCompatibilityLayer) replacing environmentVariables(wineEnv:)
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` - runProgram accepts programOverrides, isValidEnvKey extracted to extension
- `WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift` - launchWithUserMode and runInWine pass settings.overrides
- `WhiskyKit/Tests/WhiskyKitTests/EnvironmentVariablesTests.swift` - Updated DXVK assertion format + 7 new tests
- `WhiskyKit/Tests/WhiskyKitTests/BottleLauncherConfigTests.swift` - Updated DLL override format assertion
- `WhiskyKit/Tests/WhiskyKitTests/LauncherDiagnosticsTests.swift` - Updated DLL override format assertion

## Decisions Made

- **Deprecated wrapper over removal:** Kept `environmentVariables(wineEnv:)` as a deprecated wrapper that delegates to the new populator methods. This preserves backward compatibility for any code not yet migrated while providing a clear migration path.
- **Per-DLL format for WINEDLLOVERRIDES:** DLLOverrideResolver produces `d3d10core=n,b;d3d11=n,b;d3d9=n,b;dxgi=n,b` (per-DLL, semicolon-separated, alphabetically sorted) instead of the old `dxgi,d3d9,d3d10core,d3d11=n,b` (comma-grouped). Both are valid Wine syntax; the per-DLL format enables per-DLL override composition.
- **ProgramOverrides as additive parameter:** Added `programOverrides: ProgramOverrides? = nil` to `Wine.runProgram` rather than changing `Program.generateEnvironment()` return type. Cleaner separation of concerns.
- **Extension extraction for SwiftLint:** Moved `isValidEnvKey`, `isAsciiLetter`, `isAsciiDigit` from Wine class body to extension to stay under the 250-line type_body_length limit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated DLL override format assertions in 3 test files**
- **Found during:** Task 1 and Task 2
- **Issue:** DLLOverrideResolver produces per-DLL alphabetically sorted format (`d3d10core=n,b;d3d11=n,b;d3d9=n,b;dxgi=n,b`) instead of old comma-grouped format (`dxgi,d3d9,d3d10core,d3d11=n,b`). Three test files expected the old format.
- **Fix:** Updated assertions in EnvironmentVariablesTests.swift, BottleLauncherConfigTests.swift, and LauncherDiagnosticsTests.swift to expect the new canonical format
- **Files modified:** EnvironmentVariablesTests.swift, BottleLauncherConfigTests.swift, LauncherDiagnosticsTests.swift
- **Verification:** All 774 tests pass with 0 failures
- **Committed in:** d7cc482a (Task 1) and 0b1975c8 (Task 2)

**2. [Rule 1 - Bug] Fixed SwiftLint inclusive_language violation**
- **Found during:** Task 2
- **Issue:** Variable named `whitelist` in logLaunchSummary triggered SwiftLint inclusive_language rule
- **Fix:** Renamed to `allowedKeys`
- **Files modified:** WineEnvironment.swift
- **Verification:** SwiftLint passes, swiftformat --lint clean
- **Committed in:** 0b1975c8 (Task 2)

**3. [Rule 3 - Blocking] Extracted methods to fix SwiftLint type_body_length**
- **Found during:** Task 2
- **Issue:** Wine class body exceeded 250-line SwiftLint limit after adding file handle creation and constructWineEnvironment call to runProgram
- **Fix:** Extracted `isValidEnvKey`, `isAsciiLetter`, `isAsciiDigit` (3 static methods, ~28 lines) from class body to a separate `extension Wine` block
- **Files modified:** Wine.swift
- **Verification:** SwiftLint passes, all tests pass
- **Committed in:** 0b1975c8 (Task 2)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 3 blocking)
**Impact on plan:** All auto-fixes necessary for correctness and build compliance. No scope creep.

## Issues Encountered

- **Behavioral preservation complexity:** The deprecated `environmentVariables(wineEnv:)` wrapper required careful handling of key removals for `enhancedSync == .none` on macOS < 15.4, since the builder's resolve() omits removed keys but the caller's dict may have pre-existing values. Solved with explicit `removeValue(forKey:)` calls.
- **Launcher locale precedence:** Original code checked `wineEnv["LC_ALL"] == nil` before applying launcher locale. In the layer model, both writes go to the same layer. Solved by tracking `launcherProvidesLocale` flag from the launcher's `environmentOverrides()` dict.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- EnvironmentBuilder integration complete; all launch paths resolve through the builder
- Ready for Plan 02-04 (settings refactoring) which builds on the layer populator pattern
- Phase 3 (diagnostics) can leverage provenance data from EnvironmentBuilder.resolve()

## Self-Check: PASSED

All 7 key files verified present. All 3 commits (d7cc482a, 0b1975c8, b83dfb4c) verified in git log.

---
*Phase: 02-configuration-foundation*
*Completed: 2026-02-09*
