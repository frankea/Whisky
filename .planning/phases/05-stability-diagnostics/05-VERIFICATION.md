---
phase: 05-stability-diagnostics
verified: 2026-02-10T09:15:00Z
status: gaps_found
score: 22/24 must-haves verified
gaps:
  - truth: "All user-facing strings are localized in EN xcstrings file with structured diagnostics.* prefix"
    status: partial
    reason: "Strings are present in xcstrings but using plain English with auto-discovery instead of structured prefix"
    artifacts:
      - path: "Whisky/Localizable.xcstrings"
        issue: "35 localization entries added but not using diagnostics.* prefix pattern as specified in plan"
    missing:
      - "Strings are functionally localized (SwiftUI auto-discovers) but not following the structured naming convention from 05-05 plan"
  - truth: "App builds cleanly without SwiftLint violations"
    status: failed
    reason: "SwiftLint type_body_length violation in DiagnosticExporterTests.swift (378 lines vs 350 max)"
    artifacts:
      - path: "WhiskyKit/Tests/WhiskyKitTests/DiagnosticExporterTests.swift"
        issue: "Test file exceeds 350-line SwiftLint limit by 28 lines"
    missing:
      - "Split DiagnosticExporterTests into multiple test classes or request SwiftLint exception"
---

# Phase 5: Stability & Diagnostics Verification Report

**Phase Goal:** Wine error output is automatically classified so users receive actionable crash guidance instead of raw logs

