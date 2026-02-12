---
phase: 10-guided-troubleshooting
plan: 07
subsystem: integration
tags: [entry-points, localization, history-view, help-menu, crash-banner, rate-limiting, xcode-project]

# Dependency graph
requires:
  - phase: 10-guided-troubleshooting
    provides: TroubleshootingWizardView, TroubleshootingFlowEngine, SymptomCategory, TroubleshootingSession, TroubleshootingSessionStore, TroubleshootingHistory, EntryContext
  - phase: 05-stability-diagnostics
    provides: DiagnosticsPickerSheet pattern, CrashDiagnosisBannerState, crash diagnosis notification
provides:
  - TroubleshootingHistoryView per-bottle/program session history list
  - TroubleshootingTargetPicker bottle/program picker for Help menu entry
  - TroubleshootingEntryBanner resume/proactive suggestion banner
  - ProgramView Troubleshoot button as primary entry point
  - ConfigView Start Guided Troubleshooting in Diagnostics section
  - WhiskyApp Help menu Troubleshoot command with target picker
  - Crash banner Troubleshoot action for high-confidence diagnoses
  - Proactive suggestion rate limiting (30min/2hr cooldown)
  - 60 English localization entries for troubleshooting wizard UI
  - CHANGELOG.md entry for guided troubleshooting feature
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Entry point wiring: .sheet presentation from ProgramView, ConfigView, WhiskyApp to TroubleshootingWizardView"
    - "Target picker: DiagnosticsPickerSheet pattern reused for TroubleshootingTargetPicker"
    - "Rate limiting: in-memory dictionary with 30min cooldown, 2hr suppression after dismiss/completion"
    - "Crash banner enhancement: additional button alongside existing View Diagnosis"

key-files:
  created:
    - Whisky/Views/Troubleshooting/TroubleshootingHistoryView.swift
    - Whisky/Views/Troubleshooting/TroubleshootingTargetPicker.swift
    - Whisky/Views/Troubleshooting/TroubleshootingEntryBanner.swift
  modified:
    - Whisky/Views/Programs/ProgramView.swift
    - Whisky/Views/Bottle/ConfigView.swift
    - Whisky/Views/WhiskyApp.swift
    - Whisky.xcodeproj/project.pbxproj
    - Whisky/Localizable.xcstrings
    - CHANGELOG.md

key-decisions:
  - "CrashDiagnosis uses primaryCategory (not category) for evidence extraction in crash banner"
  - "Rate limiting uses in-memory dictionary (not UserDefaults) since suggestions are session-scoped"
  - "TroubleshootingTargetPicker follows DiagnosticsPickerSheet pattern exactly for consistency"
  - "History view uses clipboard export (matching AudioTroubleshootingWizardView and EscalationView pattern)"

patterns-established:
  - "Entry point -> Target picker -> Wizard sheet flow for Help menu"
  - "Banner -> Sheet presentation for resume and proactive suggestions"
  - "Inline history via TroubleshootingHistoryView embedded in ConfigView Diagnostics"

# Metrics
duration: 41min
completed: 2026-02-12
---

# Phase 10 Plan 07: Entry Points, Integration, Localization Summary

**All 4 locked entry points wired (Program view, crash banner, Config diagnostics, Help menu), troubleshooting history view, proactive suggestion rate limiting, and 60 English localization entries for the complete troubleshooting wizard UI**

## Performance

- **Duration:** 41 min
- **Started:** 2026-02-12T04:43:06Z
- **Completed:** 2026-02-12T05:24:30Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Wired all 4 locked entry points: ProgramView "Troubleshoot..." button, ConfigView "Start Guided Troubleshooting", Help menu "Troubleshoot..." with target picker, and crash banner "Troubleshoot" action
- Created TroubleshootingHistoryView showing per-bottle/program completed sessions with outcome badges, expandable fix details, and clipboard export
- Created TroubleshootingTargetPicker (DiagnosticsPickerSheet pattern) for Help menu entry point
- Created TroubleshootingEntryBanner for resume prompts and proactive suggestions with dual banner types
- Added proactive suggestion rate limiting: 30-minute cooldown per program, 2-hour suppression after dismiss/completion
- Added 60 English localization entries covering all troubleshooting wizard strings
- Updated CHANGELOG.md with user-facing guided troubleshooting entry

