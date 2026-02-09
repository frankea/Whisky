# Architecture Research

**Domain:** Wine bottle management macOS app -- per-game config, compatibility database, troubleshooting, process lifecycle
**Researched:** 2026-02-08
**Confidence:** HIGH (based on deep reading of existing codebase, established Wine ecosystem patterns, and competitor analysis)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Presentation Layer (SwiftUI)                        │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │ConfigView│  │CompatibilityV│  │TroubleshootView│  │RunningProcessV  │  │
│  └────┬─────┘  └──────┬───────┘  └───────┬────────┘  └───────┬─────────┘  │
│       │               │                  │                    │            │
├───────┴───────────────┴──────────────────┴────────────────────┴────────────┤
│                     State Management (BottleVM)                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ BottleVM.shared (@MainActor singleton, @Published bottles array)   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
├───────────────────────────────────────────────────────────────────────────┤
│                     Domain Layer (WhiskyKit)                               │
│  ┌───────────────┐  ┌──────────────────┐  ┌───────────────────────────┐   │
│  │ Configuration  │  │  Compatibility   │  │    Troubleshooting       │   │
│  │ Cascade        │  │  Database        │  │    Engine                │   │
│  │                │  │                  │  │                          │   │
│  │ Bottle         │  │ GameProfile      │  │ TroubleshootingGuide    │   │
│  │ → Program      │  │ CompatReport     │  │ SymptomMatcher          │   │
│  │ → GameProfile  │  │ CompatStore      │  │ DiagnosticCollector     │   │
│  └───────┬───────┘  └────────┬─────────┘  └───────────┬─────────────┘   │
│          │                   │                         │                  │
├──────────┴───────────────────┴─────────────────────────┴──────────────────┤
│                     Execution Layer                                        │
│  ┌───────────────────────────┐  ┌─────────────────────────────────────┐   │
│  │ Wine (static execution)   │  │ ProcessLifecycleManager             │   │
│  │ WineEnvironment            │  │ ProcessRegistry (enhanced)         │   │
│  │ LauncherPresets            │  │ WineServerMonitor                  │   │
│  └───────────────────────────┘  └─────────────────────────────────────┘   │
├───────────────────────────────────────────────────────────────────────────┤
│                     Persistence Layer                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ Plist    │  │ Plist    │  │ JSON Bundle      │  │ JSON AppSupport  │  │
│  │ Bottle   │  │ Program  │  │ (Compat DB)      │  │ (User Reports)   │  │
│  └──────────┘  └──────────┘  └──────────────────┘  └──────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| **Configuration Cascade** | Merge Wine defaults → macOS fixes → bottle settings → game profile → program settings → user overrides into final environment | Wine execution, BottleSettings, ProgramSettings, GameProfile |
| **GameProfile** | Store per-game configuration templates: env vars, DLL overrides, winetricks verbs, performance preset | Configuration Cascade, CompatibilityDatabase |
| **CompatibilityDatabase** | Match executables to known-working configurations, store local + community compatibility reports | GameProfile, CompatibilityView, BottleVM |
| **TroubleshootingEngine** | Map symptoms to solutions, collect diagnostics, suggest configuration changes | DiagnosticCollector, WinePrefixValidation, BottleSettings |
| **ProcessLifecycleManager** | Monitor wineserver + child processes, detect orphans, handle graceful/force shutdown, health checks | ProcessRegistry, Wine execution, BottleVM |
| **BottleVM** | Coordinate UI state, bottle CRUD, process launch flow | All components via @MainActor |

## Recommended Project Structure

### New Modules in WhiskyKit