**Verified:** 2026-02-10T09:15:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | WINEDEBUG output is parsed and classified into categories: access violations, GPU errors, DLL load failures, and other patterns | ✓ VERIFIED | patterns.json has 22 patterns across 7 categories: coreCrashFatal (4), graphics (5), dependenciesLoading (6), prefixFilesystem (2), networkingLaunchers (2), antiCheatUnsupported (2), otherUnknown (1) |
| 2 | Known crash patterns are matched to specific remediation suggestions displayed to the user | ✓ VERIFIED | remediations.json has 9 actions; patterns link via remediationActionIds; RemediationCardView displays with confidence badges and action buttons |
| 3 | GPU-specific crash patterns (IOMFB faults, Metal compilation errors) produce targeted troubleshooting guidance | ✓ VERIFIED | 3 GPU patterns (gpu-device-lost-dxvk, gpu-metal-validation, gpu-d3d-device-hung) link to 3 GPU remediations (switch-backend, disable-dxr, force-dx11) |
| 4 | Diagnostic report exports include a classified error summary section alongside the raw log | ✓ VERIFIED | DiagnosticExporter generates report.md with Diagnosis Summary (headline, category, confidence, counts), Matched Patterns (top 5), Suggested Remediations, plus crash.json, wine.log, system.json in ZIP |
| 5 | CrashClassifier scans log text line-by-line against pattern definitions and returns scored DiagnosisMatch entries grouped by category | ✓ VERIFIED | CrashClassifier.classify() implements 5-step pipeline: split lines, match patterns, aggregate by category, compute primary diagnosis, collect remediation IDs (158 lines) |
| 6 | Substring prefilter on each CrashPattern is checked before regex evaluation for performance | ✓ VERIFIED | CrashPattern.match() line 129-131: if let prefilter = substringPrefilter, !line.contains(prefilter) { return nil } |
| 7 | Every pattern in patterns.json has at least one positive-match unit test fixture | ✓ VERIFIED | CrashClassifierTests.swift has 39 test methods covering all patterns (590 lines) |
| 8 | CrashDiagnosis produces a 3-tier confidence model (High/Medium/Low) from internal numeric scores (0-1) | ✓ VERIFIED | ConfidenceTier.init(score:) mapping: >= 0.8 = .high, >= 0.5 = .medium, else .low (73 lines) |
| 9 | remediations.json contains action definitions separate from pattern definitions, linked by ID | ✓ VERIFIED | remediations.json has 9 actions with id, title, actionType, risk, whatWillChange fields; patterns reference via remediationActionIds array |
| 10 | DiagnosisHistory stores last 5 entries per program with FIFO eviction and Codable persistence | ✓ VERIFIED | DiagnosisHistory.append() enforces maxEntries = 5 with FIFO eviction; PropertyListEncoder/Decoder round-trip (143 lines) |
| 11 | Redactor scrubs home paths to /Users/<redacted> and filters env vars matching TOKEN, KEY, SECRET, PASSWORD, AUTH | ✓ VERIFIED | Redactor.redactHomePaths() replaces FileManager.homeDirectory patterns; redactEnvironment() filters sensitiveKeyPatterns (97 lines) |
| 12 | DiagnosticExporter produces a ZIP via /usr/bin/ditto containing report.md, crash.json, env.json, settings plists, wine.log, and system.json | ✓ VERIFIED | exportZIP() creates contentDir with 8 files, runs ditto -c -k for compression (532 lines) |
| 13 | DiagnosticExporter produces a Markdown string suitable for pasting into GitHub issues | ✓ VERIFIED | generateMarkdownReport() returns redacted Markdown with system info, bottle config, diagnosis summary, patterns, remediations (always redacted) |
| 14 | WINEDEBUG presets are injected through EnvironmentBuilder featureRuntime layer when a diagnostic preset is active | ✓ VERIFIED | WineEnvironment.swift lines 94-97: if let preset = programSettings?.activeWineDebugPreset, preset != .normal { builder.set("WINEDEBUG", preset.winedebugValue, layer: .featureRuntime) } |
| 15 | ProgramSettings stores the active WineDebugPreset and most recent log file URL for diagnosis context | ✓ VERIFIED | ProgramSettings has activeWineDebugPreset: WineDebugPreset?, lastLogFileURL: URL?, lastDiagnosisDate: Date? with Codable |
| 16 | Classification auto-triggers when Wine process exits non-zero via a post-exit callback | ✓ VERIFIED | Program+Extensions.swift calls Wine.classifyLastRun() on non-zero exit; posts Notification.Name.crashDiagnosisAvailable |
| 17 | DiagnosticsView shows summary-first layout with headline diagnosis at top, remediation cards below, and collapsible raw log at bottom | ✓ VERIFIED | DiagnosticsView.swift (398 lines) has headline section with confidence badge, category counts, remediation cards vertical stack, DisclosureGroup for log |
| 18 | Remediation cards display confidence tier label, what-will-change sentence, undo path, and applies-next-launch note | ✓ VERIFIED | RemediationCardView.swift (252 lines) renders confidenceBadge, action.whatWillChange, footerInfo with appliesNextLaunch |
| 19 | Low-risk remediation cards have direct action buttons; higher-risk cards have guided confirmation paths | ✓ VERIFIED | RemediationCardView actionButton switches on risk: .low = direct "Apply", else confirmation alert |
| 20 | LogViewerView uses NSTextView for large-log performance with background tint and left gutter markers on matched lines | ✓ VERIFIED | LogViewerView.swift (333 lines) wraps NSTextView via NSViewRepresentable; applies NSAttributedString styling with background colors for tagged lines |
| 21 | DiagnosticExportSheet has checkboxes for 'Include sensitive details' (off by default) and 'Don't include remediation history' | ✓ VERIFIED | DiagnosticExportSheet.swift (236 lines) has @State toggles for includeSensitive (default false), includeRemediationHistory (default true), includeFullLog (default true) |
| 22 | DiagnosisHistoryView shows last 5 diagnoses per program with 'View details' and 'Re-analyze' buttons | ✓ VERIFIED | DiagnosisHistoryView.swift (252 lines) lists entries with category icon, confidence badge, timestamp, "View Details" and "Re-analyze" buttons |
| 23 | Diagnostics accessible from: Diagnostics view toolbar, Log viewer toolbar, Program settings Diagnostics section, Bottle settings, Help menu | ✓ VERIFIED | ProgramOverrideSettingsView embeds DiagnosisHistoryView; ConfigView has Diagnostics section; WhiskyApp has "Run Diagnostics..." Help menu command (Cmd+Shift+D) |
| 24 | All user-facing strings are localized in EN xcstrings file | ⚠️ PARTIAL | 35 localization entries added to Localizable.xcstrings per summary; strings use plain English with SwiftUI auto-discovery instead of structured diagnostics.* prefix as specified in plan 05-05 |

