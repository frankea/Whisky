---
phase: 08-remaining-platform-issues
plan: 06
subsystem: dependencies-ui
tags: [swiftui, dependency-tracking, guided-install, winetricks, prefix-validation]

# Dependency graph
requires:
  - phase: 08-remaining-platform-issues
    plan: 03
    provides: "DependencyDefinition, DependencyStatus, DependencyManager, Winetricks+Install headless installer"
  - phase: 05-stability-diagnostics
    provides: "WinePrefixValidation for preflight checks"
provides:
  - "DependencyConfigSection showing 4 standard dependencies with status badges in bottle Config"
  - "DependencyInstallSheet guided flow with Info/Preflight/Plan/Running/Verify stages"
  - "ConfigView integration placing Dependencies section after DLL Overrides"
affects: [08-07]

# Tech tracking
tech-stack:
  added: []
  patterns: [staged-sheet-flow, section-per-subsystem, collapsible-live-log]

key-files:
  created:
    - "Whisky/Views/Bottle/DependencyConfigSection.swift"
    - "Whisky/Views/Install/DependencyInstallSheet.swift"
  modified:
    - "Whisky/Views/Bottle/ConfigView.swift"
    - "Whisky.xcodeproj/project.pbxproj"

key-decisions:
  - "DependencyConfigSection manages its own @State (no @State needed in ConfigView)"
  - "Preflight and Plan stages merged into single preflight stage with embedded verb plan section"
  - "File split into extensions per MARK section for SwiftLint type_body_length compliance"
  - "dependencyRow helper split into dependencyRow + dependencyRowDetails for SwiftLint function_body_length"
  - "Install directory created under Views for DependencyInstallSheet (new group in Xcode project)"
  - "BottleDependencyHistory populated after each install attempt for diagnostics traceability"

patterns-established:
  - "Staged sheet flow: enum-driven stage with stage-specific ViewBuilder content and bottom bar actions"
  - "Collapsible live log: DisclosureGroup with ScrollViewReader auto-scroll for process output streaming"

# Metrics
duration: 8min
completed: 2026-02-11
---

# Phase 08 Plan 06: Dependency Tracking UI Summary

**DependencyConfigSection with status rows and guided DependencyInstallSheet walking through Info/Preflight/Plan/Running/Verify stages using headless winetricks installation**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-11T07:05:04Z
- **Completed:** 2026-02-11T07:13:28Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- DependencyConfigSection shows 4 standard dependencies with colored status badges, confidence indicators, last-checked timestamps, and Install actions
- DependencyInstallSheet provides 5-stage guided flow: What (info), Preflight (prefix validation + verb plan), Running (live log), Verify (re-check status)
- Installation never happens silently: user must click Continue then Install explicitly
- Live installation log with collapsible DisclosureGroup and auto-scroll to bottom
- Post-install verification re-runs DependencyManager.checkDependencies for the installed definition
- Install attempts saved to BottleDependencyHistory for diagnostics export

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DependencyConfigSection with status rows** - `74c19c8a` (feat)
2. **Task 2: Create DependencyInstallSheet guided flow** - `3d0b749e` (feat)

## Files Created/Modified
- `Whisky/Views/Bottle/DependencyConfigSection.swift` - Dependencies section view with status rows, badges, refresh, and install sheet trigger
- `Whisky/Views/Install/DependencyInstallSheet.swift` - 5-stage guided install sheet with preflight, live log, and verification
- `Whisky/Views/Bottle/ConfigView.swift` - Added DependencyConfigSection between DLL Overrides and Game Config Revert
- `Whisky.xcodeproj/project.pbxproj` - Added both new files, Install group under Views

## Decisions Made
- DependencyConfigSection manages its own @State for statuses, loading, and selectedDependency (no state hoisting to ConfigView needed)
- Plan stage merged into Preflight stage as a verbPlanSection GroupBox (5 conceptual stages in 4 enum cases)
- dependencyRow split into two @ViewBuilder functions to satisfy SwiftLint function_body_length (50 line limit)
- DependencyInstallSheet split into 7 extensions by MARK section for SwiftLint compliance and code organization
- Install directory created under Whisky/Views/ as a new Xcode group for dependency installation UI

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed WinePrefixDiagnostics property name**
- **Found during:** Task 2 (DependencyInstallSheet implementation)
- **Issue:** Plan referenced `diagnostics?.log.last` but WinePrefixDiagnostics stores events in `events` property, not `log`
- **Fix:** Changed to `result.diagnostics?.events.last`
- **Files modified:** Whisky/Views/Install/DependencyInstallSheet.swift
- **Verification:** Build succeeds
- **Committed in:** 3d0b749e (Task 2 commit)

**2. [Rule 1 - Bug] Split dependencyRow for SwiftLint function_body_length**
- **Found during:** Task 1 (build verification)
- **Issue:** dependencyRow function body spanned 52 lines, exceeding the 50-line SwiftLint limit
- **Fix:** Extracted dependencyRowDetails helper function for the lower portion (last-checked + details disclosure)
- **Files modified:** Whisky/Views/Bottle/DependencyConfigSection.swift
- **Verification:** SwiftLint passes with 0 violations
- **Committed in:** 74c19c8a (Task 1 commit)

**3. [Rule 3 - Blocking] Added new files to Xcode project**
- **Found during:** Task 1 (build compilation)
- **Issue:** Xcode project uses explicit PBXBuildFile/PBXFileReference entries; new Swift files not compiled without registration
- **Fix:** Added PBXFileReference, PBXBuildFile, Install group, group membership, and Sources build phase entries for both files
- **Files modified:** Whisky.xcodeproj/project.pbxproj
- **Verification:** xcodebuild compiles both files successfully
- **Committed in:** 74c19c8a (Task 1 commit)

**4. [Rule 3 - Blocking] Removed duplicate DependencyInstallSheet.swift from Bottle directory**
- **Found during:** Task 1 (build verification)
- **Issue:** Pre-existing duplicate file at Whisky/Views/Bottle/DependencyInstallSheet.swift caused SwiftLint to lint both copies
- **Fix:** Removed the duplicate, keeping only the canonical copy in Whisky/Views/Install/
- **Files modified:** (file deletion)
- **Verification:** Only one copy found, build succeeds
- **Committed in:** 74c19c8a (Task 1 commit)

---

**Total deviations:** 4 auto-fixed (2 bug, 2 blocking)
**Impact on plan:** All auto-fixes necessary for compilation and SwiftLint compliance. No scope creep.

## Issues Encountered
- Task 1 commit merged with a concurrent 08-05 commit (74c19c8a contains both InputConfigSection changes and DependencyConfigSection changes). The Task 1 files are correctly committed but the commit message references 08-05. This is a cosmetic issue only; all Task 1 files are tracked in git.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Dependency tracking UI complete: Config section shows status, Install button triggers guided flow
- Ready for plan 08-07 integration testing and remaining platform issues
- DependencyInstallSheet reusable for any DependencyDefinition (not hardcoded to specific dependencies)

## Self-Check: PASSED

- [x] DependencyConfigSection.swift exists
- [x] DependencyInstallSheet.swift exists
- [x] Commit 74c19c8a found in log
- [x] Commit 3d0b749e found in log
- [x] 08-06-SUMMARY.md exists

---
*Phase: 08-remaining-platform-issues*
*Completed: 2026-02-11*
