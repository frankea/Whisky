# Phase 7: Game Compatibility Database - Research

**Researched:** 2026-02-10
**Domain:** Bundled JSON game configuration database, executable matching, settings application/undo, SwiftUI search/list/detail views
**Confidence:** HIGH

## Summary

Phase 7 introduces a bundled game compatibility database that lets users look up verified configurations for common games and apply them with one click. The implementation builds on established patterns: JSON resource loading (Phase 5's `PatternLoader`/`Bundle.module`), settings composition (`EnvironmentBuilder` 8-layer cascade from Phase 2), graphics backend model (Phase 4's `GraphicsBackend`/`ProgramOverrides`), and DLL override resolution (`DLLOverrideResolver`). The PE parser already extracts `timeDateStamp` from `COFFFileHeader` for fingerprinting, and program settings are plist-serializable via `PropertyListEncoder`.

The core technical challenges are: (1) designing a JSON schema for `GameDB.json` that encodes game entries with multiple variants, env vars, DLL overrides, winetricks verbs, and per-constraint metadata; (2) implementing a tiered matching algorithm that combines hard identifiers (Steam App ID, exe fingerprint), strong heuristics (exe filename, PE metadata), and fuzzy name matching with explainability; (3) building a settings snapshot/restore mechanism for undo using the existing plist serialization; and (4) creating a Command-K style search UI integrated into both the global navigation and contextual program views.

No new external dependencies are required. The entire phase is implementable with Foundation (JSON decoding, file I/O), SwiftUI (search, list, detail, diff preview), and WhiskyKit (EnvironmentBuilder, DLLOverrideResolver, ProgramOverrides, WinetricksVerbCache). The `GameDB.json` file ships as a bundled resource in WhiskyKit alongside the existing `patterns.json` and `remediations.json`.

**Primary recommendation:** Add `GameDB.json` as a new SPM resource in WhiskyKit's `GameDatabase/Resources/` directory, model game entries as `Codable`/`Sendable` structs with a `GameDBLoader` following the `PatternLoader` pattern, implement matching via a `GameMatcher` service with tiered scoring, build settings application through a `GameConfigApplicator` that snapshots current settings before mutation and resolves changes through the existing `EnvironmentBuilder`/`DLLOverrideResolver` cascade, and present the UI via a global `GameConfigurationView` with search and a contextual banner system.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Discovery & matching
- **Primary entry point:** Global "Game Configurations" view with prominent search box (title + aliases), filters (store, backend, anti-cheat, rating), and "Apply to..." action
- **Contextual suggestions (secondary):** Auto-detect when adding/opening an exe or creating a bottle; show "Config available: Apply" banner. In program settings: "Recommended configs for this program" if matched. In crash diagnostics: remediation cards can link to "Apply known-good config"
- **Matching strategy:** Tiered confidence scoring with explainability:
  - Hard identifiers (auto-apply eligible): Steam App ID from appmanifest/steam_appid.txt, exe fingerprint (sha256 or size+PE timestamp)
  - Strong heuristic (auto-suggest, require confirmation): Exact exe filename, PE metadata (ProductName, CompanyName), install path patterns
  - Fuzzy (search results only): Tokenized name matching against exe name, folder names, DB title + aliases with similarity scoring and minimum threshold
- **Negative handling:** Penalize generic executables (launcher.exe, setup.exe, etc.). If top-2 scores are close, show "Possible matches" instead of auto-suggesting. Always show "Why this match?" explanation and allow "Not this" suppression
- **Search scope:** DB entries only by default. Empty state shows "No configuration found" with actions for requesting/submitting a config. Optional toggle "Include installed programs" for secondary flow

#### Apply experience
- **Preview:** Always show before/after diff by default, grouped by area (Graphics, Performance, Input, DLL overrides, Winetricks, env vars). High-impact changes called out explicitly. "Don't show again" option available
- **Apply target:** Context-aware default -- program-level when triggered from program context, user chooses (bottle vs program) from global view. Config can include both scopes; show both in preview with optional parts uncheckable
- **Undo/revert:** Snapshot current settings (Metadata.plist, program plists) before apply. Toast with one-click Undo after apply. "Revert config changes" available from game config page or bottle Config screen. Revert restores settings exactly; winetricks/prefix mutations noted as non-reversible ("Settings reverted; installed components remain")
- **Winetricks handling:** Preflight check in preview lists required verbs and which are missing. Explicit "Install Required Components..." action (never silent). Allow "Apply settings only" if user declines installs; mark config as "Incomplete (missing dependencies)"
- **Restart behavior:** If changes require restart, show "Apply and restart (next launch)" option; never silently stop running processes

