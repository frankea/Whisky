# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-08)

**Core value:** Every tracking issue (#40-#50) has a concrete response -- code fix, configuration UI, or in-app guidance
**Current focus:** Phase 10 (Guided Troubleshooting) -- session persistence and fix application complete

## Current Position

Phase: 10 of 10 (Guided Troubleshooting) -- IN PROGRESS
Plan: 5 of 7 in current phase (5 complete)
Status: Executing
Last activity: 2026-02-12 -- Plan 10-05 complete (session persistence + FixApplicator)

Progress: [▓▓▓▓▓▓▓▓▓▒] 97%

## Performance Metrics

**Velocity:**
- Total plans completed: 48
- Average duration: 8.1min
- Total execution time: 6.8 hours

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
| 08-remaining-platform-issues | 7/7 | 47min | 6.7min |
| 09-ui-ux-feature-requests | 7/7 | 54min | 7.7min |
| 10-guided-troubleshooting | 5/7 | 46min | 9.2min |

**Recent Trend:**
- Last 5 plans: 10-05 (10min), 10-04 (24min), 10-02 (8min), 10-01 (4min), 09-04 (10min)
- Trend: Phase 10 progressing; session persistence and fix applicator in 10min

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
- [08-05]: Connected Controllers subpanel collapsed by default with DisclosureGroup (per user decision)
- [08-05]: Input overrides at programUser layer: controllerCompatibilityMode gates all SDL hint overrides
- [08-05]: useButtonLabels and disableControllerMapping both control SDL_GAMECONTROLLER_USE_BUTTON_LABELS at program level
- [08-04]: ActiveEnvironmentOverrides as private struct with lock icons following DLLOverrideEditor managed pattern
- [08-04]: Diagnostics button replaced with .openDiagnosticsSection notification for deep-linking to ConfigView
- [08-04]: LauncherConfigSection body extracted into computed properties for SwiftLint type_body_length compliance
- [08-04]: file_length SwiftLint disable for LauncherConfigSection (contains section + overrides view + DiagnosticsReportView)
- [08-06]: DependencyConfigSection manages own @State (no state hoisting to ConfigView)
- [08-06]: Preflight and Plan stages merged into single stage with embedded verb plan section
- [08-06]: Install directory created under Views for DependencyInstallSheet (new Xcode group)
- [08-06]: BottleDependencyHistory populated after each install attempt for diagnostics traceability
- [08-07]: SteamDownloadMonitor in app target (not WhiskyKit) following ControllerMonitor precedent
- [08-07]: 45-second sampling interval within 30-60s range; stall threshold 3 minutes per user decision
- [08-07]: Stall notifications rate-limited once per bottle per session with suppressWarnings API
- [08-07]: Dependency badge uses .openDependenciesSection notification for ConfigView deep-link

- [09-02]: BottleDisplayConfig follows BottleGraphicsConfig/BottleAudioConfig pattern exactly: module-scope enum, defensive decoding, private stored property with proxy properties
- [09-02]: ResolutionPreset uses String raw values for stable Codable serialization
- [09-02]: effectiveResolution returns (1920,1080) fallback for matchDisplay; actual screen query deferred to app layer
- [09-02]: Virtual desktop registry helpers use Wine Explorer keys (HKCU\Software\Wine\Explorer and Explorer\Desktops)
- [09-02]: disableVirtualDesktop silently catches missing key error (expected for bottles that never had virtual desktop)
- [09-05]: Run history stored in separate .run-history.plist per program (not in ProgramSettings) to avoid bloating main settings
- [09-05]: Log file names stored as relative paths (not absolute URLs) so entries survive bottle moves
- [09-05]: RunLogStore as caseless enum following GPUDetection/DiagnosisHistory pattern for static utility namespace
- [09-05]: Auto-cleanup of log files for pruned entries during append in Wine.runProgram
- [09-05]: ProgramRunResult extended with runLogEntryId for UI correlation (backward-compatible, @discardableResult)
- [Phase 09]: RetinaModeState uses enabled/disabled/unknown (SwiftLint 3-char min); DPI sheet gets read-only Bool Binding from tri-state
- [Phase 09]: SetupView auto-navigates to download on update (!firstTime + Wine not installed) for single-step GPTK dialog
- [09-04]: Menu bar entry point skipped: no Bottle-specific menu exists; context menu + toolbar sufficient
- [09-04]: FileManager.copyItem used with phase-level progress (not file-by-file) per plan discretion clause
- [09-04]: @Sendable progress callback required for crossing actor boundary in Task.detached
- [09-04]: nonisolated static methods for calculateDirectorySize and removeTransientArtifacts in @MainActor extension
- [09-07]: Wine.runWineProcess streaming API used for --follow mode (avoids new runProgram variant)
- [09-07]: ShortcutCreator as caseless enum in WhiskyKit following GPUDetection pattern
- [09-07]: ProgramShortcut delegates bundle creation to ShortcutCreator; keeps icon extraction and Finder reveal in app target
- [09-07]: tailLogFile uses polling with 5-second idle timeout for portability
- [09-07]: swiftlint:disable file_length for Main.swift (Shortcut subcommand pushed past 400-line limit)
- [09-06]: Timer-based polling (2s history, 1s log tail) over DispatchSource for simplicity
- [09-06]: WINEDEBUG line detection via regex patterns for Wine thread IDs and debug prefixes
- [09-06]: Heuristic stderr detection via common error indicators (Wine log format does not separate stdout/stderr)
- [09-06]: Export includes labeled WINEDEBUG content when filtered out for complete capture
- [09-06]: ConsoleLogView struct + extension split for SwiftLint type_body_length compliance
- [09-03]: ResolutionConfigSection uses simple/advanced segmented control following GraphicsConfigSection pattern
- [09-03]: Registry state loaded on appear via Wine.queryVirtualDesktop and matched to closest preset
- [09-03]: Per-program virtual desktop uses Wine explorer /desktop= command-line approach (per-process, no registry mutation)
- [09-03]: Bottle-level virtual desktop uses registry approach (written once when user toggles)
- [10-02]: Shared verify_fix node per flow: single verify node reused by multiple fix branches to stay within node count limits
- [10-02]: Launcher-issues flow consolidates EA/Epic/Rockstar into shared check_launcher_env path (branch at detection, converge at env check)
- [10-02]: Shallow flows (controller-input, performance-stability) use combined escalate nodes with guidance text rather than separate info nodes
- [10-02]: Fragment node IDs usable as cross-file targets via on-map (export-escalation nodes reachable from flow files)
- [10-01]: SymptomCategory includes 9th 'other' case as fallback per locked decision guidance
- [10-01]: CheckContext stores URLs/names instead of @MainActor Bottle/Program references for Sendable compliance
- [10-01]: SessionPhase has 6 cases (adding escalation beyond 5 core FlowPhases) for post-flow state
- [10-01]: EntryContext uses URL-based associated values for Sendable conformance
- [10-03]: FlowLoader uses hardcoded fragment names due to SPM .process() directory flattening
- [10-03]: CheckRegistry init is empty; registerDefaults placeholder for Plan 04 check implementations
- [10-03]: PreflightCollector sets launcherType to nil (LauncherDetection in app target, not WhiskyKit)
- [10-03]: TroubleshootingFlowEngine imports Combine (not SwiftUI) for @Published in WhiskyKit
- [10-03]: PreflightCollector uses RunLogStore for recent log/exit code lookup
- [10-04]: RegistryValueCheck parses .reg files directly (avoids @MainActor Bottle dependency for registry reads)
- [10-04]: SettingValueCheck uses switch-based property name dispatch for type-safe settings access
- [10-04]: AudioTestCheck returns .unknown gracefully (MinGW test exe not compiled, expected condition)
- [10-04]: CheckRegistry.init() auto-registers all 15 defaults; NSLock.withLock for Swift 6 async safety
- [10-05]: StalenessChange uses >50% or >5 delta threshold for process count significance
- [10-05]: Audio driver and buffer size fixes return .pending (registry writes are async)
- [10-05]: FixApplicator delegates winetricks/dependency to existing infrastructure with .pending result
- [10-05]: TroubleshootingHistory.save() is non-throwing; logs errors internally for simpler call sites

### Pending Todos

None yet.

### Blockers/Concerns

None active.

## Session Continuity

Last session: 2026-02-12
Stopped at: Completed 10-05-PLAN.md
Resume file: None
