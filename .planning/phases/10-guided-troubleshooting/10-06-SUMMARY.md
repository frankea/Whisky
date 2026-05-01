---
phase: 10-guided-troubleshooting
plan: 06
subsystem: ui
tags: [swiftui, wizard-ui, progress-rail, symptom-picker, fix-preview, session-resume, escalation, xcode-project]

# Dependency graph
requires:
  - phase: 10-guided-troubleshooting
    provides: TroubleshootingFlowEngine, FlowStepNode, SymptomCategory, TroubleshootingSession, CheckResult, FixApplicator, TroubleshootingSessionStore, StalenessChange, EntryContext, PreflightData, ConfidenceTier
  - phase: 06-audio-troubleshooting
    provides: AudioTroubleshootingWizardView pattern for wizard sheet layout
  - phase: 05-stability-diagnostics
    provides: RemediationCardView confidence badge pattern, ConfidenceTier color scheme
provides:
  - TroubleshootingWizardView main sheet with HStack layout (rail + step area)
  - ProgressRailView 5-phase vertical rail with state-based styling
  - SymptomPickerView 8-category grid with SF Symbols
  - StepCardView with evidence display and confidence badges
  - FixPreviewView diff-style preview with explicit Apply gate
  - FixVerifyView "Did this fix it?" confirmation with undo support
  - BranchExplanationView inline path-changed notification
  - SessionResumeView overlay with Resume/Start Over/Discard and staleness
  - EscalationView with 4 escalation options (diagnostics, export, issue draft, retry)
  - Xcode project Troubleshooting group under Views