#### Entry content & presentation
- **List view rows:** Title + subtitle (edition/store), rating badge (Works/Playable/Unverified/Broken/Not Supported), recommended backend tag (DXVK/D3DMetal/WineD3D), key constraint tags (Apple Silicon, Intel, Wine 10+), one-line note (most important caveat). Primary click opens detail; secondary quick action "Apply..."
- **Rating tiers (fixed set):** Works, Playable, Unverified, Broken, Not Supported
- **Detail view sections:** At a glance, Recommended configuration, Variants, What it changes, Notes / Known issues, Provenance
- **Variants:** One game entry with multiple variants. Auto-select "Recommended for this machine" using CPU arch, macOS version, Wine version, backend capabilities. If multiple fit, show top 2-3 with one-line diff summary. Wine version changes require explicit confirmation
- **Data sourcing (initial 20-50 entries):** Maintainer-verified configs, existing Whisky knowledge, community PR submissions, external databases as reference only

#### Staleness & trust signals
- **Staleness detection:** Store lastTestedAt + tested macOS/Wine/Whisky versions + CPU arch per entry. Show "Stale" warning when: >90 days since last tested, OR user's macOS newer by >1 minor release, OR Wine major version differs
- **Stale apply:** Warning banner in preview ("This config hasn't been verified recently...") with "Apply anyway" -- no hard block
- **DB updates:** Bundled-only for v1 (GameDB.json ships with app). Remote signed overlay designed but deferred
- **Provenance display:** In detail view "About this config" section near bottom. Exception: unverified/community entries surface trust cue higher

### Claude's Discretion
- JSON schema design for GameDB entries
- Matching algorithm implementation (similarity scoring, threshold tuning)
- List/detail view layout specifics (spacing, typography)
- Snapshot storage format for undo/revert
- How "Don't show again" preference is persisted
- Raw settings display in "Show advanced details" expandable

### Deferred Ideas (OUT OF SCOPE)
- Remote DB refresh / community config updates -- designed schema and safety model but deferred to post-v1
- Community submission workflow (in-app "Submit config" with evidence bundle) -- future enhancement
- "Re-test + submit results" flow for stale entries -- future enhancement
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | macOS 15+ | JSONDecoder for GameDB.json, PropertyListEncoder for snapshots, FileManager for file I/O | Already used throughout WhiskyKit for all data model encoding |
| SwiftUI | macOS 15+ | SearchableList, NavigationStack, Form, Section, diff preview views | Already used for all app views |
| CryptoKit | macOS 15+ | SHA256 for exe fingerprinting (optional hard identifier) | Apple framework, no external dependency needed |
| os.log | macOS 15+ | Logger for match scoring, apply actions, revert operations | Already used via Logger extension throughout codebase |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SemanticVersion | 0.4.0+ | Wine/macOS version comparison for staleness checks | Already a dependency in WhiskyKit Package.swift |
| XCTest | Swift 6 | Unit tests for GameMatcher scoring, GameDBLoader, GameConfigApplicator | Required for all data model and logic validation |

### Alternatives Considered
No new external dependencies needed. The existing stack provides all capabilities:
- **JSON loading**: `PatternLoader` pattern already proven for bundled JSON resources
- **Text matching**: Foundation's `String` APIs + custom tokenization sufficient for name matching; no need for heavyweight fuzzy search libraries
- **Settings snapshot**: PropertyListEncoder/Decoder already used for Metadata.plist and program plists

**Installation:** No new packages required. Add `GameDatabase/Resources/` to the SPM resources in Package.swift.

## Architecture Patterns

### Recommended File Structure