```
WhiskyKit/Sources/WhiskyKit/
├── Whisky/                          # Existing: Domain models
│   ├── Bottle.swift                 # Existing
│   ├── Program.swift                # Existing
│   ├── ProgramSettings.swift        # Extended: DLL overrides, winetricks verbs
│   ├── BottleSettings.swift         # Existing (cascade point)
│   └── GameProfile.swift            # NEW: Per-game configuration template
│
├── Wine/                            # Existing: Execution layer
│   ├── Wine.swift                   # Existing
│   ├── WineEnvironment.swift        # Extended: GameProfile integration
│   └── WinetricksRunner.swift       # NEW: Programmatic winetricks execution
│
├── Compatibility/                   # NEW: Game compatibility module
│   ├── CompatibilityDatabase.swift  # Local + community compat data
│   ├── CompatibilityReport.swift    # User-submitted compatibility rating
│   ├── GameMatcher.swift            # Match exe to known game profiles
│   └── CompatibilityStore.swift     # Persistence (JSON in app bundle + user dir)
│
├── Troubleshooting/                 # NEW: Troubleshooting module
│   ├── TroubleshootingGuide.swift   # Symptom → solution mapping
│   ├── SymptomMatcher.swift         # Pattern matching on logs/errors
│   ├── DiagnosticCollector.swift    # Gather system/bottle/wine state
│   └── TroubleshootingStep.swift    # Individual troubleshooting action
│
├── ProcessLifecycle/                # NEW: Enhanced process management
│   ├── ProcessLifecycleManager.swift# Orchestrates process tracking + cleanup
│   ├── WineServerMonitor.swift      # Monitor wineserver health per bottle
│   └── OrphanDetector.swift         # Find wine processes without parents
│
└── Utils/                           # Existing
    ├── ProcessRegistry.swift        # Existing (enhanced)
    └── ...
```

### New Views in Whisky App

```
Whisky/Views/
├── Bottle/
│   ├── ConfigView.swift             # Existing (extended)
│   └── GameProfileView.swift        # NEW: Per-game config editor
│
├── Compatibility/                   # NEW: Compatibility views
│   ├── CompatibilityView.swift      # Game compatibility browser
│   ├── CompatReportView.swift       # Submit/view compatibility report
│   └── GameSearchView.swift         # Search games in database
│
├── Troubleshooting/                 # NEW: Troubleshooting views
│   ├── TroubleshootingView.swift    # Guided troubleshooting flow
│   ├── DiagnosticsView.swift        # System diagnostics display
│   └── LogAnalysisView.swift        # Log viewer with pattern highlighting
│
└── Programs/
    ├── ProgramView.swift            # Existing (extended with game profile)
    └── EnvironmentArgView.swift     # Existing (extended with DLL overrides)
```

### Structure Rationale

- **Compatibility/ in WhiskyKit:** Game compatibility data is domain logic, not UI. WhiskyKit is published separately; other tools (WhiskyCmd, third-party) should access compat data.
- **Troubleshooting/ in WhiskyKit:** Diagnostic collection and symptom matching are reusable. The CLI could also run diagnostics.
- **ProcessLifecycle/ in WhiskyKit:** Process management is core execution concern, not app-specific. Separated from Wine/ because Wine.swift (30KB) is already too large.
- **GameProfile in Whisky/ module:** GameProfile is a domain model like Program. It belongs alongside Bottle and Program.

## Architectural Patterns

### Pattern 1: Extended Configuration Cascade

**What:** Extend the existing four-level configuration cascade to include a GameProfile layer between bottle settings and program settings.

**When to use:** Every program launch. The cascade already exists; this adds one more layer.

**Trade-offs:**
- Pro: Consistent with existing architecture. Users get per-game profiles that override bottle defaults but can still be overridden per-program.
- Pro: GameProfile can be shared across bottles (same game, different Wine versions).
- Con: More layers means more complexity in debugging "where did this env var come from?"
- Mitigation: Add a `describeEnvironmentSources()` debug method that logs each layer's contributions.

**Current cascade (from WineEnvironment.swift + BottleSettings.environmentVariables):**
```
Wine defaults (WINEPREFIX, WINEDEBUG, GST_DEBUG)
    ↓
macOS compatibility fixes (MacOSCompatibility.applyMacOSCompatibilityFixes)
    ↓
Bottle settings (BottleSettings.environmentVariables)
    ↓
Program settings (Program.generateEnvironment)
    ↓
User-provided overrides (constructWineEnvironment environment: parameter)
```

**Extended cascade:**
```
Wine defaults (WINEPREFIX, WINEDEBUG, GST_DEBUG)
    ↓
macOS compatibility fixes (MacOSCompatibility.applyMacOSCompatibilityFixes)
    ↓
Bottle settings (BottleSettings.environmentVariables)
    ↓
Game profile overrides (GameProfile.environmentOverrides)       ← NEW
    ↓
Program settings (Program.generateEnvironment)
    ↓
User-provided overrides (constructWineEnvironment environment: parameter)
```

