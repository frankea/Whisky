---
phase: 10-guided-troubleshooting
plan: 04
subsystem: troubleshooting
tags: [swift-concurrency, sendable, protocol-conformance, diagnostic-wrappers, check-registry]

# Dependency graph
requires:
  - phase: 10-guided-troubleshooting
    provides: TroubleshootingCheck protocol, CheckResult, CheckContext, PreflightData, CheckRegistry skeleton
  - phase: 05-stability-diagnostics
    provides: CrashClassifier, ConfidenceTier, WineDebugPreset
  - phase: 06-audio-troubleshooting
    provides: AudioProbe protocol, WineRegistryAudioProbe, AudioDeviceMonitor
  - phase: 04-graphics-configuration
    provides: GraphicsBackendResolver, GraphicsBackend, BottleGraphicsConfig
  - phase: 07-game-compatibility-database
    provides: GameMatcher, GameDBLoader, MatchResult, ProgramMetadata
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder, WinetricksVerbCache, BottleSettings layer populators
provides:
  - 15 TroubleshootingCheck implementations wrapping existing diagnostic primitives
  - CheckRegistry.registerDefaults() with all 15 checks pre-registered
  - Stable dot-namespaced check IDs matching JSON flow references
affects: [10-05, 10-06, 10-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Thin check wrapper: 5-30 line run() methods delegating to existing primitives"
    - "Direct .reg file parsing in RegistryValueCheck for non-MainActor registry access"
    - "BottleSettings.decode(from:) for disk-based settings reads without Bottle reference"
    - "NSLock.withLock for async-safe lock access in CheckRegistry"

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/CrashLogCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/GraphicsBackendCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DXVKSettingsCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/AudioDriverCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/AudioDeviceCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/AudioTestCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DependencyCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/WinetricksVerbCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/LauncherTypeCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/ProcessRunningCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/EnvironmentCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/RegistryValueCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/GameConfigAvailableCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/SettingValueCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DiagnosticsEnhanceCheck.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckRegistry.swift

key-decisions:
  - "RegistryValueCheck parses .reg files directly instead of spawning Wine process (avoids @MainActor Bottle dependency)"
  - "SettingValueCheck uses switch-based property name dispatch for type-safe settings access"
  - "AudioTestCheck returns .unknown gracefully since MinGW test exe is not compiled"
  - "CheckRegistry.init() calls registerDefaults() automatically (no manual registration needed)"
  - "NSLock.withLock replaces manual lock/unlock for Swift 6 async-context compatibility"

patterns-established:
  - "Check wrapper pattern: public struct + TroubleshootingCheck conformance + thin run() delegating to existing primitive"
  - "Settings-from-disk: BottleSettings.decode(from: metadataURL) for check implementations that need settings without @MainActor"
  - "Direct .reg file parsing: RegistryValueCheck reads user.reg/system.reg without Wine process overhead"

# Metrics
duration: 24min
completed: 2026-02-12
---

# Phase 10 Plan 04: Check Implementations Summary

**15 TroubleshootingCheck wrappers for CrashClassifier, GraphicsBackendResolver, AudioProbes, GameMatcher, EnvironmentBuilder, WinetricksVerbCache, and Wine registry primitives, all registered in CheckRegistry.registerDefaults()**

## Performance

- **Duration:** 24 min
- **Started:** 2026-02-12T03:28:44Z
- **Completed:** 2026-02-12T03:52:47Z
- **Tasks:** 2
- **Files modified:** 16

## Accomplishments
- Implemented all 15 concrete TroubleshootingCheck wrappers covering crash diagnostics, graphics backend verification, DXVK settings, audio driver/device/test, dependency DLL scanning, winetricks verb detection, launcher type, process running state, environment variable resolution, Wine registry value reading, game config matching, generic setting value checking, and WINEDEBUG diagnostics enhancement
- Updated CheckRegistry with registerDefaults() that registers all 15 checks automatically on init
- Fixed CheckRegistry NSLock async-context error (Swift 6 compliance) by replacing manual lock/unlock with withLock

## Task Commits

Each task was committed atomically:

1. **Task 1: Graphics, crash, DXVK, audio, and dependency checks (8 implementations)** - `69eb3ba7` (feat)
2. **Task 2: Launcher, process, environment, registry, game config, setting, diagnostics checks + registry wiring** - `57548702` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/CrashLogCheck.swift` - Wraps CrashClassifier for log pattern matching (checkId: crash.log_classify)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/GraphicsBackendCheck.swift` - Verifies resolved backend against expected (checkId: graphics.backend_is)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DXVKSettingsCheck.swift` - Checks DXVK async/hud/backend settings (checkId: dxvk.settings_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/AudioDriverCheck.swift` - Compares Wine audio driver setting (checkId: audio.driver_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/AudioDeviceCheck.swift` - Verifies default output device availability (checkId: audio.device_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/AudioTestCheck.swift` - Graceful unknown for unavailable test exe (checkId: audio.test_play)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DependencyCheck.swift` - Scans system32/syswow64 for DLLs (checkId: dependency.check_missing)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/WinetricksVerbCheck.swift` - Compares installed verbs via WinetricksVerbCache (checkId: winetricks.verb_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/LauncherTypeCheck.swift` - Detects launcher from preflight data (checkId: launcher.type_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/ProcessRunningCheck.swift` - Queries ProcessRegistry for Wine processes (checkId: process.running_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/EnvironmentCheck.swift` - Resolves env vars via EnvironmentBuilder (checkId: env.check_var)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/RegistryValueCheck.swift` - Parses .reg files from bottle prefix (checkId: registry.value_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/GameConfigAvailableCheck.swift` - Delegates to GameMatcher for known configs (checkId: game.config_available)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/SettingValueCheck.swift` - Reads any BottleSettings property by name (checkId: setting.value_check)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DiagnosticsEnhanceCheck.swift` - Evaluates WINEDEBUG preset status (checkId: diagnostics.can_enhance)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckRegistry.swift` - Updated with registerDefaults() registering all 15 checks

## Decisions Made
- RegistryValueCheck parses Wine .reg files directly from the bottle prefix instead of spawning a Wine registry query process -- this avoids needing a @MainActor Bottle reference and is faster for simple string value reads
- SettingValueCheck uses a switch-based property name dispatch rather than reflection, providing type-safe access to all common BottleSettings properties
- AudioTestCheck returns .unknown instead of .error since the MinGW test executable not being compiled is expected (not an error condition)
- CheckRegistry.init() calls registerDefaults() automatically so consumers do not need to remember to register checks separately
- NSLock.withLock replaces manual lock()/unlock() pairs in CheckRegistry.run() to fix Swift 6 async-context compatibility errors

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed CheckRegistry NSLock async-context error**
- **Found during:** Task 1 (compilation)
- **Issue:** CheckRegistry.run() used lock.lock()/lock.unlock() in an async method, which Swift 6 strict concurrency rejects
- **Fix:** Replaced with lock.withLock { } closure pattern
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckRegistry.swift
- **Verification:** swift build succeeds without errors
- **Committed in:** 69eb3ba7 (Task 1 commit)

**2. [Rule 1 - Bug] Fixed DXVKHUD.rawValue error in DXVKSettingsCheck**
- **Found during:** Task 1 (compilation)
- **Issue:** DXVKHUD enum does not have String rawValue; used .rawValue which does not compile
- **Fix:** Changed to String(describing:) for the HUD value
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/DXVKSettingsCheck.swift
- **Verification:** swift build succeeds
- **Committed in:** 69eb3ba7 (Task 1 commit)

**3. [Rule 1 - Bug] Fixed EnhancedSync.rawValue error in SettingValueCheck**
- **Found during:** Task 2 (compilation)
- **Issue:** EnhancedSync enum does not have String rawValue
- **Fix:** Changed to String(describing:)
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/SettingValueCheck.swift
- **Verification:** swift build succeeds
- **Committed in:** 57548702 (Task 2 commit)

**4. [Rule 1 - Bug] Fixed non-optional rating binding in GameConfigAvailableCheck**
- **Found during:** Task 2 (compilation)
- **Issue:** GameDBEntry.rating is non-optional; `if let` binding fails to compile
- **Fix:** Direct assignment without optional binding
- **Files modified:** WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/GameConfigAvailableCheck.swift
- **Verification:** swift build succeeds
- **Committed in:** 57548702 (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (4 Rule 1 bugs)
**Impact on plan:** All auto-fixes necessary for compilation correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 15 check implementations ready for the TroubleshootingFlowEngine (Plan 05) to invoke via CheckRegistry
- Check IDs are stable and match the JSON flow file references from Plan 02
- No new diagnostic logic built; all checks delegate to existing primitives as intended

## Self-Check: PASSED

All 15 Swift check files verified present. Both commits (69eb3ba7, 57548702) verified in git log. CheckRegistry.registerDefaults() contains 15 register() calls. All 15 checkIds are unique and dot-namespaced. swift build --package-path WhiskyKit succeeds. swift test --package-path WhiskyKit passes all 23 tests.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
