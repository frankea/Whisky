---
phase: 05-stability-diagnostics
plan: 05
subsystem: ui
tags: [swiftui, diagnostics, export, localization, nssavepanel, nspasteboard, winedebug, crash-history]

# Dependency graph
requires:
  - phase: 05-stability-diagnostics/01
    provides: CrashDiagnosis, CrashCategory, ConfidenceTier, WineDebugPreset, PatternLoader
  - phase: 05-stability-diagnostics/02
    provides: DiagnosticExporter, DiagnosisHistory, RemediationTimeline, ExportOptions, Redactor
  - phase: 05-stability-diagnostics/03
    provides: Notification.Name.crashDiagnosisAvailable, ProgramSettings diagnostics fields, Wine.classifyLastRun
  - phase: 05-stability-diagnostics/04
    provides: DiagnosticsView, RemediationCardView, LogViewerView, LogFilterMode
provides:
  - DiagnosticExportSheet with privacy toggles, ZIP save, and Markdown clipboard copy
  - DiagnosisHistoryView with per-program history list, confidence badges, and enhanced logging section
  - Diagnostics entry points in ProgramOverrideSettingsView, ConfigView, and Help menu
  - Crash notification observer with toast banner
  - DiagnosticsPickerSheet for bottle/program selection from Help menu
  - 35 English localization entries for diagnostics strings
affects: [phase-06 if adding more UI surface, phase-10 guided troubleshooting]

# Tech tracking
tech-stack:
  added: [NSSavePanel for ZIP export, NSPasteboard for clipboard copy, UniformTypeIdentifiers for UTType.zip]
  patterns: [sheet-based export with privacy controls, notification observer for crash detection banner, picker sheet for menu command context selection]

key-files:
  created:
    - Whisky/Views/Diagnostics/DiagnosticExportSheet.swift
    - Whisky/Views/Diagnostics/DiagnosisHistoryView.swift
  modified:
    - Whisky/Views/Programs/ProgramOverrideSettingsView.swift
    - Whisky/Views/Bottle/ConfigView.swift
    - Whisky/Views/WhiskyApp.swift
    - Whisky/Localizable.xcstrings
    - Whisky.xcodeproj/project.pbxproj

key-decisions:
  - "DiagnosisHistoryView uses optional closure callbacks for view/re-analyze/rerun actions"
  - "ConfigView diagnostics helpers extracted to extension for SwiftLint type_body_length compliance"
  - "Crash notification banner auto-dismisses after 8 seconds with manual dismiss option"
  - "DiagnosticsPickerSheet uses Picker-based bottle/program selection for Help menu entry point"
  - "Plain English strings used for diagnostics UI (matching plan 05-04 pattern) with xcstrings auto-discovery"

patterns-established:
  - "Export sheet pattern: privacy toggles -> NSSavePanel for ZIP / NSPasteboard for clipboard"
  - "Notification-driven crash banner: onReceive publisher -> overlay banner with auto-dismiss"
  - "Menu command picker sheet: CommandGroup menu item -> sheet with context pickers -> action"

# Metrics
duration: 14min
completed: 2026-02-10
---

# Phase 05 Plan 05: Diagnostics UI Surface Summary

**DiagnosticExportSheet with ZIP/Markdown export and privacy controls, DiagnosisHistoryView with per-program crash history and WineDebugPreset picker, plus five entry points (program settings, bottle config, Help menu, notification banner) and 35 localization entries**

## Performance

- **Duration:** 14 min
- **Started:** 2026-02-10T05:06:54Z
- **Completed:** 2026-02-10T05:20:57Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- DiagnosticExportSheet with privacy toggles (sensitive details, remediation history, full log), NSSavePanel for ZIP save, NSPasteboard for Markdown clipboard copy, and progress indicator
- DiagnosisHistoryView showing last 5 diagnoses per program with category icons, confidence badges, relative timestamps, top signatures, view/re-analyze buttons, clear history with confirmation, and WineDebugPreset picker with re-run action
- Diagnostics section in ProgramOverrideSettingsView embedding full DiagnosisHistoryView with last-analyzed date
- Diagnostics section in ConfigView with export and view diagnosis buttons for most recently diagnosed program
- "Run Diagnostics..." command in Help menu (Cmd+Shift+D) with DiagnosticsPickerSheet for bottle/program selection
- Crash notification observer with toast banner ("Crash detected -- [program]") and auto-dismiss
- 35 English localization entries added to Localizable.xcstrings

## Task Commits

Each task was committed atomically:

1. **Task 1: DiagnosticExportSheet and DiagnosisHistoryView** - `3b427f0e` (feat)
2. **Task 2: Entry points in existing views and localization** - `b4b69130` (feat)

## Files Created/Modified
- `Whisky/Views/Diagnostics/DiagnosticExportSheet.swift` - Export dialog with privacy controls, ZIP save via NSSavePanel, Markdown clipboard copy
- `Whisky/Views/Diagnostics/DiagnosisHistoryView.swift` - Per-program diagnosis history list with confidence badges and enhanced logging section
- `Whisky/Views/Programs/ProgramOverrideSettingsView.swift` - Added Diagnostics section with embedded DiagnosisHistoryView
- `Whisky/Views/Bottle/ConfigView.swift` - Added Diagnostics section with export and view buttons, extracted loading functions to extension
- `Whisky/Views/WhiskyApp.swift` - Added Run Diagnostics menu item, crash notification observer, DiagnosticsPickerSheet, CrashDiagnosisBannerState
- `Whisky/Localizable.xcstrings` - 35 new English localization entries for diagnostics UI
- `Whisky.xcodeproj/project.pbxproj` - Added 2 file references to Diagnostics group

## Decisions Made
- **Optional closure callbacks in DiagnosisHistoryView**: Used optional closures for onViewDetails, onReanalyze, onAnalyzeLastRun, onRerunWithPreset so the view can be embedded in different contexts with different navigation strategies.
- **ConfigView extension extraction**: Moved loadBuildName, loadRetinaMode, loadDpi, and diagnostics helpers to extensions to satisfy SwiftLint type_body_length (was 305 lines, max 250).
- **Auto-dismissing crash banner**: 8-second auto-dismiss with manual close button, using `.overlay(alignment: .top)` with `.transition(.move(edge: .top))`.
- **Picker-based diagnostics entry from Help menu**: DiagnosticsPickerSheet with bottle/program Pickers rather than auto-selecting, since the Help menu has no program context.
- **Plain English localization strings**: Followed the pattern established in plan 05-04 of using English text directly in diagnostics views rather than key-based strings.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed SwiftLint identifier_name violation for 'fm' variable**
- **Found during:** Task 1
- **Issue:** Variable name `fm` in DiagnosticExportSheet's `moveFile` method was shorter than SwiftLint's 3-character minimum
- **Fix:** Renamed `fm` to `fileManager`
- **Files modified:** Whisky/Views/Diagnostics/DiagnosticExportSheet.swift
- **Verification:** SwiftLint passes
- **Committed in:** 3b427f0e

**2. [Rule 3 - Blocking] Fixed SwiftFormat redundantViewBuilder in DiagnosisHistoryView**
- **Found during:** Task 1
- **Issue:** `@ViewBuilder` attribute on `historyEntryRow` method was redundant
- **Fix:** Removed `@ViewBuilder` attribute
- **Files modified:** Whisky/Views/Diagnostics/DiagnosisHistoryView.swift
- **Verification:** SwiftFormat lint passes
- **Committed in:** 3b427f0e

**3. [Rule 3 - Blocking] Fixed SwiftLint type_body_length in ConfigView**
- **Found during:** Task 2
- **Issue:** ConfigView struct body was 305 lines (max 250) after adding diagnostics section
- **Fix:** Extracted loadBuildName, loadRetinaMode, loadDpi, and diagnostics helpers to extensions in the same file
- **Files modified:** Whisky/Views/Bottle/ConfigView.swift
- **Verification:** SwiftLint passes for ConfigView
- **Committed in:** b4b69130

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All fixes necessary for SwiftLint/SwiftFormat compliance. No scope creep.

## Issues Encountered
- Pre-existing SwiftLint errors (25 violations in DiagnosticExporter.swift, CrashClassifierTests.swift, DiagnosticExporterTests.swift, and Wine.swift from plans 05-01/05-02) continue to cause the overall build to fail. None of these are related to plan 05-05 changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 05 (Stability & Diagnostics) is now complete with all 5 plans executed
- All diagnostics UI surface is wired: classification engine, exporters, views, entry points, and localization
- Pre-existing SwiftLint violations from plans 05-01/05-02 should be addressed in a cleanup pass before releasing
- Phase 06 can build on the diagnostics foundation if additional UI features are needed

## Self-Check: PASSED

All 2 created files found. Both task commits verified (3b427f0e, b4b69130). All 4 modified files confirmed. Project.pbxproj updated with 2 new file references.

---
*Phase: 05-stability-diagnostics*
*Completed: 2026-02-10*