**Example:**
```swift
// In WineEnvironment.swift (extended)
@MainActor
public static func constructWineEnvironment(
    for bottle: Bottle,
    program: Program? = nil,
    environment: [String: String] = [:]
) -> [String: String] {
    var result: [String: String] = [
        "WINEPREFIX": bottle.url.path,
        "WINEDEBUG": "fixme-all",
        "GST_DEBUG": "1"
    ]

    applyMacOSCompatibilityFixes(to: &result)
    bottle.settings.environmentVariables(wineEnv: &result)

    // NEW: Apply game profile if matched
    if let program,
       let profile = CompatibilityDatabase.shared.matchProfile(for: program) {
        profile.applyEnvironmentOverrides(to: &result)
    }

    // Existing: program-level overrides
    if let program {
        let programEnv = program.generateEnvironment()
        for (key, value) in programEnv where isValidEnvKey(key) {
            result[key] = value
        }
    }

    // Existing: user-provided overrides
    for (key, value) in environment where isValidEnvKey(key) {
        result[key] = value
    }

    return result
}
```

### Pattern 2: Bundled + User Compatibility Data

**What:** Ship a curated JSON compatibility database in the app bundle. Users can add local reports. Optionally sync community data via a lightweight API.

**When to use:** Game matching, "apply recommended settings", compatibility browsing.

**Trade-offs:**
- Pro: Works offline. No server dependency for core functionality.
- Pro: App bundle data is curated and reliable. User data augments it.
- Con: Bundled data becomes stale between app updates.
- Mitigation: Version the database format. Support incremental updates via a CDN-hosted JSON diff (future).
- Con: Community sync requires server infrastructure.
- Mitigation: Phase community features later. Start with bundled + local only.

**Data model:**
```swift
/// A known game with recommended configuration
public struct GameProfile: Codable, Identifiable, Sendable {
    public let id: String                           // Unique identifier (e.g., "steam-1234567")
    public var displayName: String                  // "Elden Ring"
    public var matchPatterns: [GameMatchPattern]     // How to identify this game
    public var recommendedSettings: GameSettings     // Env vars, DLL overrides, winetricks
    public var compatibilityRating: CompatRating?   // Platinum/Gold/Silver/Bronze/Borked
    public var notes: String?                       // User-facing tips
    public var lastUpdated: Date
}

public struct GameMatchPattern: Codable, Sendable {
    public var executableName: String?      // "eldenring.exe"
    public var steamAppID: String?          // "1245620"
    public var pathContains: String?        // "ELDEN RING"
}

public struct GameSettings: Codable, Sendable {
    public var environmentOverrides: [String: String]  // Extra env vars
    public var dllOverrides: [String: DLLOverrideMode] // e.g., "d3d11": .native
    public var winetricksVerbs: [String]               // ["vcrun2019", "dotnet48"]
    public var performancePreset: PerformancePreset?
    public var windowsVersion: WinVersion?
    public var dxvkEnabled: Bool?
    public var enhancedSync: EnhancedSync?
    public var additionalArguments: String?
}

public enum DLLOverrideMode: String, Codable, Sendable {
    case native = "n"
    case builtin = "b"
    case nativeBuiltin = "n,b"
    case builtinNative = "b,n"
    case disabled = ""
}

public enum CompatRating: String, Codable, CaseIterable, Sendable {
    case platinum   // Runs perfectly out of the box
    case gold       // Runs with minor tweaks
    case silver     // Runs with configuration
    case bronze     // Runs but with issues
    case borked     // Does not run
}
```

### Pattern 3: Symptom-Driven Troubleshooting

**What:** A structured troubleshooting system that maps observable symptoms (black screen, crash on launch, no sound) to diagnostic checks and solutions. Each symptom has a decision tree of checks.

**When to use:** When users encounter problems running games. Presented as an in-app guide.

**Trade-offs:**
- Pro: Reduces support burden. Users can self-diagnose common issues.
- Pro: Decision tree structure is maintainable and extensible.
- Con: Can become stale as Wine/macOS evolve.
- Mitigation: Version the troubleshooting database. Reference GitHub issue numbers for traceability.
- Con: Complex symptoms may not fit a tree structure.
- Mitigation: Fallback to "collect diagnostics and report" for unmatched symptoms.