```
WhiskyKit/Sources/WhiskyKit/
  GameDatabase/
    GameDBEntry.swift           # Core data models (GameDBEntry, GameConfigVariant, etc.)
    GameDBRating.swift          # CompatibilityRating enum
    GameDBLoader.swift          # JSON loading, follows PatternLoader pattern
    GameMatcher.swift           # Tiered matching algorithm
    GameConfigApplicator.swift  # Apply/revert logic, settings snapshots
    GameConfigSnapshot.swift    # Snapshot model for undo/revert
    MatchResult.swift           # Match scoring, confidence, explainability
    Resources/
      GameDB.json               # Bundled game database (20-50 entries)

Whisky/
  Views/
    GameDB/
      GameConfigurationView.swift       # Global list + search (primary entry point)
      GameEntryDetailView.swift         # Detail view with sections
      GameEntryRowView.swift            # List row with rating badge, tags
      GameConfigPreviewSheet.swift      # Before/after diff preview
      GameConfigBannerView.swift        # Contextual "Config available" banner
      GameVariantPickerView.swift       # Variant selection card UI
      GameConfigSearchBar.swift         # Command-K style search
  Utils/
    GameConfigIntegration.swift         # Integration with FileOpenView, ProgramView, DiagnosticsView
```

### Pattern 1: JSON Resource Loading (following PatternLoader)

**What:** Load and validate the GameDB.json from the SPM bundle, decoded into typed Codable structs.
**When to use:** App startup and whenever the database needs to be accessed.
**Example:**
```swift
// Source: existing PatternLoader.swift pattern in WhiskyKit
public enum GameDBLoader {
    private struct GameDBFile: Codable {
        let version: Int
        let entries: [GameDBEntry]
    }

    public static func loadEntries(from url: URL) throws -> [GameDBEntry] {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(GameDBFile.self, from: data)
        return file.entries
    }

    public static func loadDefaults() -> [GameDBEntry] {
        guard let url = Bundle.module.url(forResource: "GameDB", withExtension: "json") else {
            #if DEBUG
            fatalError("Missing resource: GameDB.json in Bundle.module")
            #else
            return []
            #endif
        }
        do {
            return try loadEntries(from: url)
        } catch {
            #if DEBUG
            fatalError("Failed to load GameDB: \(error)")
            #else
            return []
            #endif
        }
    }
}
```

### Pattern 2: Settings Application via EnvironmentBuilder Cascade

**What:** Game config application works through the existing settings model, not by directly manipulating environment variables. The applicator sets `BottleSettings` properties and `ProgramOverrides` fields, which then flow through the 8-layer EnvironmentBuilder cascade at launch time.
**When to use:** When "Apply" is clicked in the preview sheet.
**Example:**
```swift
// Apply works by mutating the same BottleSettings / ProgramOverrides
// that the EnvironmentBuilder already consumes
public struct GameConfigApplicator {
    /// Applies a game config variant to a bottle's settings
    @MainActor
    public static func apply(
        variant: GameConfigVariant,
        to bottle: Bottle,
        programOverrides: inout ProgramOverrides?,
        snapshot: inout GameConfigSnapshot
    ) {
        // Snapshot current state BEFORE mutation
        snapshot.bottleSettings = bottle.settings

        // Apply graphics backend
        if let backend = variant.graphicsBackend {
            bottle.settings.graphicsBackend = backend
        }

        // Apply env vars via the existing pattern -- these become
        // bottle-level custom env vars or ProgramOverrides fields
        if let dxvk = variant.dxvk {
            bottle.settings.dxvk = dxvk
        }

        // DLL overrides go through the existing dllOverrides array
        if let overrides = variant.dllOverrides {
            bottle.settings.dllOverrides.append(contentsOf: overrides)
        }

        bottle.saveBottleSettings()
    }
}
```

### Pattern 3: Settings Snapshot for Undo (Plist Serialization)

**What:** Before applying a game config, serialize the current `BottleSettings` and relevant `ProgramSettings` to Data blobs using PropertyListEncoder. Store in a per-bottle snapshot file. Revert deserializes and restores.
**When to use:** Undo/revert after game config application.
**Example:**
```swift
// Source: existing BottleSettings.encode(to:) / .decode(from:) pattern
public struct GameConfigSnapshot: Codable {
    /// Serialized BottleSettings plist data from before the apply
    public var bottleSettingsData: Data?
    /// Serialized ProgramSettings plist data for affected programs
    public var programSettingsData: [URL: Data]?
    /// Winetricks verbs that were installed (non-reversible, noted in UI)
    public var installedVerbs: [String]?
    /// Timestamp of when the snapshot was created
    public var timestamp: Date

    private static let snapshotFileName = "GameConfigSnapshot.plist"

    public static func save(_ snapshot: GameConfigSnapshot, to bottleURL: URL) throws {
        let url = bottleURL.appending(path: snapshotFileName)
        let data = try PropertyListEncoder().encode(snapshot)
        try data.write(to: url)
    }

    public static func load(from bottleURL: URL) -> GameConfigSnapshot? {
        let url = bottleURL.appending(path: snapshotFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(GameConfigSnapshot.self, from: data)
    }
}
```

