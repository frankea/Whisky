---
phase: 01-miscellaneous-fixes
plan: 02
subsystem: ui
tags: [clickonce, swiftui, program-model, context-menu, localization]

# Dependency graph
requires:
  - phase: 01-01
    provides: "ClickOnceManager with displayName(for:) and deploymentURL(for:) helpers"
provides:
  - "ClickOnce apps as first-class entries in Programs list with badge and context menu"
  - "Program.isClickOnce flag and init(appRefURL:bottle:displayName:) initializer"
  - "ClickOnce cache executable filtering in updateInstalledPrograms"
  - "Manual rescan toolbar button for ClickOnce app discovery"
affects: [01-03]

# Tech tracking
tech-stack:
  added: []
  patterns: ["ClickOnce badge rendered as else-if after PE architecture badge", "ClickOnce context menu section appended after standard program menu"]

key-files:
  created: []
  modified:
    - "WhiskyKit/Sources/WhiskyKit/Whisky/Program.swift"
    - "Whisky/Extensions/Bottle+Extensions.swift"
    - "Whisky/Views/Programs/ProgramsView.swift"
    - "Whisky/Views/Programs/ProgramMenuView.swift"
    - "Whisky/Localizable.xcstrings"

key-decisions:
  - "ClickOnce badge uses else-if after PE architecture badge (mutually exclusive since ClickOnce apps have no PE file)"
  - "Rescan button placed in ProgramsView toolbar rather than context menu for discoverability"
  - "ClickOnce context menu actions in separate Section to visually distinguish from standard actions"

patterns-established:
  - "Program type differentiation via isClickOnce flag with specialized initializer"
  - "ClickOnce-specific menu section appended conditionally in ProgramMenuView"

# Metrics
duration: 5min
completed: 2026-02-09
---

# Phase 1 Plan 2: ClickOnce UI Integration Summary

**ClickOnce .appref-ms apps surfaced in Programs list with ClickOnce badge, context menu actions (Copy URL, Remove), and manual rescan toolbar button**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-09T04:37:11Z
- **Completed:** 2026-02-09T04:43:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Program model extended with isClickOnce flag and ClickOnce-specific initializer
- ClickOnce .appref-ms files auto-detected and displayed with friendly names in Programs list
- ClickOnce cache executables (Apps/2.0/) filtered from regular program scan
- Context menu provides Copy Deployment URL and Remove ClickOnce App actions
- Rescan ClickOnce Apps toolbar button for manual discovery refresh
- 6 localization strings added (EN only, translations handled on Crowdin)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend Program model for ClickOnce and integrate detection into Bottle** - `1a8cf91b` (feat)
2. **Task 2: Surface ClickOnce apps in ProgramsView with badge and context menu actions** - `ad2c7bcb` (feat)

Note: ProgramsView.swift and Localizable.xcstrings changes from Task 2 were captured in commit `b428aa42` by a concurrent Plan 01-03 execution. The remaining ProgramMenuView.swift changes were committed in `ad2c7bcb`.

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Whisky/Program.swift` - Added isClickOnce flag, _displayName, and ClickOnce initializer
- `Whisky/Extensions/Bottle+Extensions.swift` - ClickOnce detection in updateInstalledPrograms, Apps/2.0 cache filtering
- `Whisky/Views/Programs/ProgramsView.swift` - ClickOnce badge in ProgramItemView, rescan toolbar button
- `Whisky/Views/Programs/ProgramMenuView.swift` - Copy Deployment URL and Remove ClickOnce App menu actions
- `Whisky/Localizable.xcstrings` - 6 new program.clickonce.* localization keys

## Decisions Made
- ClickOnce badge uses `else if` after PE architecture badge since they are mutually exclusive
- Rescan button placed in toolbar (not context menu) for better discoverability
- ClickOnce menu actions in a separate Section to visually distinguish from standard program actions

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- A concurrent Plan 01-03 execution committed ProgramsView.swift and Localizable.xcstrings changes (which included Task 2 ClickOnce changes) in commit b428aa42. ProgramMenuView.swift was committed separately in ad2c7bcb. All changes are present and verified.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ClickOnce apps fully integrated into UI, ready for user testing
- All 23 WhiskyKit tests pass
- App builds successfully
- Plan 03 can proceed with remaining clipboard/cleanup UI work

## Self-Check: PASSED

- All 5 source files exist on disk
- Both task commits verified: `1a8cf91b`, `ad2c7bcb`
- SUMMARY.md exists at expected path

---
*Phase: 01-miscellaneous-fixes*
*Completed: 2026-02-09*