**Score:** 22/24 truths verified (2 partial/failed)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashClassifier.swift | Classification pipeline: load patterns, scan log lines, score and group matches | ✓ VERIFIED | 158 lines, classify() method with 5-step pipeline |
| WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json | Versioned pattern database with regex, prefilter, category, confidence per pattern | ✓ VERIFIED | 22 patterns, version 1 schema, 8343 bytes |
| WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/remediations.json | Remediation action definitions with type, parameters, risk level | ✓ VERIFIED | 9 actions, version 1 schema, 5161 bytes |
| WhiskyKit/Tests/WhiskyKitTests/CrashClassifierTests.swift | Unit tests with sample log lines for every pattern rule | ✓ VERIFIED | 590 lines, 39 test methods |
| WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosisHistory.swift | Per-program diagnosis persistence with bounded FIFO entries | ✓ VERIFIED | 143 lines, maxEntries = 5 |
| WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosticExporter.swift | ZIP and Markdown export with redaction and privacy controls | ✓ VERIFIED | 532 lines, exportZIP() and generateMarkdownReport() |
| WhiskyKit/Sources/WhiskyKit/Diagnostics/Redactor.swift | Composable redaction pipeline for home paths and sensitive env vars | ✓ VERIFIED | 97 lines, redactHomePaths() and redactEnvironment() |
| WhiskyKit/Tests/WhiskyKitTests/DiagnosticExporterTests.swift | Tests for redaction, history bounds, and export content | ⚠️ SWIFTLINT | 491 lines, all tests pass but exceeds 350-line SwiftLint limit (378 line body) |
| WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift | WINEDEBUG preset injection in constructWineEnvironment via featureRuntime layer | ✓ VERIFIED | Lines 94-97 inject preset when activeWineDebugPreset != .normal |
| WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift | activeWineDebugPreset and lastLogFileURL fields for diagnosis tracking | ✓ VERIFIED | Lines 155, 180-182 add fields with Codable |
| WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift | Post-exit classification trigger in runProgram output stream | ✓ VERIFIED | Wine.classifyLastRun() lines 747-784 |
| Whisky/Views/Diagnostics/DiagnosticsView.swift | Main diagnostics view with summary-first split layout | ✓ VERIFIED | 398 lines, responsive split at 700pt threshold |
| Whisky/Views/Diagnostics/RemediationCardView.swift | Actionable remediation card with confidence, description, and action buttons | ✓ VERIFIED | 252 lines, standard + anti-cheat cards |
| Whisky/Views/Diagnostics/LogViewerView.swift | NSTextView-backed log viewer with gutter markers and filtering | ✓ VERIFIED | 333 lines, NSViewRepresentable wrapper |
| Whisky/Views/Diagnostics/DiagnosticExportSheet.swift | Export dialog with privacy controls, ZIP save, and clipboard copy | ✓ VERIFIED | 236 lines, NSSavePanel + NSPasteboard |
| Whisky/Views/Diagnostics/DiagnosisHistoryView.swift | Per-program diagnosis history list with view/re-analyze/clear actions | ✓ VERIFIED | 252 lines, last 5 entries display |
| Whisky/Views/Programs/ProgramOverrideSettingsView.swift | Diagnostics section in program settings with history panel and enhanced logging | ✓ VERIFIED | Lines 53, 69 embed DiagnosticsView and DiagnosisHistoryView |
| Whisky/Localizable.xcstrings | EN localization entries for all diagnostics strings | ⚠️ PARTIAL | 35 entries added (per summary), uses plain English auto-discovery instead of structured prefix |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| CrashClassifier | patterns.json | PatternLoader.loadPatterns(from:) at init | ✓ WIRED | Line 67: let (patterns, remediations) = PatternLoader.loadDefaults() |
| CrashPattern.match(line:) | substringPrefilter | fast path: String.contains() before Regex evaluation | ✓ WIRED | Lines 129-131: if let prefilter = substringPrefilter, !line.contains(prefilter) { return nil } |
| CrashDiagnosis | ConfidenceTier | numeric score mapped to .high/.medium/.low tiers | ✓ WIRED | ConfidenceTier.init(score:) in CrashDiagnosis.primaryConfidence computed property |
| DiagnosticExporter | Redactor | all content passes through redaction before export | ✓ WIRED | Lines 156, 168, 374, 386: Redactor.redactLogText() and Redactor.redactEnvironment() |
| DiagnosticExporter | CrashDiagnosis | encodes diagnosis to crash.json in ZIP | ✓ WIRED | Lines 127-128: JSONEncoder encodes CrashDiagnosisCodableWrapper |
| DiagnosisHistory | DiagnosisHistoryEntry | FIFO append with maxEntries cap | ✓ WIRED | append() method enforces maxEntries = 5 |
| Wine.runProgram | CrashClassifier.classify | post-exit callback when exitCode != 0 | ✓ WIRED | Program+Extensions line 156: Wine.classifyLastRun() |
| WineDebugPreset | EnvironmentBuilder.set | featureRuntime layer WINEDEBUG override | ✓ WIRED | WineEnvironment lines 95-96: builder.set("WINEDEBUG", preset.winedebugValue, layer: .featureRuntime) |
| ProgramSettings.activeWineDebugPreset | constructWineEnvironment | preset read during environment construction | ✓ WIRED | WineEnvironment line 95: if let preset = programSettings?.activeWineDebugPreset |
| DiagnosticsView | CrashDiagnosis | displays diagnosis summary, matches, and remediations | ✓ WIRED | Line 24: let diagnosis: CrashDiagnosis? |
| RemediationCardView | RemediationAction | renders action details and executes on button tap | ✓ WIRED | Line 25: let action: RemediationAction |
| LogViewerView | DiagnosisMatch | highlights matched lines with gutter markers | ✓ WIRED | applyMatchStyling() uses diagnosisMatches.lineIndex |
| DiagnosticExportSheet | DiagnosticExporter | calls exportZIP/generateMarkdownReport with user-selected options | ✓ WIRED | saveZIP() and copyToClipboard() methods call DiagnosticExporter static methods |
| DiagnosisHistoryView | DiagnosisHistory | loads and displays entries from per-program sidecar | ✓ WIRED | DiagnosisHistory.load(from:) called in init |
| ProgramOverrideSettingsView | DiagnosticsView | Diagnostics section links to full diagnostics view | ✓ WIRED | Line 53: DiagnosticsView(...) |
| Help menu | DiagnosticsView | menu command opens diagnostics with bottle/program picker | ✓ WIRED | WhiskyApp lines 135-136: "Run Diagnostics..." command, DiagnosticsPickerSheet |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| STAB-01: WINEDEBUG error patterns are parsed and classified from Wine output | ✓ SATISFIED | All supporting truths verified: 22 patterns, 7 categories, CrashClassifier pipeline |
| STAB-02: Known crash patterns are detected and matched to suggested remediation steps | ✓ SATISFIED | 9 remediations linked to patterns; RemediationCardView displays with action buttons |
| STAB-03: GPU crash pattern detection provides specific guidance for IOMFB and Metal errors | ✓ SATISFIED | 3 GPU patterns (gpu-device-lost-dxvk, gpu-metal-validation, gpu-d3d-device-hung) link to GPU remediations |
| STAB-04: Diagnostic reports include classified error summary alongside raw logs | ✓ SATISFIED | DiagnosticExporter generates report.md with summary + crash.json + wine.log in ZIP |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| WhiskyKit/Tests/WhiskyKitTests/DiagnosticExporterTests.swift | 1-491 | SwiftLint type_body_length violation (378 lines vs 350 max) | ⚠️ Warning | Build fails in CI due to SwiftLint enforcement; tests pass but file structure violates project style rules |

### Gaps Summary

**Gap 1: Localization Naming Convention**
The plan 05-05 specified using structured "diagnostics.*" prefix for all localization keys, following a dot-separated hierarchy. The implementation uses plain English strings with SwiftUI's auto-discovery mechanism instead. While this is functionally equivalent (strings are localized), it deviates from the specified naming convention.

Impact: Low - strings are localized and will be discovered by Crowdin, but lack structured namespace organization specified in plan.

**Gap 2: SwiftLint Compliance**
DiagnosticExporterTests.swift exceeds the project's 350-line body length limit by 28 lines. The file compiles and all tests pass, but the build fails in CI due to SwiftLint enforcement.

Impact: Medium - blocks CI/CD pipeline; requires either splitting test class or requesting SwiftLint exception.

---

_Verified: 2026-02-10T09:15:00Z_
_Verifier: Claude (gsd-verifier)_
