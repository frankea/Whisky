---
phase: 10-guided-troubleshooting
verified: 2026-02-12T01:30:00Z
status: passed
score: 5/5 must-haves verified
---

# Phase 10: Guided Troubleshooting Verification Report

**Phase Goal:** Users can navigate interactive, data-driven troubleshooting flows that diagnose and resolve common issues by integrating diagnostics, compatibility data, and configuration from all previous phases
**Verified:** 2026-02-12T01:30:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A data-driven troubleshooting engine loads symptom/solution decision trees from bundled JSON without hardcoded logic | VERIFIED | `TroubleshootingFlowEngine` (451 lines) navigates `FlowDefinition` graphs loaded from 8 JSON flow files + 2 fragments via `FlowLoader.loadAllFlows()`. `FlowStepNode.on` maps drive all branching. No hardcoded per-category logic in the engine. `Package.swift` declares `.process("Troubleshooting/Resources/")` for SPM bundle inclusion. `FlowValidator` (289 lines) validates graph integrity at load time. |
| 2 | Troubleshooting guides for graphics issues (black screen, artifacts, low FPS) are navigable in-app with step-by-step flows | VERIFIED | `graphics.json` (181 lines) contains 10 nodes: `check_backend` -> `fix_enable_dxvk` -> `check_crash_log` -> `show_crash_findings` -> `check_dxvk_settings` -> `fix_enable_async` -> `check_game_config` -> `suggest_game_config` -> `verify_fix` -> `escalate/resolved`. Automated checks use `graphics.backend_is`, `crash.log_classify`, `dxvk.settings_check`, `game.config_available`. All wired through `TroubleshootingWizardView` which presents `SymptomPickerView` with 8 categories including "Graphics problems". |
| 3 | Troubleshooting guides for audio issues (crackling, missing sound, stuttering) are navigable in-app with step-by-step flows | VERIFIED | `audio.json` (182 lines) contains 11 nodes: `check_audio_device` -> `show_device_issue` -> `check_audio_driver` -> `fix_audio_driver` -> `check_audio_buffer` -> `fix_buffer_size` -> `check_sample_rate` -> `show_sample_rate_info` -> `verify_fix` -> `escalate/resolved`. Automated checks use `audio.device_check`, `audio.driver_check`, `registry.value_check`. Covers crackling (buffer size), missing sound (driver config, device detection), and stuttering (sample rate mismatch). |
| 4 | Troubleshooting guides for launcher issues (Steam, EA, Rockstar, Epic) are navigable in-app with step-by-step flows | VERIFIED | `launcher-issues.json` (193 lines) contains 12 nodes with launcher-type branching: `check_launcher_type` -> `branch_by_launcher` (branches to steam/ea/epic/rockstar/default) -> `check_steam_process` -> `fix_restart_launcher` -> `check_steam_download` -> `show_steam_download_info` -> `check_launcher_env` -> `fix_launcher_env` -> `check_generic_env` -> `verify_fix` -> `escalate/resolved`. Uses `launcher.type_check`, `process.running_check`, `setting.value_check`, `env.check_var` checks. |
| 5 | Guides include automated diagnostic checks that verify current settings, check file existence, and match log patterns before suggesting manual steps | VERIFIED | 15 `TroubleshootingCheck` implementations registered in `CheckRegistry.registerDefaults()`: `CrashLogCheck` (delegates to `CrashClassifier` for log pattern matching), `GraphicsBackendCheck` (verifies current settings), `AudioDriverCheck` (reads bottle settings), `RegistryValueCheck` (checks Wine registry), `EnvironmentCheck` (verifies env vars), `ProcessRunningCheck` (checks running processes), `DependencyCheck`, `WinetricksVerbCheck`, `GameConfigAvailableCheck`, etc. All return normalized `CheckResult` with outcome/evidence/summary for flow branching. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowDefinition.swift` | FlowDefinition and FlowStepNode Codable types | VERIFIED | 208 lines; `struct FlowDefinition: Codable, Sendable`, `struct FlowStepNode: Codable, Sendable, Identifiable` with defensive decoding, `enum NodeType`, `enum FlowPhase`, `struct FixPreviewData` |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/SymptomCategory.swift` | 8 symptom categories enum | VERIFIED | 99 lines; 9 cases (8 named + `.other`); includes `flowFileName`, `displayTitle`, `sfSymbol` computed properties |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckResult.swift` | Normalized check outcome with evidence | VERIFIED | 73 lines; `struct CheckResult: Sendable, Codable` with outcome/evidence/summary/confidence; `enum CheckOutcome` with pass/fail/already_configured/unknown/error |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingCheck.swift` | Protocol for check implementations | VERIFIED | 59 lines; `protocol TroubleshootingCheck: Sendable` with `checkId` and `func run(params:context:) async -> CheckResult` |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingSession.swift` | Session state for wizard persistence | VERIFIED | 262 lines; full session state with id, bottleURL, programURL, symptomCategory, phase, stepHistory, currentNodeId, checkResults, fixAttempts, branchDecisions, outcome, preflightSnapshot; mutating methods for pushStep/recordCheckResult/recordFixAttempt/recordBranch |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingFlowEngine.swift` | JSON-driven state machine | VERIFIED | 451 lines; `@MainActor class TroubleshootingFlowEngine: ObservableObject` with selectCategory/navigateToNode/runCheck/applyFix/userReportsFixed/userReportsNotFixed/skipStep/goBack/escalate/startOver. Cycle protection (50 step limit). Auto-saves via TroubleshootingSessionStoring protocol. |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowLoader.swift` | JSON flow loading from bundle resources | VERIFIED | 155 lines; `enum FlowLoader` with loadIndex/loadFlow/loadAllFlows/loadFragments using `Bundle.module` |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowValidator.swift` | Flow graph validation | VERIFIED | 289 lines; `enum FlowValidator` validates dangling refs, missing fragments, unreachable nodes, long automated paths. BFS reachability + DFS depth analysis. |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckRegistry.swift` | Check ID to implementation mapping | VERIFIED | 143 lines; `class CheckRegistry: @unchecked Sendable` with thread-safe registration, `registerDefaults()` registers all 15 checks, `run(checkId:params:context:)` with fallback error result |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/PreflightCollector.swift` | Cheap eager preflight data collection | VERIFIED | 162 lines; `enum PreflightCollector` with `collect(bottle:program:)` gathering wineserver state, process count, graphics backend, audio device, recent log URL, exit code |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingSessionStore.swift` | Session save/load/expire/delete operations | VERIFIED | 264 lines; `struct TroubleshootingSessionStore: TroubleshootingSessionStoring` with atomic plist writes, 14-day staleness expiry, history archival, staleness change detection |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingHistory.swift` | Bounded completed session history | VERIFIED | File exists and is used by TroubleshootingSessionStore.completeSession() and TroubleshootingHistoryView |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FixApplicator.swift` | Fix application with preview, apply, undo | VERIFIED | 449 lines; `enum FixApplicator` with 10 known fix IDs, `preview(fixId:params:bottle:program:)`, `apply(fixId:params:bottle:program:)`, `undo(attempt:bottle:program:)`. Handles graphics backend, DXVK async, audio driver, buffer size, esync, controller compat, winetricks, dependency, diagnostics, wineserver restart. |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/index.json` | Category metadata with entry nodes | VERIFIED | 69 lines; 8 categories with id/title/sfSymbol/flowFile/depth/description |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/graphics.json` | Graphics troubleshooting flow | VERIFIED | 181 lines; 10 nodes with check/fix/verify/info types, uses graphics.backend_is/crash.log_classify/dxvk.settings_check/game.config_available |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/audio.json` | Audio troubleshooting flow | VERIFIED | 182 lines; 11 nodes covering device check, driver config, buffer size, sample rate |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/launcher-issues.json` | Launcher troubleshooting flow | VERIFIED | 193 lines; 12 nodes with Steam/EA/Epic/Rockstar branching, process checks, env var fixes |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/fragments/export-escalation.json` | Shared escalation subflow | VERIFIED | 95 lines; 6 nodes for escalation/enhanced diagnostics/export/support draft. Referenced by all 8 flow files via `fragmentRef: "export-escalation"` |
| `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Checks/*.swift` (15 files) | Check implementations | VERIFIED | 15 files totaling 1301 lines (42-156 lines each). All implement `TroubleshootingCheck` protocol with real delegation to existing diagnostic primitives. |
| `Whisky/Views/Troubleshooting/TroubleshootingWizardView.swift` | Main single-page wizard sheet | VERIFIED | 312 lines; HStack layout with ProgressRailView (180px) + step area. Phase-switched content: SymptomPickerView/StepCardView/FixPreviewView/FixVerifyView/EscalationView. Session resume overlay. Uses `@StateObject TroubleshootingFlowEngine`. |
| `Whisky/Views/Troubleshooting/ProgressRailView.swift` | 5-phase vertical progress rail | VERIFIED | 188 lines; 5 fixed phases (Symptom/Checks/Fix/Verify/Export) with state-based styling (completed/active/upcoming/superseded) |
| `Whisky/Views/Troubleshooting/StepCardView.swift` | Individual step card rendering | VERIFIED | 210 lines; Renders FlowStepNode with type icon, title, description, evidence section, confidence badge |
| `Whisky/Views/Troubleshooting/SymptomPickerView.swift` | 8-category symptom selection | VERIFIED | 119 lines; LazyVGrid with 8 primary categories + "Other", SF Symbols, descriptions, calls engine.selectCategory() |
| `Whisky/Views/Troubleshooting/FixPreviewView.swift` | Diff-style fix preview with Apply button | VERIFIED | 248 lines; Monospace diff layout (red-/green+), reversibility indicator, explicit Apply button with confirmation gate, FixApplicator.preview/apply integration |
| `Whisky/Views/Troubleshooting/FixVerifyView.swift` | Did this fix it? confirmation gate | VERIFIED | 167 lines; "Yes, it's fixed" / "No, still broken" buttons, attempt counter (3 max), undo button |
| `Whisky/Views/Troubleshooting/EscalationView.swift` | Unresolved outcome view | VERIFIED | 363 lines; Enhanced diagnostics, export diagnostics, support issue draft, retry from step options |
| `Whisky/Views/Troubleshooting/BranchExplanationView.swift` | Branch explanation banner | VERIFIED | 69 lines; Dismissable info bar showing path change reason |
| `Whisky/Views/Troubleshooting/SessionResumeView.swift` | Session resume overlay | VERIFIED | 166 lines; "Since you left" staleness changes, Resume/Start Over/Discard actions |
| `Whisky/Views/Troubleshooting/TroubleshootingHistoryView.swift` | Per-bottle troubleshooting history | VERIFIED | 224 lines; Expandable entry rows with outcome badges, fix details, reopen/export actions |
| `Whisky/Views/Troubleshooting/TroubleshootingTargetPicker.swift` | Bottle/program picker for Help menu | VERIFIED | 82 lines; Bottle picker + optional program picker, triggers wizard launch |
| `Whisky/Views/Troubleshooting/TroubleshootingEntryBanner.swift` | Proactive suggestion/resume banner | VERIFIED | 81 lines; Two types: resumeSession and proactiveSuggestion with appropriate icons and messages |
| `WhiskyKit/Package.swift` | SPM resource declaration | VERIFIED | Contains `.process("Troubleshooting/Resources/")` at line 44 |
| `Whisky.xcodeproj/project.pbxproj` | All view files registered | VERIFIED | 52 Troubleshooting view file references across build phases and groups |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `TroubleshootingFlowEngine` | `CheckRegistry` | `checkRegistry.run(checkId:params:context:)` | WIRED | Line 227 in engine calls `checkRegistry.run(checkId:params:context:)` |
| `TroubleshootingFlowEngine` | `FlowLoader` | Flow definitions loaded at init | WIRED | WizardView init calls `FlowLoader.loadAllFlows()` and `FlowLoader.loadFragments()`, passes to engine constructor |
| `FlowLoader` | `Resources/*.json` | `Bundle.module` resource loading | WIRED | `FlowLoader.loadIndex()` line 45: `Bundle.module.url(forResource: "index", withExtension: "json")` |
| `TroubleshootingWizardView` | `TroubleshootingFlowEngine` | `@StateObject` | WIRED | Line 32: `@StateObject private var engine: TroubleshootingFlowEngine`; init creates engine with all dependencies |
| `StepCardView` | `FlowStepNode` | Renders node content | WIRED | Takes `FlowStepNode` and `CheckResult?` as parameters, renders title/description/evidence |
| `FixPreviewView` | `FixApplicator` | preview/apply calls | WIRED | `loadPreview()` calls `FixApplicator.preview()`, `applyFix()` calls `FixApplicator.apply()` |
| `ProgramView` | `TroubleshootingWizardView` | `.sheet` presentation | WIRED | `@State showTroubleshootingWizard`, "Troubleshoot..." button, `.sheet(isPresented:)` presenting `TroubleshootingWizardView` |
| `WhiskyApp` | `TroubleshootingTargetPicker` | Help menu -> sheet -> picker -> wizard | WIRED | Help menu "Troubleshoot" button -> `showTroubleshootingPicker` sheet -> `TroubleshootingTargetPicker` -> `showTroubleshootingWizard` sheet |
| `ConfigView` | `TroubleshootingHistoryView` | Diagnostics section embeds history | WIRED | "Start Guided Troubleshooting" link + `TroubleshootingHistoryView(bottleURL:programURL:)` embedded in diagnostics section |
| `TroubleshootingSessionStore` | `TroubleshootingSession` | PropertyListEncoder/Decoder | WIRED | `save()` uses `PropertyListEncoder().encode(session)`, `loadActiveSession()` uses `PropertyListDecoder().decode()` |
| `TroubleshootingSessionStore` | `TroubleshootingHistory` | completeSession archives | WIRED | `completeSession()` creates `TroubleshootingHistoryEntry`, calls `history.append(entry)` and `history.save(to:)` |
| `CrashLogCheck` | `CrashClassifier` | Delegation | WIRED | Line 54: `let classifier = CrashClassifier()` + `classifier.classify(log:exitCode:)` |
| Flows `*.json` | Fragment `export-escalation` | `fragmentRef` field | WIRED | All 8 flow files contain `"fragmentRef": "export-escalation"` on their escalate nodes |
| `index.json` | `flows/*.json` | `flowFile` field | WIRED | Each of 8 categories has `"flowFile": "*.json"` matching actual flow file names |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| TRBL-01: Data-driven troubleshooting engine loads symptom/solution mappings from JSON | SATISFIED | N/A |
| TRBL-02: User can navigate troubleshooting guides for graphics issues | SATISFIED | N/A |
| TRBL-03: User can navigate troubleshooting guides for audio issues | SATISFIED | N/A |
| TRBL-04: User can navigate troubleshooting guides for launcher issues | SATISFIED | N/A |
| TRBL-05: Troubleshooting guides include automated diagnostic checks | SATISFIED | N/A |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | - | - | - | - |

No TODOs, FIXMEs, placeholders, empty implementations, or stub patterns were detected in any of the 46 Phase 10 files (34 Swift files + 11 JSON files + 1 .gitkeep). The only "placeholder" references in `TroubleshootingWizardView.swift` are legitimate loading spinner views shown while checks execute asynchronously.

### Human Verification Required

### 1. End-to-End Wizard Flow

**Test:** Open Whisky, select a bottle with a program, click "Troubleshoot..." in ProgramView. Select "Graphics problems" category. Observe the wizard navigating through check/fix/verify steps.
**Expected:** Progress rail updates phase highlights. Check steps show evidence and confidence badges. Fix steps show diff-style preview. Verify gate shows "Did this fix it?" with Yes/No buttons. Back/Skip navigation works.
**Why human:** Visual layout, animation smoothness, and real check execution against actual Wine/bottle state cannot be verified programmatically.

### 2. Help Menu Entry Point

**Test:** Open Help menu, click "Troubleshoot...", select a bottle and optionally a program from the target picker, confirm.
**Expected:** Target picker sheet appears with bottle/program pickers. After selection, the troubleshooting wizard opens with the selected context.
**Why human:** Menu integration and sheet presentation chaining require runtime UI interaction.

### 3. Session Resume After Quit

**Test:** Start a troubleshooting session, progress through several steps, close the wizard. Reopen it for the same bottle.
**Expected:** Resume overlay appears showing session category, relative time, and "Since you left" staleness changes if any settings changed. Resume/Start Over/Discard options work correctly.
**Why human:** Session persistence via plist and staleness detection require actual file I/O and time-based behavior.