### Pattern 4: Tiered Match Scoring with Explainability

**What:** The GameMatcher produces scored results with human-readable explanations of why each match was made, following the user's tiered strategy.
**When to use:** Auto-detection on exe open, contextual suggestions in program settings.
**Example:**
```swift
public struct MatchResult: Sendable {
    public let entry: GameDBEntry
    public let confidence: Double        // 0.0...1.0
    public let tier: MatchTier           // .hardIdentifier, .strongHeuristic, .fuzzy
    public let explanation: String       // "Matched Steam appid 12345"
    public let variant: GameConfigVariant? // Auto-selected variant for this machine
}

public enum MatchTier: Int, Comparable, Sendable {
    case hardIdentifier = 3    // Auto-apply eligible
    case strongHeuristic = 2   // Auto-suggest, require confirmation
    case fuzzy = 1             // Search results only

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### Anti-Patterns to Avoid
- **Direct env var injection:** Never bypass the EnvironmentBuilder. Game configs set `BottleSettings` properties and `ProgramOverrides` fields, which are resolved through the existing 8-layer cascade at launch. This preserves provenance tracking.
- **Monolithic GameDB.swift:** Split the domain into focused files (entry model, loader, matcher, applicator, snapshot) following the Phase 5 diagnostics pattern (`CrashPattern`, `PatternLoader`, `CrashClassifier`, `RemediationAction`).
- **Blocking search:** The game DB will have 20-50 entries initially, so in-memory filtering is fine. Do not over-engineer with background search or indexing for v1.
- **Silent winetricks installation:** The CONTEXT.md explicitly forbids silent verb installation. Always show what will be installed and require explicit action.
- **Modifying env vars at runtime:** Game configs are applied before launch via settings mutation. Never try to inject env vars into a running Wine process.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Settings persistence | Custom file format for snapshots | `PropertyListEncoder`/`PropertyListDecoder` (already used for `BottleSettings`, `ProgramSettings`) | Exact roundtrip fidelity with existing plist format, proven pattern |
| JSON loading from bundle | Custom resource discovery | `Bundle.module.url(forResource:)` + `JSONDecoder` (PatternLoader pattern) | SPM handles resource bundling; pattern already proven in Phase 5 |
| DLL override composition | Manual WINEDLLOVERRIDES string building | `DLLOverrideResolver` with managed/bottleCustom/programCustom layers | Handles precedence, warnings, and deterministic output; already validated |
| Graphics backend env vars | Direct env var dict manipulation | `BottleSettings.populateBottleManagedLayer(builder:)` | Encapsulates DXVK/D3DMetal/wined3d env var emission with DLL override composition |
| Version comparison | String parsing for semver | `SemanticVersion` package (already a dependency) | Handles comparison operators, already used in `BottleSettings.fileVersion` |
| Winetricks verb detection | Parsing log files manually | `Winetricks.loadInstalledVerbs(for:)` with `WinetricksVerbCache` | Cache-aware, handles both list-installed and log parsing fallback |
| PE timestamp extraction | Manual binary parsing | `PEFile.coffFileHeader.timeDateStamp` | Already parsed and available as `Date` on every `Program.peFile` |

**Key insight:** Phase 7 does not require new infrastructure for settings, env vars, DLL overrides, or graphics backends. The entire apply/revert flow can be built by composing existing types: `BottleSettings` (mutate properties) -> `EnvironmentBuilder` (resolves at launch) -> `DLLOverrideResolver` (composes DLL overrides) -> `Wine.constructWineEnvironment` (final dict). The snapshot is simply "serialize current plist, deserialize on revert."

## Common Pitfalls

### Pitfall 1: Applying DLL overrides additively without cleanup
**What goes wrong:** Game config appends DLL overrides to `bottle.settings.dllOverrides`. On revert, the snapshot restores the original list. But if the user manually added overrides between apply and revert, the revert clobbers their additions.
**Why it happens:** The snapshot stores the full `dllOverrides` array, not a delta.
**How to avoid:** Document this in the UI: "Revert restores settings to their exact state before apply." Consider storing a delta (added entries only) for more surgical revert, but for v1 the full-snapshot approach is simpler and matches user expectations.
**Warning signs:** User reports losing custom DLL overrides after reverting a game config.

### Pitfall 2: Winetricks verbs are not reversible
**What goes wrong:** Game config installs winetricks verbs (e.g., vcrun2022, dotnet48). These modify the Wine prefix filesystem. Revert restores settings but the DLLs remain installed.
**Why it happens:** Winetricks modifies `drive_c/windows/system32/` and registry entries. There is no "uninstall verb" equivalent.
**How to avoid:** The CONTEXT.md already specifies the solution: clearly communicate "Settings reverted; installed components remain" in the UI. The preview should list which verbs will be installed and note their permanence.
**Warning signs:** Users expect full revert including winetricks components.

### Pitfall 3: Generic exe name false positives in matching
**What goes wrong:** Many games use `launcher.exe`, `game.exe`, `start.exe`, or `app.exe`. Matching on filename alone produces false positives.
**Why it happens:** Generic filenames are common in game installations.
**How to avoid:** The CONTEXT.md specifies penalizing generic executables. Maintain a denylist of generic names (similar to `LauncherDetection.detectLauncher`'s specific handling of "launcher.exe"). Require additional signals (path components, PE metadata) for generic names. Show "Possible matches" instead of auto-suggesting when confidence is marginal.
**Warning signs:** Auto-detection incorrectly suggesting configs for unrelated programs.

### Pitfall 4: Stale entry applied without warning
**What goes wrong:** A game config was last tested on macOS 14 with Wine 9.x. User is running macOS 15.4 with Wine 10.x. Applied config causes issues because env vars or behavior changed between versions.
**Why it happens:** The staleness check was not surfaced prominently enough, or the user dismissed it.
**How to avoid:** Implement staleness detection as specified: compare `lastTestedAt`, macOS minor version delta, Wine major version. Show yellow warning banner in preview. Never block, but make the risk visible.
**Warning signs:** User reports that "recommended" config breaks their game.

### Pitfall 5: GameDB.json schema breaking changes
**What goes wrong:** A future schema update adds required fields or changes field semantics. Older bundled DBs fail to decode.
**Why it happens:** JSON schema evolution without versioning.
**How to avoid:** Include a `version` field in the root of `GameDB.json` (following `PatternLoader`'s `PatternFile.version`). Use defensive `decodeIfPresent` for all optional fields (following `BottleSettings.init(from:)` pattern). New fields default to safe values. Never remove or rename existing fields; deprecate and add new ones.
**Warning signs:** App crashes on launch after update due to JSON decode failure.

### Pitfall 6: Snapshot file grows unbounded
**What goes wrong:** Each apply creates a new snapshot. Multiple game config applications accumulate snapshot files.
**Why it happens:** No cleanup policy for old snapshots.
**How to avoid:** Store only the most recent snapshot per bottle (overwrite). If multi-level undo is needed in the future, cap at 3-5 snapshots with oldest-first eviction (similar to `Wine.enforceLogRetention`).
**Warning signs:** Bottle directory accumulates large plist snapshot files.

## Code Examples

Verified patterns from the existing codebase:

### JSON Resource Loading in SPM
```swift
// Source: WhiskyKit/Package.swift line 41, Diagnostics/Resources/
// Existing: resources: [.process("Diagnostics/Resources/")]
// Add: resources: [.process("Diagnostics/Resources/"), .process("GameDatabase/Resources/")]
```

### Defensive Codable Decoding (BottleSettings pattern)
```swift
// Source: BottleSettings.swift init(from:)
// Every optional field uses decodeIfPresent with a safe default
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    self.rating = try container.decodeIfPresent(CompatibilityRating.self, forKey: .rating) ?? .unverified
    self.variants = try container.decodeIfPresent([GameConfigVariant].self, forKey: .variants) ?? []
    // ... all fields use decodeIfPresent
}
```

### Existing PE Metadata Available for Matching
```swift
// Source: COFFFileHeader.swift, PortableExecutable.swift
// Available on every Program.peFile:
// - peFile.coffFileHeader.timeDateStamp: Date (PE build timestamp)
// - peFile.coffFileHeader.machine: UInt16 (architecture)
// - peFile.architecture: Architecture (.x32, .x64, .unknown)
// - peFile.url: URL (file path for size calculation)