## Task Commits

Each task was committed atomically:

1. **Task 1: Entry points, history view, target picker, banner** - `0d37fbb5` (feat)
2. **Task 2: Localization and CHANGELOG** - `604ece20` (feat)

## Files Created/Modified
- `Whisky/Views/Troubleshooting/TroubleshootingHistoryView.swift` - Per-bottle/program history list with outcome badges, expandable rows, reopen-as-template, and clipboard export
- `Whisky/Views/Troubleshooting/TroubleshootingTargetPicker.swift` - Bottle/program picker sheet for Help menu entry, following DiagnosticsPickerSheet pattern
- `Whisky/Views/Troubleshooting/TroubleshootingEntryBanner.swift` - Compact tappable banner with BannerType enum (resumeSession/proactiveSuggestion)
- `Whisky/Views/Programs/ProgramView.swift` - Added Troubleshoot button in bottom bar, resume banner on active session, sheet presentation
- `Whisky/Views/Bottle/ConfigView.swift` - Added Start Guided Troubleshooting button, resume banner, inline TroubleshootingHistoryView in Diagnostics section
- `Whisky/Views/WhiskyApp.swift` - Added Help menu Troubleshoot command, target picker sheet, wizard sheet, crash banner Troubleshoot action, rate limiting
- `Whisky.xcodeproj/project.pbxproj` - Added 3 new files to Troubleshooting group
- `Whisky/Localizable.xcstrings` - 60 English localization entries with troubleshooting.* key prefix
- `CHANGELOG.md` - Added guided troubleshooting wizard entry under [Unreleased]

## Decisions Made
- CrashDiagnosis uses `primaryCategory` property (not `category`) for crash evidence extraction -- the struct's field is `primaryCategory: CrashCategory?`
- Rate limiting uses in-memory dictionary rather than UserDefaults since proactive suggestions are session-scoped (resets on app restart is acceptable)
- TroubleshootingTargetPicker follows DiagnosticsPickerSheet pattern exactly: VStack layout, Picker for bottle/program, Cancel/Start buttons
- History view exports to clipboard (NSPasteboard) matching existing AudioTroubleshootingWizardView and EscalationView pattern

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed CrashDiagnosis.category reference**
- **Found during:** Task 1 (WhiskyApp crash banner integration)
- **Issue:** Plan referenced `banner.diagnosis.category` but CrashDiagnosis has `primaryCategory: CrashCategory?` (optional)
- **Fix:** Changed to `banner.diagnosis.primaryCategory?.rawValue ?? "unknown"`
- **Files modified:** Whisky/Views/WhiskyApp.swift
- **Committed in:** 0d37fbb5 (Task 1 commit)

**2. [Rule 1 - Bug] Fixed closure parameter in first(where:) for program matching**
- **Found during:** Task 1 (WhiskyApp crash banner integration)
- **Issue:** Closure for `bottle.programs.first(where:)` implicitly ignored the parameter, causing Swift compiler error
- **Fix:** Added explicit `_ in` parameter label to the closure
- **Files modified:** Whisky/Views/WhiskyApp.swift
- **Committed in:** 0d37fbb5 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Minor API name correction and Swift syntax fix. No scope creep.

## Issues Encountered
- Pre-existing SwiftLint violations in FlowDefinition.swift, FlowValidator.swift, FixApplicator.swift cause SwiftLint script phase to fail; these are from plans 10-01 through 10-05 and do not affect compilation
- All new files compile cleanly with zero new compiler errors or SwiftLint violations

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- This completes Phase 10 (Guided Troubleshooting) - all 7 plans executed
- The complete troubleshooting wizard is integrated end-to-end: WhiskyKit engine + JSON flows + check implementations + session persistence + wizard UI views + entry points + localization
- All 4 locked entry points are wired: Program view (primary), crash banner (launch failure), Config diagnostics (secondary), Help menu (with target picker)

## Self-Check: PASSED

All 3 new Swift files verified present in Whisky/Views/Troubleshooting/. Both commits (0d37fbb5, 604ece20) verified in git log. ProgramView contains showTroubleshootingWizard. ConfigView contains Start Guided Troubleshooting. WhiskyApp contains TroubleshootingTargetPicker. CHANGELOG.md contains guided troubleshooting entry. Localizable.xcstrings contains troubleshooting.* entries.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