**Data model:**
```swift
public struct TroubleshootingGuide: Codable, Sendable {
    public let symptoms: [Symptom]
}

public struct Symptom: Codable, Identifiable, Sendable {
    public let id: String
    public var displayName: String           // "Black screen on launch"
    public var description: String           // "Game window appears but shows only black"
    public var category: SymptomCategory     // .graphics, .audio, .crash, .performance
    public var steps: [TroubleshootingStep]  // Ordered checks to perform
    public var relatedIssues: [String]       // GitHub issue references
}

public enum SymptomCategory: String, Codable, CaseIterable, Sendable {
    case crash
    case graphics
    case audio
    case performance
    case input
    case launcher
    case installation
    case network
}

public struct TroubleshootingStep: Codable, Identifiable, Sendable {
    public let id: String
    public var title: String                  // "Enable DXVK"
    public var explanation: String            // "DXVK translates DirectX to Vulkan..."
    public var checkType: CheckType           // .settingCheck, .fileCheck, .logCheck
    public var autoCheck: AutoCheck?          // Automated diagnostic check
    public var resolution: Resolution         // What to do
    public var ifUnresolved: String?          // ID of next step to try
}

public enum CheckType: String, Codable, Sendable {
    case settingCheck    // Check a bottle/program setting value
    case fileCheck       // Check if a file exists
    case logCheck        // Search logs for pattern
    case processCheck    // Check if process is running
    case systemCheck     // Check macOS/hardware state
}

public struct AutoCheck: Codable, Sendable {
    public var settingPath: String?    // "bottle.settings.dxvk"
    public var expectedValue: String?  // "true"
    public var fileExists: String?     // Relative path in bottle
    public var logPattern: String?     // Regex to search in logs
}

public struct Resolution: Codable, Sendable {
    public var description: String     // "Enable DXVK in bottle settings"
    public var settingChange: SettingChange?
    public var manualAction: String?   // Instructions for manual fix
}
```

### Pattern 4: Wineserver-Aware Process Lifecycle

**What:** Extend ProcessRegistry to track wineserver processes per bottle (not just individual wine processes). Wineserver is the true parent of all Wine processes in a bottle; monitoring it gives accurate bottle-level lifecycle awareness.

**When to use:** App termination cleanup, bottle status display, orphan detection.