// For fingerprinting: combine file size + PE timestamp
let fileSize = try FileManager.default.attributesOfItem(
    atPath: url.path(percentEncoded: false)
)[.size] as? Int64
let timestamp = peFile.coffFileHeader.timeDateStamp
```

### Settings Mutation Triggers Auto-Save
```swift
// Source: Bottle.swift line 86-88, Program.swift line 108-109
// BottleSettings saves on didSet, ProgramSettings saves on didSet
@Published public var settings: BottleSettings {
    didSet { saveSettings() }
}
// This means the GameConfigApplicator can simply mutate properties
// and persistence happens automatically.
```

### DLL Override Integration
```swift
// Source: DLLOverride.swift, WineEnvironment.swift
// Game config DLL overrides should go through bottle.settings.dllOverrides
// which feeds into DLLOverrideResolver.bottleCustom layer
// For per-program overrides, use ProgramOverrides.dllOverrides
// which feeds into DLLOverrideResolver.programCustom layer
let resolver = DLLOverrideResolver(
    managed: managedOverrides,
    bottleCustom: bottle.settings.dllOverrides,  // game config bottle-level overrides go here
    programCustom: programOverrides?.dllOverrides ?? []  // game config program-level here
)
```

### Winetricks Verb Preflight Check
```swift
// Source: Winetricks+InstalledVerbs.swift
// Use loadInstalledVerbs to check which verbs are already installed
let (installedVerbs, _) = await Winetricks.loadInstalledVerbs(for: bottle)
let requiredVerbs = Set(variant.winetricksVerbs ?? [])
let missingVerbs = requiredVerbs.subtracting(installedVerbs)
// Show missingVerbs in the preview UI
```

### Contextual Navigation Pattern (BottleView stages)
```swift
// Source: BottleView.swift - navigation via NavigationLink + BottleStage enum
// Game Configurations can be added as a new BottleStage
enum BottleStage {
    case config
    case programs
    case processes
    case gameConfigs  // NEW
}
// Or as a top-level sidebar entry if it should be global
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct env var dict manipulation | EnvironmentBuilder 8-layer cascade | Phase 2 | Game configs MUST use BottleSettings/ProgramOverrides, not raw env vars |
| Single DXVK bool toggle | GraphicsBackend enum with .recommended auto-resolution | Phase 4 | Game configs specify backend enum value, not boolean |
| No per-program overrides | ProgramOverrides with nil=inherit pattern | Phase 2 | Game configs can target program-level with structured overrides |
| No DLL override UI | DLLOverrideResolver with 3-layer composition | Phase 4 | Game config DLL overrides compose through the resolver, not raw strings |
| Manual winetricks only | WinetricksVerbCache with staleness detection | Phase 6 | Can preflight-check which verbs are installed before suggesting |
| No crash diagnostics | CrashClassifier + RemediationAction | Phase 5 | Crash remediation cards can link to "Apply known-good config" |