### 4. Launch Failure Proactive Suggestion

**Test:** Configure a program that fails to launch (e.g., missing dependency). Launch it, observe the crash banner. Click the "Troubleshoot" action on the banner.
**Expected:** Wizard opens pre-filled with crash evidence from the launch failure, starting at the appropriate category flow.
**Why human:** Requires actual Wine process launch failure to trigger the crash detection path.

### 5. Audio Troubleshooting Flow Correctness

**Test:** Navigate the audio troubleshooting flow with a bottle that has non-default audio settings.
**Expected:** Audio device check detects current device. Driver check reads actual registry value. Buffer size check reads actual DirectSound setting. Fix steps apply real settings changes. Verify gate confirms resolution.
**Why human:** Audio checks interact with CoreAudio and Wine registry, requiring real system state.

### Gaps Summary

No gaps found. All 5 observable truths are verified against the codebase. All artifacts exist at all three levels (exists, substantive, wired). All key links are confirmed. All 5 TRBL requirements are satisfied.

The implementation delivers:
- A fully data-driven engine (`TroubleshootingFlowEngine`) that navigates JSON flow graphs without hardcoded per-category logic
- 8 category flow definitions (1392 lines of JSON) with proper decision tree structure
- 2 shared fragments (export-escalation, dependency-install) referenced by all flows
- 15 concrete check implementations wrapping existing diagnostic primitives
- Session persistence with atomic writes, 14-day staleness expiry, and bounded history
- Fix application with diff preview, explicit apply gate, and undo support
- 12 SwiftUI views providing the complete wizard UI
- 4 entry points: ProgramView button, Help menu, ConfigView link, launch failure banner
- 60 localization keys for user-facing strings
- FlowValidator for structural integrity checking at load time

---

_Verified: 2026-02-12T01:30:00Z_
_Verifier: Claude (gsd-verifier)_
