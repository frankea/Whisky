---
phase: 01-miscellaneous-fixes
plan: 01
subsystem: whiskykit
tags: [clipboard, clickonce, wine, configuration, codable]

# Dependency graph
requires: []
provides:
  - "Dynamic wineUsername path construction in ClickOnceManager"
  - "ClipboardCheckResult structured return type for pre-launch clipboard checks"
  - "ClipboardPolicy enum for per-bottle clipboard behavior"
  - "BottleCleanupConfig with clipboardPolicy, clipboardThreshold, killOnQuit"
  - "KillOnQuitPolicy enum for per-bottle process lifecycle overrides"
  - "displayName(for:) and deploymentURL(for:) helpers on ClickOnceManager"
affects: [01-02, 01-03]

# Tech tracking
tech-stack:
  added: []
  patterns: ["structured result return instead of direct UI presentation", "per-bottle config section with proxy properties"]

key-files:
  created:
    - "WhiskyKit/Sources/WhiskyKit/Whisky/BottleCleanupConfig.swift"
  modified:
    - "WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift"
    - "WhiskyKit/Sources/WhiskyKit/ClipboardManager.swift"
    - "WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift"

key-decisions:
  - "ClipboardPolicy and ClipboardCheckResult defined at module scope (not nested in ClipboardManager) for easier import"
  - "KillOnQuitPolicy uses inherit/alwaysKill/neverKill to clearly override global killOnTerminate"
  - "BottleCleanupConfig follows existing config section pattern (private stored, public proxy properties)"

patterns-established:
  - "Structured result pattern: WhiskyKit methods return result enums, app layer presents UI"
  - "Per-bottle config section: private stored config + public proxy computed properties on BottleSettings"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 1 Plan 1: WhiskyKit Backend Preparation Summary

**Parameterized ClickOnce username, structured clipboard check results, and per-bottle cleanup/clipboard configuration**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T04:29:37Z
- **Completed:** 2026-02-09T04:33:46Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- ClickOnceManager no longer hardcodes "crossover" -- wineUsername is a parameter with backward-compatible default
- ClipboardManager returns ClipboardCheckResult instead of directly showing NSAlert, decoupling WhiskyKit from UI
- New BottleCleanupConfig provides per-bottle clipboard policy, size threshold, and kill-on-quit settings
- Added displayName(for:) and deploymentURL(for:) helper methods on ClickOnceManager

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix ClickOnceManager hardcoded username and add display name helper** - `e66b78df` (feat)
2. **Task 2: Refactor ClipboardManager to return ClipboardCheckResult and add BottleCleanupConfig** - `87149cd3` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift` - Parameterized wineUsername, added displayName/deploymentURL helpers
- `WhiskyKit/Sources/WhiskyKit/ClipboardManager.swift` - Replaced sanitizeForMultiplayer with checkBeforeLaunch, added ClipboardPolicy/ClipboardCheckResult enums
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleCleanupConfig.swift` - New per-bottle cleanup config with ClipboardPolicy, KillOnQuitPolicy
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - Added cleanupConfig section with proxy properties

## Decisions Made
- ClipboardPolicy and ClipboardCheckResult defined at module scope for easier access from app layer
- KillOnQuitPolicy uses inherit/alwaysKill/neverKill naming to clearly convey override semantics
- BottleCleanupConfig follows existing config section pattern for consistency

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ClickOnce display helpers ready for Plan 02 (UI integration)
- ClipboardCheckResult ready for Plan 03 (clipboard pre-launch UI)
- BottleCleanupConfig ready for Plan 03 (cleanup settings UI)
- All 743 XCTest + 23 Swift Testing tests pass
- App builds successfully

## Self-Check: PASSED

- All 4 source files exist on disk
- Both task commits verified: `e66b78df`, `87149cd3`
- SUMMARY.md exists at expected path

---
*Phase: 01-miscellaneous-fixes*
*Completed: 2026-02-09*