**Deprecated/outdated:**
- `BottleSettings.environmentVariables(wineEnv:)`: Deprecated in Phase 2, replaced by EnvironmentBuilder layer populators. Game config code MUST NOT use this method.

## JSON Schema Design (Claude's Discretion)

### Recommended GameDB.json Schema

```json
{
  "version": 1,
  "entries": [
    {
      "id": "elden-ring",
      "title": "Elden Ring",
      "aliases": ["ELDEN RING", "eldenring"],
      "subtitle": "Bandai Namco",
      "store": "steam",
      "steamAppId": 1245620,
      "rating": "playable",
      "exeNames": ["eldenring.exe"],
      "exeFingerprints": [
        {
          "sha256": null,
          "fileSize": 78643200,
          "peTimestamp": "2024-06-20T00:00:00Z"
        }
      ],
      "pathPatterns": ["elden ring/game"],
      "antiCheat": null,
      "constraints": {
        "cpuArchitectures": ["arm64"],
        "minMacOSVersion": "15.0.0",
        "minWineVersion": "9.0",
        "requiredBackendCapabilities": []
      },
      "variants": [
        {
          "id": "recommended-apple-silicon",
          "label": "Recommended (Apple Silicon)",
          "isDefault": true,
          "whenToUse": "Standard setup for M-series Macs",
          "rationale": [
            "D3DMetal provides best performance on Apple Silicon",
            "Enhanced sync improves frame pacing",
            "Shader cache reduces first-run stuttering"
          ],
          "settings": {
            "graphicsBackend": "d3dMetal",
            "dxvk": false,
            "dxvkAsync": false,
            "enhancedSync": "esync",
            "forceD3D11": false,
            "performancePreset": "balanced",
            "shaderCacheEnabled": true,
            "avxEnabled": false,
            "sequoiaCompatMode": false
          },
          "environmentVariables": {
            "D3DM_SUPPORT_DXR": "0"
          },
          "dllOverrides": [],
          "winetricksVerbs": ["vcrun2022"],
          "testedWith": {
            "lastTestedAt": "2026-01-15T00:00:00Z",
            "macOSVersion": "15.3.0",
            "wineVersion": "10.0",
            "whiskyVersion": "3.0.0",
            "cpuArchitecture": "arm64"
          }
        }
      ],
      "notes": [
        "Easy Anti-Cheat must be disabled; online play is not available",
        "First launch may take 2-3 minutes for shader compilation"
      ],
      "knownIssues": [
        {
          "description": "Occasional shader compilation stutter in open world",
          "severity": "minor",
          "workaround": "Enable shader cache and wait for initial compilation"
        }
      ],
      "provenance": {
        "source": "maintainer-verified",
        "author": "Whisky Team",
        "lastUpdated": "2026-01-15T00:00:00Z",
        "referenceURL": null
      }
    }
  ]
}
```

