# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-08)

**Core value:** Every tracking issue (#40-#50) has a concrete response -- code fix, configuration UI, or in-app guidance
**Current focus:** Phase 5 in progress -- Stability & Diagnostics

## Current Position

Phase: 5 of 10 (Stability & Diagnostics)
Plan: 4 of 5 in current phase (05-04 complete)
Status: In Progress
Last activity: 2026-02-10 -- Completed 05-04-PLAN.md (Diagnostics UI)

Progress: [▓▓▓▓▓░░░░░] 46%

## Performance Metrics

**Velocity:**
- Total plans completed: 17
- Average duration: 9.2min
- Total execution time: 2.52 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-miscellaneous-fixes | 3 | 17min | 5.7min |
| 02-configuration-foundation | 4 | 73min | 18.3min |
| 03-process-lifecycle-management | 3 | 18min | 6.0min |
| 04-graphics-configuration | 3 | 12min | 4.0min |
| 05-stability-diagnostics | 4 | 31min | 7.8min |

**Recent Trend:**
- Last 5 plans: 04-03 (3min), 05-01 (7min), 05-02 (6min), 05-03 (9min), 05-04 (9min)
- Trend: UI plans consistent ~9min; NSViewRepresentable complexity handled within budget

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 10 phases derived from 54 requirements at comprehensive depth
- [Roadmap]: Phase 1 closes out existing PR #79 before starting new work
- [Roadmap]: EnvironmentBuilder refactor (Phase 2) is the foundation; graphics/audio/game phases depend on it
- [Roadmap]: Phases 3-4 are parallel-capable after foundation; Phases 5-6 are parallel-capable
- [01-01]: ClipboardPolicy/ClipboardCheckResult defined at module scope for easier import
- [01-01]: Structured result pattern: WhiskyKit returns result enums, app layer presents UI
- [01-01]: BottleCleanupConfig follows existing config section pattern (private stored, proxy properties)
- [01-02]: ClickOnce badge uses else-if after PE arch badge (mutually exclusive)
- [01-02]: Rescan button in toolbar for discoverability
- [01-02]: ClickOnce context menu in separate Section from standard actions
- [01-03]: Clipboard check called from app layer (ProgramItemView) rather than inside WhiskyKit's launchWithUserMode
- [01-03]: Startup zombie process sweep deferred to Phase 3 (ProcessRegistry is session-based)
- [01-03]: CleanupConfigSection extracted to own file for SwiftLint type_body_length compliance
- [02-01]: EnvironmentBuilder uses [String: String?] per layer to support explicit key removal via nil
- [02-01]: DLLOverrideResolver.managed uses tuple array (entry, source) instead of separate dictionaries
- [02-01]: displayName on DLLOverrideMode uses plain strings (localization deferred to UI phase)
- [02-01]: Added Sendable to EnhancedSync and DXVKHUD enums for ProgramOverrides compatibility
- [02-03]: Verb discovery methods placed in separate extension file for SwiftLint length compliance
- [02-03]: MainActor.run used to safely read bottle.url from non-isolated async contexts
- [02-03]: Both prefix root and drive_c checked for winetricks.log location
- [02-02]: Kept environmentVariables(wineEnv:) as deprecated wrapper for backward compatibility
- [02-02]: DLLOverrideResolver produces per-DLL alphabetically sorted format (valid Wine syntax)
- [02-02]: Extracted isValidEnvKey to extension to satisfy SwiftLint type_body_length
- [02-02]: ProgramOverrides passed through Wine.runProgram rather than changing generateEnvironment return type
- [02-04]: Inherit/override toggle uses nil-check on grouped fields (no separate boolean tracking)
- [02-04]: Copy-on-enable copies current bottle values when switching from inherit to override
- [02-04]: taggedVerbs excluded from ProgramOverrides.isEmpty (organizational metadata, not settings override)
- [02-04]: Advanced raw WINEDLLOVERRIDES escape hatch deferred per discretion clause
- [03-01]: ProcessKind.classify uses static Set<String> lookup for O(1) classification
- [03-01]: parseTasklistOutput is a pure non-MainActor function for testability
- [03-01]: clearRegistry made public for ViewModel shutdown cleanup
- [03-02]: ProcessRegistry.shared made public for app target access
- [03-02]: RunningProcessesView split into struct + 2 extensions for SwiftLint type_body_length
- [03-02]: contextMenu(forSelectionType: Int32.self) for Table row context menus
- [03-02]: Text(date, style: .relative) for automatic launch time display
- [03-02]: Shutdown refresh uses temporary state bypass to reuse refreshProcessList
- [03-03]: Close confirmation dialog in ContentView (not BottleView) due to SwiftUI onDisappear lifecycle
- [03-03]: NSAlert with checkbox for remember-choice UX (matching existing showRemoveAlert pattern)
- [03-03]: sweepOrphanProcesses extracted to @MainActor method (Swift 6 region-based isolation workaround)
- [03-03]: showProcessCloseAlert in ContentView extension for SwiftLint type_body_length
- [Phase 04]: [04-01]: GraphicsBackend at module scope (ClipboardPolicy pattern), resolver as caseless enum (GPUDetection pattern)
- [Phase 04]: [04-01]: dxvk proxy derives from graphicsConfig.backend; DXVK_ASYNC only emitted for .dxvk backend
- [Phase 04]: [04-01]: Decode-time migration for old bottles: container.contains(.graphicsConfig) + dxvk=true -> backend=.dxvk
- [Phase 04]: [04-02]: Selection cards use custom Button + BackendCard (not standard Picker) for richer layout
- [Phase 04]: [04-02]: Metal settings inlined into GraphicsConfigSection Advanced mode (not separate view)
- [Phase 04]: [04-02]: hasAdvancedSettingsConfigured uses inverted default (!dxvkAsync) due to BottleDXVKConfig internal access
- [Phase 04]: [04-03]: graphicsBackend replaces dxvk as sentinel for graphics override group
- [Phase 04]: [04-03]: Standalone DXVK toggle removed from per-program override controls (backend picker implies DXVK active)
- [Phase 04]: [04-03]: computedManagedOverrides checks graphicsBackend == .dxvk instead of bottle.settings.dxvk
- [05-01]: nonisolated(unsafe) for Regex storage in CrashPattern (Swift 6 Sendable compliance)
- [05-01]: SPM .process() flattens resource directories; PatternLoader loads without subdirectory path
- [05-01]: Added otherUnknown pattern (wine-nonzero-exit) to ensure all 7 categories have coverage
- [05-01]: WineDebugPreset uses presetDescription property name to avoid shadowing CustomStringConvertible
- [05-02]: CrashDiagnosisCodableWrapper encodes only serializable portions of CrashDiagnosis for JSON export
- [05-02]: Redactor uses FileManager.default.homeDirectoryForCurrentUser for runtime home path detection
- [05-02]: DiagnosticExporter captures MainActor-isolated values before Task.detached for file I/O
- [05-02]: ExportOptions at module scope (not nested in DiagnosticExporter) for cleaner API surface
- [05-03]: ProgramRunResult @discardableResult return from runProgram for backward compatibility
- [05-03]: Crash signature heuristic Set<String> pre-check before running full classifier pipeline
- [05-03]: makeFileHandleWithURL() alongside existing makeFileHandle() for log URL tracking
- [05-03]: Notification.Name.crashDiagnosisAvailable carries diagnosis, programPath, logFileURL in userInfo
- [05-03]: DiagnosisHistory sidecar stored as programName.diagnosis-history.plist in Program Settings directory
- [05-04]: GeometryReader with 700pt threshold for responsive split vs vertical layout
- [05-04]: Unicode filled circle gutter markers instead of NSRulerView for simplicity
- [05-04]: NSTextStorage batch editing (beginEditing/endEditing) for attributed string updates
- [05-04]: Filter-driven full line rebuild on filter/search change for NSTextView correctness
- [05-04]: Low-confidence remediations hidden behind "Other things to try" collapsed DisclosureGroup

### Pending Todos

None yet.

### Blockers/Concerns

None active.

## Session Continuity

Last session: 2026-02-10
Stopped at: Completed 05-04-PLAN.md (Diagnostics UI)
Resume file: None