affects: [10-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wizard sheet layout: HStack with fixed-width ProgressRailView (180pt) + scrollable step area"
    - "Phase state derivation: phaseOrder comparison with superseded step detection from stepHistory"
    - "Diff-style preview: monospace red (removal) + green (addition) with FixApplicator.preview read-only inspection"
    - "Escalation button factory: reusable escalationButton method for consistent option card styling"

key-files:
  created:
    - Whisky/Views/Troubleshooting/TroubleshootingWizardView.swift
    - Whisky/Views/Troubleshooting/ProgressRailView.swift
    - Whisky/Views/Troubleshooting/SymptomPickerView.swift
    - Whisky/Views/Troubleshooting/StepCardView.swift
    - Whisky/Views/Troubleshooting/FixPreviewView.swift
    - Whisky/Views/Troubleshooting/FixVerifyView.swift
    - Whisky/Views/Troubleshooting/BranchExplanationView.swift
    - Whisky/Views/Troubleshooting/SessionResumeView.swift
    - Whisky/Views/Troubleshooting/EscalationView.swift
  modified:
    - Whisky.xcodeproj/project.pbxproj

key-decisions:
  - "FixVerifyView.canUndo uses FixApplicator.preview (read-only) to check reversibility instead of calling FixApplicator.undo which would mutate state"
  - "ProgressRailView uses .tint/.accentColor instead of .accent (unavailable in macOS SwiftUI)"
  - "BranchExplanationView uses Color(.secondarySystemFill) for subtle background on macOS"
  - "EscalationView exports diagnostics to clipboard (matching AudioTroubleshootingWizardView pattern)"
  - "Stub views created in Task 1 for compilation, replaced with full implementations in Tasks 2 and 3"

patterns-established:
  - "Wizard sheet layout: 180pt fixed-width rail + scrollable step area in HStack"
  - "Phase-based content switching: switch on engine.session.phase for step area content"
  - "Escalation options: reusable button factory with title/description/symbol/action pattern"
  - "Session resume overlay: ZStack with dimmed background + centered card"

# Metrics
duration: 9min
completed: 2026-02-12
---

# Phase 10 Plan 06: Wizard UI Views Summary

**9 SwiftUI views for the troubleshooting wizard: single-page layout with 5-phase progress rail, 8-category symptom picker, diff-style fix preview with gated Apply, Yes/No verify gate, session resume overlay, and 4-option escalation path**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-12T04:23:03Z
- **Completed:** 2026-02-12T04:32:32Z
- **Tasks:** 3
- **Files modified:** 10

## Accomplishments
- Built the complete wizard UI surface: TroubleshootingWizardView as main sheet with HStack layout (180pt progress rail + scrollable step area), toolbar with Close/Back/Skip, and session resume detection on appear
- All 9 view files compile cleanly under Swift 6 with no new SwiftLint violations
- FixPreviewView uses FixApplicator.preview() for read-only diff display and FixApplicator.apply() for gated execution, with confirmation dialogs for high-impact changes
- EscalationView provides 4 escalation paths: enhanced WINEDEBUG diagnostics, clipboard export, GitHub issue draft, and retry from a previous step

## Task Commits

Each task was committed atomically:

1. **Task 1: TroubleshootingWizardView, ProgressRailView, SymptomPickerView** - `e8c02ac1` (feat)
2. **Task 2: StepCardView, FixPreviewView, FixVerifyView** - `288b5b28` (feat)
3. **Task 3: BranchExplanationView, SessionResumeView, EscalationView** - `6ffe3a8d` (feat)

## Files Created/Modified
- `Whisky/Views/Troubleshooting/TroubleshootingWizardView.swift` - Main wizard sheet with @StateObject engine, HStack layout, phase-based content switching, session resume detection, and preflight collection
- `Whisky/Views/Troubleshooting/ProgressRailView.swift` - 5-phase vertical rail (Symptom/Checks/Fix/Verify/Export) with completed/active/upcoming/superseded styling and connector lines
- `Whisky/Views/Troubleshooting/SymptomPickerView.swift` - 2-column adaptive grid of 8 categories with SF Symbols, descriptions, and "Other" at reduced visual weight
- `Whisky/Views/Troubleshooting/StepCardView.swift` - Card rendering for check/info/branch/fix/verify nodes with evidence key-value display, outcome icons, and ConfidenceTier badges
- `Whisky/Views/Troubleshooting/FixPreviewView.swift` - Diff-style preview (red removal, green addition) with FixApplicator.preview/apply integration, reversibility indicator, and confirmation alert
- `Whisky/Views/Troubleshooting/FixVerifyView.swift` - "Did this fix it?" gate with Yes (green)/No buttons, fix attempt counter (X of 3), and undo button using FixApplicator.preview for reversibility check
- `Whisky/Views/Troubleshooting/BranchExplanationView.swift` - Inline info bar with "Path updated" reason and dismiss button
- `Whisky/Views/Troubleshooting/SessionResumeView.swift` - Modal overlay card with session summary, relative time, "Since you left" staleness changes, and Resume/Start Over/Discard buttons
- `Whisky/Views/Troubleshooting/EscalationView.swift` - 4-option escalation: enhanced diagnostics, clipboard export, GitHub issue draft, and retry from step picker
- `Whisky.xcodeproj/project.pbxproj` - Added Troubleshooting group under Views with all 9 file references

## Decisions Made
- FixVerifyView.canUndo uses FixApplicator.preview() (read-only) instead of FixApplicator.undo() to avoid mutating state during computed property evaluation -- this was an auto-fixed bug (Rule 1)
- ProgressRailView uses .tint/.accentColor instead of .accent which is not available in macOS SwiftUI
- Stub views created in Task 1 for all 9 files to enable immediate compilation, then replaced with full implementations in Tasks 2 and 3
- EscalationView exports diagnostics to clipboard (NSPasteboard) matching the AudioTroubleshootingWizardView pattern rather than creating a file

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed canUndo calling FixApplicator.undo (mutating) instead of preview (read-only)**
- **Found during:** Task 2 (FixVerifyView implementation)
- **Issue:** canUndo computed property was calling FixApplicator.undo() which actually performs the undo, causing unintended side effects during view rendering
- **Fix:** Changed to use FixApplicator.preview() which returns isReversible without mutating state
- **Files modified:** Whisky/Views/Troubleshooting/FixVerifyView.swift
- **Verification:** Build succeeds, no side effects from computed property
- **Committed in:** 288b5b28 (Task 2 commit)

**2. [Rule 3 - Blocking] Created stub views in Task 1 for compilation**
- **Found during:** Task 1 (TroubleshootingWizardView references views from Tasks 2/3)
- **Issue:** TroubleshootingWizardView references StepCardView, FixPreviewView, FixVerifyView, BranchExplanationView, SessionResumeView, EscalationView which don't exist yet
- **Fix:** Created minimal stub implementations with correct signatures, replaced with full versions in Tasks 2 and 3
- **Files modified:** All 6 stub view files
- **Verification:** Build succeeds at each task boundary
- **Committed in:** e8c02ac1 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered
- `.accent` color style unavailable on macOS SwiftUI (used `.tint` and `.accentColor` instead)
- SwiftLint `superfluous_disable_command` violation when file_length disable was not needed (removed)
- SwiftLint `trailing_comma` violation in array literal (removed trailing comma)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 9 wizard UI views ready for Plan 07 integration (entry points, wiring, and final testing)
- TroubleshootingWizardView accepts Bottle, Program?, and EntryContext for flexible entry points
- Engine observation via @StateObject/@ObservedObject pattern established for all views
- Xcode project updated with Troubleshooting group containing all view files

## Self-Check: PASSED

All 9 Swift files verified present in Whisky/Views/Troubleshooting/. All 3 commits (e8c02ac1, 288b5b28, 6ffe3a8d) verified in git log. Xcode project contains Troubleshooting group with file references. Swift compilation succeeds with zero new compiler errors.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