**Trade-offs:**
- Pro: Wineserver dying means all processes in that bottle are dead. More reliable than tracking individual PIDs.
- Pro: `wineserver -k` is the correct way to shut down a bottle; aligns with Wine best practices.
- Con: Wineserver PID must be discovered (it's not directly launched by Whisky).
- Mitigation: Use `pgrep -f "wineserver.*WINEPREFIX"` or parse wineserver socket path.

**Enhancement to existing ProcessRegistry:**
```swift
// In ProcessLifecycleManager.swift (orchestrator)
public final class ProcessLifecycleManager {
    public static let shared = ProcessLifecycleManager()

    private let registry = ProcessRegistry.shared
    private let serverMonitor = WineServerMonitor()

    /// Launch a program with full lifecycle tracking
    @MainActor
    public func launchProgram(
        _ program: Program, in bottle: Bottle
    ) async throws {
        // 1. Register intent in ProcessRegistry
        // 2. Call Wine.runProgram (existing)
        // 3. Start wineserver monitoring for this bottle
        // 4. Set up termination handler
    }

    /// Graceful shutdown of a bottle's processes
    @MainActor
    public func shutdownBottle(_ bottle: Bottle, force: Bool) async {
        // 1. Try wineserver -k (graceful Wine shutdown)
        // 2. Wait with timeout
        // 3. If force, SIGKILL wineserver
        // 4. Detect and clean orphan wine processes
        // 5. Unregister all from ProcessRegistry
    }

    /// Periodic health check for all bottles
    public func healthCheck() async -> [URL: BottleHealthStatus] {
        // For each bottle with registered processes:
        // 1. Check if wineserver is still alive
        // 2. Check if registered PIDs are still alive
        // 3. Detect zombie/orphan processes
        // 4. Return status per bottle
    }
}

// In WineServerMonitor.swift
public final class WineServerMonitor {
    /// Discovers the wineserver PID for a bottle
    public func discoverWineServer(for bottle: Bottle) -> Int32? {
        // Parse /tmp/.wine-{uid}/server-{device}-{inode}/lock
        // or use pgrep with WINEPREFIX filter
    }

    /// Monitors wineserver for a bottle, calling handler on exit
    public func monitor(
        bottle: Bottle, onExit: @escaping () -> Void
    ) { ... }
}
```

## Data Flow

### Program Launch Flow (Extended)

```
User clicks "Run" on a Program
    ↓
BottleVM / ProgramView
    ↓
ProcessLifecycleManager.launchProgram(program, bottle)
    ↓
┌── GameMatcher.matchProfile(for: program) ──────────────┐
│   Checks: executable name, Steam ID, path patterns      │
│   Returns: Optional<GameProfile>                         │
└──────────────────────────────────────────────────────────┘
    ↓
┌── Wine.constructWineEnvironment(bottle, program) ────────┐
│   1. Wine defaults (WINEPREFIX, WINEDEBUG)               │
│   2. macOS compat fixes                                   │
│   3. bottle.settings.environmentVariables()               │
│   4. gameProfile.applyEnvironmentOverrides()    ← NEW     │
│   5. program.generateEnvironment()                        │
│   6. user overrides                                       │
│   Result: merged [String: String]                         │
└──────────────────────────────────────────────────────────┘
    ↓
┌── DLL Override Application ──────────────────────────────┐
│   gameProfile.dllOverrides + program.dllOverrides         │
│   → merged into WINEDLLOVERRIDES env var                  │
│   → DXVK DLL installation if needed                      │
└──────────────────────────────────────────────────────────┘
    ↓
ProcessRegistry.register(process, bottle, programName)
    ↓
Wine.runProgram(at:, args:, bottle:, environment:)
    ↓
AsyncStream<ProcessOutput> consumed by UI
    ↓
WineServerMonitor starts tracking bottle's wineserver
    ↓
On exit: ProcessRegistry.unregister, health check
```

### Compatibility Database Flow

```
┌── App Bundle ───────────────────────┐
│ compatibility-db.json               │
│ (curated, ships with app)           │
└──────────────┬──────────────────────┘
               │
               ↓ loaded at startup
┌── CompatibilityDatabase (in-memory) ┐
│ profiles: [GameProfile]              │
│ index: [execName: [GameProfile]]     │
│ index: [steamID: GameProfile]        │
└───────┬──────────────┬──────────────┘
        │              │
   ┌────┘              └────┐
   ↓                        ↓
GameMatcher             CompatibilityView
(automatic matching     (user browsing,
 on program launch)      searching)
        │                        │
        ↓                        ↓
Apply recommended          User submits
settings to program        compat report
                                │
                                ↓
                    ┌── User Reports Dir ──────┐
                    │ ~/Library/App Support/    │
                    │   Whisky/CompatReports/   │
                    │   {gameID}.json           │
                    └──────────────────────────┘
```

### Troubleshooting Flow

```
User opens Troubleshooting view
    ↓
Select symptom category (graphics, crash, audio, etc.)
    ↓
Select specific symptom ("Black screen on launch")
    ↓
TroubleshootingEngine loads steps for symptom
    ↓
For each step:
┌───────────────────────────────────────────────────────┐
│ 1. Display explanation to user                         │
│ 2. Run autoCheck (if available):                       │
│    - settingCheck → read bottle.settings.dxvk          │
│    - fileCheck → check file existence in bottle        │
│    - logCheck → scan recent log for pattern            │
│    - processCheck → check if wineserver alive          │
│ 3. Display result: "DXVK is disabled"                  │
│ 4. Offer resolution: "Enable DXVK" [Apply] button     │
│ 5. If unresolved → next step                           │
└───────────────────────────────────────────────────────┘
    ↓
If all steps exhausted:
    Collect full diagnostics (DiagnosticCollector)
    Offer "Copy to clipboard" for GitHub issue
```

### State Persistence

```
Existing (unchanged):
  Bottle.settings → Metadata.plist (in bottle dir)
  Program.settings → Program Settings/{name}.plist (in bottle dir)

New:
  GameProfile (bundled) → WhiskyKit/Resources/compatibility-db.json
  GameProfile (user) → ~/Library/App Support/Whisky/GameProfiles/{id}.json
  CompatReport (user) → ~/Library/App Support/Whisky/CompatReports/{id}.json
  TroubleshootingGuide → WhiskyKit/Resources/troubleshooting-guide.json
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0-500 games in DB | Bundled JSON, in-memory index, linear scan is fast enough |
| 500-5000 games | Add SQLite for compat DB (local only), keep JSON for bundled seed data |
| Community sync | CDN-hosted JSON diffs, append-only user reports uploaded to API |

### Scaling Priorities

1. **First bottleneck:** Compatibility database size. If the bundled JSON exceeds ~1MB, switch to SQLite with FTS5 for search. This is a local-only concern and does not affect architecture.
2. **Second bottleneck:** Community sync volume. Start with one-way "upload report" (fire-and-forget POST). Community browsing can be a web view to ProtonDB or a simple API. No need for full sync protocol initially.
3. **Third bottleneck:** Process monitoring overhead. WineServerMonitor polling should be infrequent (every 5 seconds). Use dispatch sources on wineserver socket file for zero-overhead exit detection.

## Anti-Patterns

### Anti-Pattern 1: Merging GameProfile into ProgramSettings

**What people do:** Store game-specific recommended settings inside each Program's ProgramSettings plist, mixing user overrides with recommended defaults.

**Why it's wrong:** ProgramSettings is per-program-per-bottle. If a user has the same game in two bottles, settings don't transfer. If the compatibility database updates, there's no way to know which ProgramSettings values came from the database vs. user customization.

**Do this instead:** Keep GameProfile separate from ProgramSettings. GameProfile is a *recommendation template* that can be applied to any program. ProgramSettings is the user's *actual configuration*. The cascade applies GameProfile first, then ProgramSettings overrides it. Track a `appliedProfileID` in ProgramSettings so the UI can show "based on Elden Ring profile, with your modifications."

### Anti-Pattern 2: Real-Time Community Database Sync

**What people do:** Build a full client-server sync protocol from day one with conflict resolution, offline queuing, and real-time updates.

**Why it's wrong:** Premature complexity. The app doesn't have a server infrastructure. Building sync before validating the data model wastes effort and creates maintenance burden.

**Do this instead:** Phase the community features:
1. **Phase 1:** Bundled JSON + local-only user data (no network)
2. **Phase 2:** One-way upload of compatibility reports (simple POST to API)
3. **Phase 3:** Periodic download of community-curated profiles (CDN JSON)
4. **Phase 4:** Full bidirectional sync (only if user demand warrants it)

### Anti-Pattern 3: Tracking Wine Processes by PID Only

**What people do:** Store PIDs at launch time and assume they're valid later for cleanup.

**Why it's wrong:** PIDs can be reused by the OS. Wine child processes reparent to wineserver (not to the Whisky process). Zombie processes from Wine's fork model make PID tracking unreliable.

**Do this instead:** The existing ProcessRegistry already uses ObjectIdentifier(Process) as the primary key, which is good. Enhance it by also monitoring the wineserver process per bottle. When wineserver exits, mark all processes in that bottle as dead. For orphan detection, scan for wine processes whose WINEPREFIX matches a known bottle but aren't in the registry.

### Anti-Pattern 4: Monolithic Troubleshooting Guide in Code

**What people do:** Hardcode all troubleshooting logic in Swift with if/else chains and string comparisons.

**Why it's wrong:** Troubleshooting steps change frequently as Wine/macOS evolve. Embedding them in code requires app updates for every new workaround. Non-developers can't contribute.

**Do this instead:** Store the troubleshooting guide as structured JSON data (bundled in the app). The TroubleshootingEngine interprets the JSON at runtime. AutoCheck provides automated diagnostics, but the decision tree itself is data-driven. This allows:
- Updating guides without code changes
- Community contribution via pull requests to the JSON file
- A/B testing different troubleshooting flows

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| BottleVM ↔ CompatibilityDatabase | Direct method call (both @MainActor) | CompatibilityDatabase.shared singleton, loaded at app launch |
| Wine.constructWineEnvironment ↔ GameProfile | Parameter passing (GameProfile passed as optional) | Backward compatible: existing calls without program/profile still work |
| ProcessLifecycleManager ↔ ProcessRegistry | Direct method call (ProcessRegistry is internal dependency) | ProcessLifecycleManager wraps ProcessRegistry; UI should use manager, not registry directly |
| TroubleshootingEngine ↔ BottleSettings | Read-only inspection of settings for autoCheck | Engine never modifies settings directly; resolutions return SettingChange values that UI applies |
| ProgramSettings ↔ GameProfile | ProgramSettings stores `appliedProfileID: String?` | Tracks which profile was applied; used for "reset to recommended" |
| WinetricksRunner ↔ Wine | Delegates to Wine.runWineProcess for execution | Wraps winetricks verb execution with prefix validation (WinePrefixValidation) first |

### External Services (Future)

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| ProtonDB API | HTTP GET via URLSession, cache locally | Read-only. Use community API (protondb.max-p.me). Cache aggressively. |
| Whisky Compat API (future) | HTTP POST for report upload, GET for community data | Build when user base warrants. Start with GitHub-hosted JSON. |
| SteamDB / IGDB | HTTP GET for game metadata (names, IDs, icons) | For enriching compatibility database entries. Optional enhancement. |

## Build Order Implications

Components have clear dependency ordering that should inform the roadmap:

```
                    ┌──────────────────────┐
                    │ 1. ProgramSettings   │
                    │    extensions         │
                    │    (DLL overrides,    │
                    │     winetricks verbs) │
                    └──────────┬───────────┘
                               │
              ┌────────────────┼────────────────┐
              ↓                ↓                 ↓
┌─────────────────┐ ┌──────────────────┐ ┌────────────────────┐
│ 2a. GameProfile │ │ 2b. Process      │ │ 2c. Winetricks     │
│     model       │ │ Lifecycle        │ │     Runner         │
│     + matcher   │ │ Manager          │ │     (wraps Wine)   │
└────────┬────────┘ └──────────────────┘ └────────────────────┘
         │
         ↓
┌──────────────────────┐
│ 3. Compatibility     │
│    Database          │
│    (bundled JSON)    │
└──────────┬───────────┘
           │
    ┌──────┴──────┐
    ↓             ↓
┌──────────┐ ┌──────────────────┐
│ 4a. Compat│ │ 4b. Extended     │
│ UI views  │ │ Config Cascade   │
│           │ │ (integrate       │
│           │ │  GameProfile)    │
└──────────┘ └──────────────────┘
                    │
                    ↓
         ┌──────────────────┐
         │ 5. Troubleshooting│
         │    Engine + UI    │
         │    (uses all      │
         │     above)        │
         └──────────────────┘
                    │
                    ↓
         ┌──────────────────┐
         │ 6. Community      │
         │    features       │
         │    (optional,     │
         │     network)      │
         └──────────────────┘
```

**Dependency rationale:**
- **Step 1 first:** ProgramSettings extensions are the lowest-risk, highest-value change. Adding DLL override fields and winetricks verb tracking requires no new modules -- just extending existing Codable structs.
- **Steps 2a-2c parallel:** GameProfile model, ProcessLifecycleManager, and WinetricksRunner are independent of each other. All depend on Step 1 being done but not on each other.
- **Step 3 after 2a:** CompatibilityDatabase stores GameProfiles. The model must exist first.
- **Steps 4a-4b parallel:** Compat UI and cascade integration both depend on the database but not each other.
- **Step 5 after 4:** Troubleshooting references settings, profiles, and process state. It's the integration point that ties everything together.
- **Step 6 last:** Network features are optional and require server infrastructure. Defer until local features prove the data model.

## Sources

- Existing codebase analysis: `WhiskyKit/Sources/WhiskyKit/` (all modules read and analyzed)
- [ProtonDB Community API](https://github.com/Trsnaqe/protondb-community-api) -- Data model reference for compatibility ratings
- [WineHQ AppDB](https://appdb.winehq.org/) -- Established compatibility database structure
- [Lutris architecture](https://github.com/lutris/lutris) -- SQLite-based game library with community install scripts
- [Bottles](https://usebottles.com/) -- Isolated Wine prefix management (comparable architecture)
- [Wine process management](https://forum.winehq.org/viewtopic.php?t=29046) -- Wineserver lifecycle, zombie process handling
- [wineserver man page](https://man.archlinux.org/man/wineserver.1.en) -- Wineserver shutdown and process management

---
*Architecture research for: Wine bottle management macOS app*
*Researched: 2026-02-08*