### Schema Design Rationale

1. **Flat settings object in variants:** Maps directly to `BottleSettings` property names, making the applicator trivial -- just set matching properties. No translation layer needed.
2. **Separate `environmentVariables` dict:** For env vars that don't map to named settings (e.g., game-specific Wine env vars). These go into the `bottleUser` layer of EnvironmentBuilder.
3. **`dllOverrides` as `[{dllName, mode}]`:** Directly maps to `DLLOverrideEntry` for the resolver.
4. **`exeFingerprints` array:** Supports multiple versions of the same game. `sha256` is optional (expensive to compute); `fileSize` + `peTimestamp` is the fast path.
5. **`constraints` object:** Enables variant auto-selection by filtering against the current machine's capabilities.
6. **`testedWith` per variant:** Enables granular staleness detection per variant, not just per entry.

## Matching Algorithm Design (Claude's Discretion)

### Recommended Scoring Approach

```
Score = max(hardIdentifierScore, heuristicScore, fuzzyScore)

Hard Identifiers (0.95-1.0):
  - Steam App ID match from appmanifest: 1.0
  - Steam App ID match from steam_appid.txt: 0.98
  - SHA256 fingerprint match: 0.99
  - File size + PE timestamp match: 0.95

Strong Heuristics (0.7-0.9):
  - Exact exe name match (non-generic): 0.85
  - Exact exe name + path pattern match: 0.90
  - PE ProductName/CompanyName match: 0.80

Fuzzy (0.3-0.6):
  - Tokenized name match (exe name vs title+aliases): 0.3-0.6 based on token overlap
  - Folder name match: +0.1 bonus

Penalties:
  - Generic exe name (launcher.exe, setup.exe, game.exe): -0.3
  - Multiple entries with similar scores (top-2 within 0.1): downgrade to "Possible matches"

Thresholds:
  - Auto-suggest: >= 0.7
  - Show in search results: >= 0.3
  - Suppress: < 0.3
```

### Generic Executable Denylist
```swift
private static let genericExeNames: Set<String> = [
    "launcher.exe", "setup.exe", "start.exe", "game.exe",
    "app.exe", "install.exe", "uninstall.exe", "updater.exe",
    "config.exe", "settings.exe", "crash_reporter.exe",
    "ue4-win64-shipping.exe", "unity.exe"
]
```

## Snapshot Storage Format (Claude's Discretion)

