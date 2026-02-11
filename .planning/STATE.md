# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-08)

**Core value:** Every tracking issue (#40-#50) has a concrete response -- code fix, configuration UI, or in-app guidance
**Current focus:** Phase 8 in progress -- Remaining Platform Issues

## Current Position

Phase: 8 of 10 (Remaining Platform Issues) -- IN PROGRESS
Plan: 3 of 7 in current phase (plan 03 complete)
Status: Executing
Last activity: 2026-02-11 -- Completed 08-03 (Dependency Tracking Data Layer)

Progress: [▓▓▓▓▓▓▓░░░] 75%

## Performance Metrics

**Velocity:**
- Total plans completed: 32
- Average duration: 8.4min
- Total execution time: 4.7 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-miscellaneous-fixes | 3 | 17min | 5.7min |
| 02-configuration-foundation | 4 | 73min | 18.3min |
| 03-process-lifecycle-management | 3 | 18min | 6.0min |
| 04-graphics-configuration | 3 | 12min | 4.0min |
| 05-stability-diagnostics | 5 | 45min | 9.0min |
| 06-audio-troubleshooting | 5/5 | 32min | 6.4min |
| 07-game-compatibility-database | 7/7 | 64min | 9.1min |
| 08-remaining-platform-issues | 3/7 | 17min | 5.7min |

**Recent Trend:**
- Last 5 plans: 07-06 (8min), 07-07 (11min), 08-01 (--), 08-02 (8min), 08-03 (9min)
- Trend: Phase 8 progressing; dependency tracking data layer in 9min

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
- [05-05]: DiagnosisHistoryView uses optional closure callbacks for flexible embedding in different navigation contexts
- [05-05]: ConfigView diagnostics helpers extracted to extension for SwiftLint type_body_length compliance
- [05-05]: Crash banner auto-dismisses after 8s with overlay alignment + transition animation
- [05-05]: DiagnosticsPickerSheet for Help menu entry point (menu has no program context, needs selection)
- [05-05]: Plain English localization strings for diagnostics UI (matching 05-04 pattern, auto-discovered by Xcode)
- [06-01]: AudioTransportType uses String raw value for Codable, separate init(coreAudioTransportType:) for UInt32 mapping
- [06-01]: AudioDeviceHistory is a final class (@unchecked Sendable) to allow non-mutating append/clear API
- [06-01]: AudioDeviceMonitor stores listener block + address for proper removal in deinit
- [06-02]: Audio config follows BottleGraphicsConfig pattern exactly: module-scope enums, defensive decoding, private stored property with proxy properties
- [06-02]: Audio settings are registry-backed (not env vars): populateAudioLayer is a placeholder for future audio env var support
- [06-02]: RegistryType promoted to public and addRegistryKey/queryRegistryKey promoted from private to public for module-wide access
- [06-03]: WineRegistryAudioProbe uses @unchecked Sendable final class with @MainActor bridge for registry access
- [06-03]: WineAudioTestProbe uses Wine.runWineProcess streaming API for separate stdout/stderr capture
- [06-03]: AudioTroubleshootingEngine fix order is hardcoded per symptom as static dictionary (JSON migration ready)
- [06-03]: MinGW not available; WhiskyAudioTest.exe not compiled (probe returns .skipped gracefully)
- [06-04]: @State instead of @StateObject for AudioDeviceMonitor (not ObservableObject; query-only device API)
- [06-04]: AudioDeviceMonitor listener callback accepted with Sendable warning (dispatch guaranteed main-queue)
- [06-04]: Findings view reuses ConfidenceTier color scheme from Phase 5 (green/yellow/gray badges)
- [06-05]: AudioTroubleshootingEngine created on-demand when wizard opens; probes injected from AudioConfigSection
- [06-05]: Bluetooth device change debounce at 2 seconds in AudioConfigSection
- [06-05]: AudioAlertTracker uses 3-minute cooldown per device name for rate-limiting toast alerts
- [06-05]: Deep-link uses Notification.Name.openAudioTroubleshooting (matching Phase 5 pattern)
- [07-01]: EnhancedSync decoded from plain strings in JSON database with fallback to native Codable format
- [07-01]: GameConfigVariantSettings fields map 1:1 to BottleSettings property names for zero-translation apply
- [07-01]: Single snapshot file per bottle (GameConfigSnapshot.plist) for single-undo design
- [07-01]: programSettingsData keyed by String (URL string) instead of URL for Codable simplicity
- [07-07]: EnhancedSync encodes as plain strings in JSON (not keyed objects) under Swift 6 language mode
- [07-07]: 30 entries chosen for comprehensive coverage across rating tiers, stores, and backends
- [07-07]: WineD3D backend coverage via Witcher 2 entry for older DX9 game compatibility
- [07-07]: Anti-cheat categorization: kernel-level (Vanguard, EAC-kernel) as notSupported, session-level (BattlEye) as broken
- [07-02]: GameMatcher as caseless enum following GPUDetection pattern for static utility namespace
- [07-02]: bestMatch returns nil for ambiguous results (gap < 0.1) unless top is hardIdentifier tier
- [07-02]: Fuzzy score capped at 0.69 to stay below strong heuristic tier boundary
- [07-02]: Variant auto-selection prefers isDefault; soft architecture preference without strict constraint exclusion
- [07-03]: DLL override deduplication by name during apply: variant value wins over existing
- [07-03]: Full BottleSettings snapshot (not delta) for simple and reliable undo
- [07-03]: Staleness thresholds: 90 days, >1 minor macOS delta, different Wine major
- [07-03]: ConfigChange preview uses string descriptions for all value types (no generics needed)
- [07-04]: List without selection binding (GameDBEntry not Hashable); NavigationLink with value-based destination
- [07-04]: Filter bar uses safeAreaInset(edge: .top) with ScrollView for horizontal filter pickers
- [07-04]: Backend filter derived from defaultVariant.settings.graphicsBackend display name
- [07-04]: ContentUnavailableView for empty state with search-aware messaging
- [07-05]: FlowLayout custom Layout for constraint tag wrapping instead of LazyHGrid
- [07-05]: Community trust banner between At a Glance and Recommended Config for non-maintainer entries
- [07-05]: Preview sheet uses VStack+ScrollView (not Form) for finer diff layout control
- [07-05]: Winetricks verb status display-only; actual installation left to existing Winetricks UI
- [07-05]: Undo snapshot saved to bottle on apply; full undo toast deferred to future refinement
- [07-05]: SettingDisplay private struct for type-safe settings area display
- [07-06]: Localization uses .xcstrings (String Catalog) format, not .strings files -- project convention
- [07-06]: GameConfigBannerView uses sheet presentation for detail view (embeddable in non-navigation contexts)
- [07-06]: ProgramOverrideSettingsView loads game match asynchronously via .task modifier with nonisolated helper
- [07-06]: ConfigView revert calls GameConfigApplicator.revert + GameConfigSnapshot.delete directly
- [07-06]: 60 localization entries added with gameConfig.* and gamedb.* key prefixes
- [08-02]: nonisolated(unsafe) for notification observer storage in @MainActor deinit (Swift 6 compliance)
- [08-02]: useButtonLabels coexists with disableControllerMapping; either true sets SDL_GAMECONTROLLER_USE_BUTTON_LABELS=1
- [08-02]: ControllerMonitor in Whisky app target (not WhiskyKit) since GameController framework is app-level
- [Phase 08]: [08-03]: DependencyDefinition at module scope in WhiskyKit (ClipboardPolicy pattern); DependencyManager as caseless enum (GPUDetection pattern)
- [Phase 08]: [08-03]: Headless winetricks install via Process (not Terminal AppleScript) for Whisky volume access attribution
- [Phase 08]: [08-03]: Evidence-based recommendations only: ClickOnce->dotnet48, dependenciesLoading crashes->vcruntime/directx, game DB verbs->matching definitions
- [Phase 08]: FixCategory enum at module scope for shared LauncherFixDetail/MacOSFix classification
- [Phase 08]: MacOSCompatibilityFixes as caseless enum registry; fixDetails() in separate extension file for SwiftLint compliance
- [Phase 08]: EnvironmentBuilder reason storage as separate per-layer dict; WINEESYNC conditional preserved as special case

### Pending Todos

None yet.

### Blockers/Concerns

None active.

## Session Continuity

Last session: 2026-02-11
Stopped at: Completed 08-03-PLAN.md (Dependency Tracking Data Layer)
Resume file: None