**Recommendation:** Single `GameConfigSnapshot.plist` per bottle, overwritten on each apply. Contains:
- Serialized `BottleSettings` as Data (via PropertyListEncoder)
- Map of program URL -> serialized `ProgramSettings` as Data
- List of winetricks verbs installed during this apply (informational)
- Applied entry ID and variant ID (for display in "Revert" UI)
- Timestamp

This follows the `WinetricksVerbCache` storage pattern (plist in bottle directory alongside `Metadata.plist`).

## "Don't Show Again" Preference (Claude's Discretion)

**Recommendation:** Use `@AppStorage("gameConfigSkipPreview")` as a global boolean in UserDefaults. When true, apply action triggers directly with a minimal toast ("Applied Elden Ring config") instead of the full preview sheet. A "Show preview" link in the toast allows one-time override. The preference can be reset from Whisky Settings.

## Open Questions

1. **PE version info resource parsing**
   - What we know: The existing PE parser reads COFF headers and resource sections (for icons). PE files can contain a `VS_VERSION_INFO` resource with `ProductName`, `CompanyName`, `FileDescription` strings.
   - What's unclear: The current `PEFile` does not expose version info string tables. Adding this would improve strong heuristic matching significantly.
   - Recommendation: For v1, rely on exe filename + path patterns + Steam App ID for matching. PE version info parsing can be added as an enhancement to `PEFile` in a later iteration. The matching algorithm should still work well without it, since most games have distinctive exe names or Steam App IDs.

2. **Steam appmanifest parsing**
   - What we know: Steam stores `appmanifest_<appid>.acf` files in `steamapps/` directories within the bottle's `drive_c`. These are key-value text files containing the app ID.
   - What's unclear: The exact directory structure varies. Some games also have `steam_appid.txt` in their install directory.
   - Recommendation: Implement both lookup strategies: scan for `appmanifest_*.acf` files in common Steam library paths within the bottle, and check for `steam_appid.txt` in the exe's directory and parent directories.

3. **Global vs bottle-scoped Game Configurations view**
   - What we know: CONTEXT.md specifies a "Global Game Configurations view" as primary entry point.
   - What's unclear: Whether this is a new top-level navigation item in the sidebar (alongside bottle list) or a new stage within a selected bottle.
   - Recommendation: Add as a `NavigationLink` in the `BottleView` navigation stack (alongside Config, Programs, Processes), since game configs are applied to specific bottles. Also provide a global entry point via a toolbar button or menu item that opens the search and lets the user choose a target bottle during apply.

## Sources

### Primary (HIGH confidence)
- Codebase analysis of WhiskyKit source files: `BottleSettings.swift`, `EnvironmentBuilder.swift`, `WineEnvironment.swift`, `DLLOverride.swift`, `ProgramOverrides.swift`, `PatternLoader.swift`, `CrashPattern.swift`, `PortableExecutable.swift`, `COFFFileHeader.swift`, `LauncherPresets.swift`, `WinetricksVerbCache.swift`, `Winetricks+InstalledVerbs.swift`
- Codebase analysis of Whisky app views: `BottleView.swift`, `ConfigView.swift`, `ContentView.swift`, `BackendPickerView.swift`, `ProgramOverrideSettingsView.swift`
- WhiskyKit Package.swift for SPM resource configuration
- Existing planning documents: `04-RESEARCH.md` for format and pattern reference

### Secondary (MEDIUM confidence)
- PE format documentation: [Microsoft PE Format Spec](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format) for COFF header and version info resource structure
- Steam appmanifest format: Well-documented ACF/VDF key-value format used by Valve

### Tertiary (LOW confidence)
- Fuzzy matching threshold tuning: Recommended thresholds (0.3/0.7) are educated estimates that will need empirical tuning with real game data during initial DB population

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All technologies already used in the codebase; no new dependencies
- Architecture: HIGH - Follows proven patterns (PatternLoader, BottleSettings, EnvironmentBuilder) already validated in Phases 2-6
- JSON Schema: HIGH - Designed to map directly to existing Codable types with defensive decoding
- Matching Algorithm: MEDIUM - Scoring thresholds are theoretical; will need tuning with real data
- Pitfalls: HIGH - Based on direct codebase analysis of how settings flow through the system

**Research date:** 2026-02-10
**Valid until:** 2026-03-10 (stable domain; no fast-moving external dependencies)
