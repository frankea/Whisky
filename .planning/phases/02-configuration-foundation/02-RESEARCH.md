# Phase 2: Configuration Foundation - Research

**Researched:** 2026-02-09
**Domain:** Environment variable cascade, per-program settings, DLL override management, winetricks verb tracking
**Confidence:** HIGH

## Summary

Phase 2 refactors the environment variable construction path from an ad-hoc imperative chain into a layered `EnvironmentBuilder` with explicit precedence, provenance tracking, structured DLL override management, per-program setting overrides, and winetricks verb tracking. This is a pure WhiskyKit + Whisky app refactor with no external dependencies needed.

The current codebase constructs environment variables through a chain of mutable dictionary mutations: `constructWineEnvironment()` creates a base dict, calls `applyMacOSCompatibilityFixes()`, then `bottle.settings.environmentVariables()` which internally calls `applyLauncherCompatibility()`, `applyInputCompatibility()`, and `applyPerformancePreset()`. The caller-provided `environment` dict (from `Program.generateEnvironment()`) is merged last. This chain has implicit ordering, no provenance, conflicting override patterns (some use `merge`, some use `updateValue`, some use `removeValue`), and the WINEDLLOVERRIDES key is constructed as a flat string with no composition.

The refactor introduces an `EnvironmentBuilder` that collects entries into explicit layers, resolves conflicts deterministically (later layer wins per-key, except WINEDLLOVERRIDES which composes per-DLL), and produces both the final `[String: String]` and provenance metadata. This is pure data transformation with no framework dependencies beyond Foundation.

**Primary recommendation:** Build EnvironmentBuilder as a struct in WhiskyKit with a builder-pattern API, extract all environment logic from `BottleSettings.environmentVariables()` and `constructWineEnvironment()` into layer-populating functions, and wire it through `Wine.runWineProcess()` and `Wine.runWineserverProcess()`. The DLL override model, ProgramOverrides struct, and winetricks verb tracking are independent data model additions that can be implemented in parallel with the builder.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **DLL Override Editing**: First-class structured DLL override editor: table with DLL name (no `.dll` suffix) + Mode dropdown (`Builtin (b)`, `Native (n)`, `Native then Builtin (n,b)`, `Builtin then Native (b,n)`, `Disabled`). Add / Remove / Reset actions. Show "Inherited (from bottle)" vs "Overridden (this program)" indicators. Store overrides as structured data (dictionary) in ProgramSettings; EnvironmentBuilder renders the final `WINEDLLOVERRIDES` string. Optional "Advanced" reveal for raw `WINEDLLOVERRIDES` editing as escape hatch. Lightweight presets via a `Presets...` button: at minimum `DXVK (recommended)` applying `dxgi,d3d9,d3d10core,d3d11=n,b`. Per-DLL conflict resolution: `effective[dll] = programOverride[dll] ?? bottleCustom[dll] ?? bottleManaged[dll]`. Warning if user overrides a DXVK-managed DLL away from `n,b`.
- **DLL Override -- Bottle Level**: Keep existing implicit behavior: DXVK toggle + launcher presets generate "Managed" overrides (read-only in UI, lock icon). Add an "Advanced: Custom DLL Overrides" table at bottle level. Effective DLL override order: managed (DXVK/launcher) -> bottle custom -> program custom (most specific wins per-DLL). Warning if user's custom entries override a managed DXVK DLL.
- **Winetricks Verb Tracking**: Primary discovery: run bundled `winetricks list-installed` non-interactively. Fallback: parse `<WINEPREFIX>/winetricks.log`. Only scan when opening Winetricks UI or on explicit refresh. Persist a per-bottle cache. Background refresh after loading cache. Cheap staleness detection via `winetricks.log` mtime/size. UI: toggle/segmented control `All` / `Installed`; show "Installed" indicator on verb rows. Verb tracking is bottle/prefix-scoped. In program settings, show installed verbs as read-only info.
- **Layer Model (EnvironmentBuilder)**: 8 coarse, stable layers: base -> platform -> bottle_managed -> launcher_managed -> bottle_user -> program_user -> feature_runtime -> callsite_override. Returns both final `[String: String]` and provenance data. Provenance data captured in Phase 2; Environment Inspector UI deferred to Phase 5.
- **Launch Logging**: Do NOT log full resolved environment by default. Log a small safe summary at launch. Provide opt-in diagnostics mode or "Copy environment report" action.
- **Per-Program Override Scope**: Overrideable: DXVK (on/off, async, HUD), sync mode, D3D mode, performance preset/shader cache, input/SDL fixes, DLL overrides. Bottle-only: windowsVersion, wineVersion, pins/blocklist, vcRedistInstalled, cleanup policies, diagnostics Metal toggles.
- **Per-Program Override UX**: Each overrideable group defaults to "Inherit from bottle". Toggle/picker flips to "Override" with copy-on-enable. Show "Currently inherited: ..." summary. "Reset Overrides" action clears `ProgramSettings.overrides`.
- **Per-Program Data Model**: Extend `ProgramSettings` with nested `ProgramOverrides?` where each field is optional (nil = inherit). Keep existing locale/environment/arguments as-is. One plist per program; missing keys decode as inherit (backward-compatible).

### Claude's Discretion
- Exact EnvironmentBuilder API surface and internal architecture
- How to structure the provenance data types
- Preset definitions beyond DXVK (add .NET/ClickOnce only if exact DLLs can be justified)
- Winetricks log parsing implementation details
- Compression/optimization of cached verb state
- Exact UI layout of the DLL override editor and per-program settings sections
- Whether to include raw WINEDLLOVERRIDES escape hatch or defer it

### Deferred Ideas (OUT OF SCOPE)
- Environment Inspector UI -- Phase 5 (Stability and Diagnostics), using provenance data from EnvironmentBuilder
- Game profile system -- Phase 7, will use EnvironmentBuilder layers
- Audio-specific env settings -- Phase 6, slots into bottle_managed layer
- Startup zombie process sweep -- Phase 3 (ProcessRegistry is session-based)
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | macOS 15+ | PropertyListEncoder/Decoder, FileManager, Process | Already used throughout WhiskyKit |
| SwiftUI | macOS 15+ | UI views for settings editors | Already used for all Whisky views |
| os.log | macOS 15+ | Structured logging | Already used via `Logger` throughout codebase |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SemanticVersion | 0.4.0+ | Version tracking for settings file format | Already a dependency in Package.swift |
| XCTest | Swift 6 | Unit testing for EnvironmentBuilder, DLL override composition | Already used for WhiskyKitTests |

### Alternatives Considered
No external dependencies needed. This is pure Swift data transformation and SwiftUI views.

## Architecture Patterns

### Current Environment Variable Flow (as-is)

```
Wine.constructWineEnvironment(for: bottle, environment: [:])
  |
  +-- Creates base dict: WINEPREFIX, WINEDEBUG, GST_DEBUG
  +-- applyMacOSCompatibilityFixes(&result)         // mutates in-place
  +-- bottle.settings.environmentVariables(&result)  // mutates in-place
  |     +-- applyLauncherCompatibility(&wineEnv)     // if enabled
  |     +-- applyInputCompatibility(&wineEnv)        // if enabled
  |     +-- DXVK: sets WINEDLLOVERRIDES as flat string
  |     +-- Sync mode: sets WINEESYNC/WINEMSYNC
  |     +-- Metal/AVX/DXR toggles
  |     +-- applyPerformancePreset(&wineEnv)
  |     +-- Shader cache, Force D3D11
  +-- Merge caller-provided `environment` dict (last wins)
```

**Problems identified:**
1. WINEDLLOVERRIDES is set as a single flat string -- multiple sources clobber each other
2. No provenance: impossible to tell which setting came from where
3. Launcher overrides use `merge { _, new in new }` but managed overrides use `updateValue` -- inconsistent
4. `constructWineServerEnvironment()` does NOT call `bottle.settings.environmentVariables()` -- wineserver env is incomplete
5. Program environment from `generateEnvironment()` is passed as caller `environment` parameter -- no structured layer
6. EnhancedSync `.none` on macOS 15.4+ forces ESYNC even though user said "none" -- platform layer overrides user intent without visibility

### Recommended Architecture: EnvironmentBuilder

```
WhiskyKit/Sources/WhiskyKit/
  Wine/
    EnvironmentBuilder.swift       # Core builder + layer types
    EnvironmentProvenance.swift     # Provenance tracking types
    WineEnvironment.swift           # Updated: delegates to EnvironmentBuilder
    MacOSCompatibility.swift        # Unchanged (extracted into platform layer populator)
    LauncherPresets.swift           # Unchanged (extracted into launcher_managed layer populator)
  Whisky/
    BottleSettings.swift            # Remove environmentVariables(), add layer populator methods
    ProgramSettings.swift           # Add ProgramOverrides struct
    DLLOverride.swift               # NEW: DLL override model + composition
    WinetricksVerbCache.swift       # NEW: Verb cache + staleness detection
    BottleDXVKConfig.swift          # Unchanged
    BottleWineConfig.swift          # Unchanged
    ...
```

### Pattern 1: EnvironmentBuilder (Builder Pattern)

**What:** A value type that accumulates environment entries by layer, resolves conflicts deterministically, and produces both the final merged dictionary and provenance metadata.

**When to use:** Every Wine process launch.

**Recommended API:**

```swift
/// A layer in the environment variable cascade.
enum EnvironmentLayer: Int, CaseIterable, Comparable, Sendable {
    case base = 0
    case platform
    case bottleManaged
    case launcherManaged
    case bottleUser
    case programUser
    case featureRuntime
    case callsiteOverride

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tracks which layer set each environment variable.
struct EnvironmentProvenance: Sendable {
    struct Entry: Sendable {
        let key: String
        let value: String
        let layer: EnvironmentLayer
        let overriddenBy: EnvironmentLayer?
    }

    /// The winning entry for each key.
    let entries: [String: Entry]
    /// All layers that contributed at least one entry.
    let activeLayers: Set<EnvironmentLayer>
}

/// Builds the Wine environment by collecting entries from ordered layers.
struct EnvironmentBuilder: Sendable {
    private var layers: [EnvironmentLayer: [String: String]] = [:]

    mutating func set(_ key: String, _ value: String, layer: EnvironmentLayer)
    mutating func setAll(_ entries: [String: String], layer: EnvironmentLayer)
    mutating func remove(_ key: String, layer: EnvironmentLayer)

    /// Resolves all layers into a final environment dictionary.
    /// Later layers win per-key (higher rawValue = higher priority).
    func resolve() -> (environment: [String: String], provenance: EnvironmentProvenance)
}
```

**Key design decisions:**
- Struct, not class -- immutable after construction, easily testable
- `Sendable` -- safe to pass across actor boundaries (important for `@MainActor` Bottle)
- Layers as enum, not string keys -- compile-time safety, ordered by rawValue
- `resolve()` is the only materializing call -- all `set`/`setAll` are cheap accumulation

### Pattern 2: DLL Override Composition

**What:** WINEDLLOVERRIDES is special: it's a semicolon-separated list of `dllname=mode` entries. Multiple layers can contribute DLL overrides; the result must be composed per-DLL, not clobbered per-key.

**Recommended model:**

```swift
/// Mode for a DLL override entry.
enum DLLOverrideMode: String, Codable, CaseIterable, Sendable {
    case builtin = "b"
    case native = "n"
    case nativeThenBuiltin = "n,b"
    case builtinThenNative = "b,n"
    case disabled = ""
}

/// A single DLL override entry.
struct DLLOverrideEntry: Codable, Equatable, Sendable {
    let dllName: String        // without .dll suffix
    let mode: DLLOverrideMode
}

/// Source of a managed DLL override.
enum DLLOverrideSource: Codable, Equatable, Sendable {
    case dxvk
    case launcher(LauncherType)
    case userBottle
    case userProgram
}

/// Resolves DLL overrides from multiple sources into a WINEDLLOVERRIDES string.
struct DLLOverrideResolver: Sendable {
    /// Managed overrides (DXVK toggle, launcher presets) -- read-only in UI.
    var managed: [DLLOverrideEntry] = []
    /// Bottle-level custom overrides (user-defined).
    var bottleCustom: [DLLOverrideEntry] = []
    /// Program-level custom overrides (user-defined, highest priority).
    var programCustom: [DLLOverrideEntry] = []

    /// Per-DLL resolution: programCustom[dll] ?? bottleCustom[dll] ?? managed[dll]
    func resolve() -> (overrides: String, warnings: [DLLOverrideWarning])
}
```

**Integration with EnvironmentBuilder:** The `DLLOverrideResolver` is called during `resolve()` to produce the final WINEDLLOVERRIDES value. Individual DLL entries are NOT set as separate env vars; they compose into one string.

### Pattern 3: ProgramOverrides (Optional Fields for Inheritance)

**What:** Per-program settings that override bottle defaults. Each field is Optional; nil means "inherit from bottle."

**Recommended model:**

```swift
/// Per-program overrides. nil fields inherit from bottle settings.
struct ProgramOverrides: Codable, Equatable {
    // Graphics / DXVK
    var dxvk: Bool?
    var dxvkAsync: Bool?
    var dxvkHud: DXVKHUD?

    // Sync
    var enhancedSync: EnhancedSync?

    // D3D
    var forceD3D11: Bool?

    // Performance
    var performancePreset: PerformancePreset?
    var shaderCacheEnabled: Bool?

    // Input
    var controllerCompatibilityMode: Bool?
    var disableHIDAPI: Bool?
    var allowBackgroundEvents: Bool?
    var disableControllerMapping: Bool?

    // DLL overrides (structured)
    var dllOverrides: [DLLOverrideEntry]?

    /// Returns true if all fields are nil (no overrides active).
    var isEmpty: Bool { ... }

    init(from decoder: Decoder) throws {
        // All fields use decodeIfPresent -- missing keys = nil = inherit
    }
}
```

**Backward compatibility:** `ProgramSettings` gains `var overrides: ProgramOverrides?`. Existing plists that lack the `overrides` key decode as `nil`, which means full inheritance. No migration needed.

### Pattern 4: Winetricks Verb Cache

**What:** Per-bottle cache of installed winetricks verbs with staleness detection.

**Recommended model:**

```swift
/// Cached state of installed winetricks verbs for a bottle.
struct WinetricksVerbCache: Codable {
    var installedVerbs: Set<String>
    var lastChecked: Date
    var logFileSize: Int64?
    var logFileModDate: Date?

    /// Whether the cache is potentially stale based on winetricks.log changes.
    func isStale(currentLogSize: Int64?, currentLogModDate: Date?) -> Bool
}
```

**Storage:** Persisted as `WinetricksCache.plist` in the bottle directory alongside `Metadata.plist`. This avoids bloating the main settings file.

**Discovery flow:**
1. On Winetricks UI open, load `WinetricksVerbCache` from plist (instant)
2. Check `winetricks.log` mtime/size against cached values
3. If stale or no cache, spawn `winetricks list-installed` in background
4. Parse stdout into `Set<String>`, update cache, refresh UI
5. Fallback: if `winetricks list-installed` fails, parse `winetricks.log` directly

### Pattern 5: Config Section UI Pattern (Existing)

The codebase has two UI patterns for config sections:

1. **Section-based** (used by DXVK, Performance, Cleanup, Wine): `Section("title", isExpanded: $binding) { ... }` inside a `Form { ... }.formStyle(.grouped)`
2. **DisclosureGroup-based** (used by Launcher, Input): `DisclosureGroup(isExpanded: $binding) { ... } label: { ... }` with custom label

For the DLL override editor and per-program settings, use the **Section-based** pattern for consistency with the majority of config sections. The DLL override table itself should use `Table` (already used in WinetricksView) for the structured editor.

### Anti-Patterns to Avoid

- **Mutating dictionary in-place across functions:** The current `environmentVariables(wineEnv: &result)` pattern spreads env construction across multiple methods with no clear ownership. EnvironmentBuilder centralizes this.
- **String-based WINEDLLOVERRIDES clobbering:** Current code sets `wineEnv["WINEDLLOVERRIDES"] = "dxgi,d3d9,d3d10core,d3d11=n,b"` which overwrites any existing value. The DLL override resolver composes per-DLL.
- **Optional-heavy Codable without `decodeIfPresent`:** All new Codable types MUST use `decodeIfPresent` with defaults in `init(from:)` for backward compatibility. The existing codebase does this consistently.
- **Bloating BottleSettings with new fields:** Use separate files/types (DLLOverride, WinetricksVerbCache) and only add necessary proxy properties to BottleSettings.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Plist serialization | Custom file format | PropertyListEncoder/Decoder | Already used throughout; backward-compatible |
| Environment key validation | Regex-based checking | `Wine.isValidEnvKey()` | Already exists and is well-tested |
| DLL override string parsing | Custom parser from WINEDLLOVERRIDES | Build structured model, render to string | Parsing is fragile; structured data is the source of truth |
| Winetricks verb discovery | Manual file parsing first | `winetricks list-installed` command first, log parsing as fallback | The tool is the authoritative source |

**Key insight:** The DLL override resolver should NEVER parse WINEDLLOVERRIDES strings from settings. Structured data (`[DLLOverrideEntry]`) is the source of truth. The string is only rendered at resolve time.

## Common Pitfalls

### Pitfall 1: Breaking the wineserver environment
**What goes wrong:** `constructWineServerEnvironment()` currently does NOT call `bottle.settings.environmentVariables()`. If EnvironmentBuilder replaces `constructWineEnvironment()` but wineserver continues using its separate function, the environments diverge.
**Why it happens:** Wineserver and wine processes historically had different env needs, but this is no longer true.
**How to avoid:** Both `runWineProcess` and `runWineserverProcess` should go through EnvironmentBuilder. The wineserver builder just skips program-specific layers.
**Warning signs:** Wineserver processes fail to find the correct prefix or have missing macOS compatibility fixes.

### Pitfall 2: WINEDLLOVERRIDES composition order
**What goes wrong:** DLL overrides from DXVK, launcher presets, and user entries must compose per-DLL with clear precedence. If the composition uses simple dictionary merge, a later layer with fewer DLLs could drop managed entries.
**Why it happens:** Dictionary merge replaces the entire value for the WINEDLLOVERRIDES key, not per-DLL.
**How to avoid:** DLL overrides must be treated as a dictionary of `[String: DLLOverrideMode]`, not as a string. The `DLLOverrideResolver` collects entries from all sources and renders the final string.
**Warning signs:** DXVK stops working when user adds a custom DLL override; user's custom override disappears when DXVK is toggled.

### Pitfall 3: Backward compatibility of ProgramSettings
**What goes wrong:** Existing program plist files don't have an `overrides` key. If `ProgramOverrides` is not Optional or doesn't use `decodeIfPresent`, existing settings will fail to decode.
**Why it happens:** Adding required fields to a Codable type breaks existing plists.
**How to avoid:** `ProgramSettings.overrides` is `ProgramOverrides?`, initialized to `nil`. `ProgramOverrides.init(from:)` uses `decodeIfPresent` for every field.
**Warning signs:** Programs lose their settings (arguments, environment) after upgrading.

### Pitfall 4: macOS 15.4 sync override conflict
**What goes wrong:** The platform layer currently forces `WINEESYNC=1` on macOS 15.4+, which overrides user's "none" sync choice. With the layer model, this becomes explicit: platform layer sets it, bottle_managed layer can override it.
**Why it happens:** The current code has `if MacOSVersion.current >= .sequoia15_4 { ... }` mixed into the same function as user settings.
**How to avoid:** Document that platform layer sets WINEESYNC=1 as a stability default. If bottle_managed layer sets enhancedSync = .none and macOS >= 15.4, the bottle_managed layer should still set WINEESYNC=1 (because it's required for stability) but the provenance data should note the conflict.
**Warning signs:** Users on macOS 15.4+ get unexpected sync behavior; test failures on different macOS versions.

### Pitfall 5: Thread safety with @MainActor Bottle
**What goes wrong:** EnvironmentBuilder needs data from `Bottle.settings` which is `@MainActor`. If EnvironmentBuilder is constructed off the main actor, it can't access bottle settings.
**Why it happens:** `Bottle` is `@MainActor` isolated; `EnvironmentBuilder` is `Sendable`.
**How to avoid:** Build the environment on `@MainActor` (where bottle settings are accessed), then pass the resolved `[String: String]` to the Process. This is already how the current code works -- `constructWineEnvironment()` is `@MainActor`.
**Warning signs:** Compiler errors about sending `@MainActor`-isolated values across boundaries.

### Pitfall 6: Winetricks subprocess hanging
**What goes wrong:** `winetricks list-installed` may hang or take very long if Wine isn't properly set up.
**Why it happens:** Winetricks internally starts Wine to query the prefix; if the prefix is corrupt or Wine is misconfigured, it can hang.
**How to avoid:** Run `winetricks list-installed` with a timeout (e.g., 30 seconds). Fall back to log parsing if the subprocess doesn't complete. Use `Process.terminationHandler` or async timeout.
**Warning signs:** WinetricksView shows a permanent spinner; UI hangs on verb tab switch.

## Code Examples

Verified patterns from the existing codebase:

### Current Environment Construction (to be refactored)
```swift
// Source: WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift
@MainActor
public static func constructWineEnvironment(
    for bottle: Bottle, environment: [String: String] = [:]
) -> [String: String] {
    var result: [String: String] = [
        "WINEPREFIX": bottle.url.path,
        "WINEDEBUG": "fixme-all",
        "GST_DEBUG": "1"
    ]
    applyMacOSCompatibilityFixes(to: &result)
    bottle.settings.environmentVariables(wineEnv: &result)
    // ... merge caller environment
    return result
}
```

### Current DXVK Override (flat string, will become structured)
```swift
// Source: WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift line 582
if dxvk {
    wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")
}
```

### Current Program Environment Generation
```swift
// Source: WhiskyKit/Sources/WhiskyKit/Whisky/Program.swift line 227
public func generateEnvironment() -> [String: String] {
    var environment = settings.environment
    if settings.locale != .auto {
        environment["LC_ALL"] = settings.locale.rawValue
    }
    return environment
}
```

### Config Section Pattern (for new DLL override UI)
```swift
// Source: Whisky/Views/Bottle/DXVKConfigSection.swift
struct DXVKConfigSection: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    var body: some View {
        Section("config.title.dxvk", isExpanded: $isExpanded) {
            Toggle(isOn: $bottle.settings.dxvk) { Text("config.dxvk") }
            // ...
        }
    }
}
```

### Codable with decodeIfPresent (backward-compatible pattern)
```swift
// Source: WhiskyKit/Sources/WhiskyKit/Whisky/BottleCleanupConfig.swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.clipboardPolicy = try container.decodeIfPresent(
        ClipboardPolicy.self, forKey: .clipboardPolicy
    ) ?? .auto
    self.killOnQuit = try container.decodeIfPresent(
        KillOnQuitPolicy.self, forKey: .killOnQuit
    ) ?? .inherit
}
```

### Table View Pattern (for DLL override editor)
```swift
// Source: Whisky/Views/Bottle/WinetricksView.swift
Table(category.verbs, selection: $selectedTrick) {
    TableColumn("winetricks.table.name", value: \.name)
    TableColumn("winetricks.table.description", value: \.description)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Mutable dict passed by inout reference | Will be: EnvironmentBuilder with layered accumulation | Phase 2 | All env construction goes through one path |
| WINEDLLOVERRIDES as flat string | Will be: DLLOverrideResolver with per-DLL structured entries | Phase 2 | Composable, inspectable DLL overrides |
| No per-program overrides | Will be: ProgramOverrides with Optional fields | Phase 2 | Programs can override DXVK, sync, etc. |
| No winetricks verb tracking | Will be: WinetricksVerbCache with staleness detection | Phase 2 | Users see which verbs are installed |

**Deprecated/outdated:**
- `BottleSettings.environmentVariables(wineEnv: &[String: String])` will be replaced by layer populator methods called from EnvironmentBuilder
- `Wine.constructWineEnvironment()` / `Wine.constructWineServerEnvironment()` will delegate to EnvironmentBuilder

## Open Questions

1. **Winetricks `list-installed` reliability**
   - What we know: The `winetricks` script supports `list-installed` which outputs installed verbs one per line. The script is bundled at `WhiskyWineInstaller.libraryFolder/winetricks`.
   - What's unclear: Whether `list-installed` works reliably in all cases (e.g., corrupted prefix, missing Wine binary). The script currently runs via Terminal AppleScript.
   - Recommendation: Run `list-installed` as a headless `Process` with a 30-second timeout, not through Terminal. Capture stdout directly. Fall back to log parsing if it fails. This can be tested during implementation.

2. **EnvironmentBuilder and generateRunCommand / generateTerminalEnvironmentCommand**
   - What we know: `Wine.generateRunCommand()` and `Wine.generateTerminalEnvironmentCommand()` both call `constructWineEnvironment()` to get the environment dict for shell command generation.
   - What's unclear: Whether these should also use EnvironmentBuilder or continue to call a simpler path.
   - Recommendation: Both should use EnvironmentBuilder for consistency. The generated shell command should reflect exactly what `runProgram` would use. This ensures "Run in Terminal" matches "Run" behavior.

3. **Bottle-level custom environment variables (bottle_user layer)**
   - What we know: Currently only programs have custom env vars (`ProgramSettings.environment`). Bottles do not have a custom env var editor.
   - What's unclear: Whether to add a bottle-level custom env var editor in Phase 2 or defer it.
   - Recommendation: The EnvironmentBuilder should have a `bottle_user` layer slot ready, but the UI for bottle-level custom env vars can be deferred. The existing program-level env vars naturally map to `program_user` layer. The `bottle_user` layer can initially be empty.

4. **DLL override presets beyond DXVK**
   - What we know: The CONTEXT.md says "add .NET/ClickOnce only if exact DLLs can be justified." ClickOnce applications use specific .NET runtime DLLs.
   - What's unclear: The exact DLL list for .NET/ClickOnce presets.
   - Recommendation: Start with DXVK preset only (`dxgi,d3d9,d3d10core,d3d11=n,b`). .NET/ClickOnce preset can be added later when DLL requirements are verified. The preset system is extensible.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` -- current environment construction
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` -- settings structure, environment variable generation, all 8 config sections
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramSettings.swift` -- current program settings model
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Wine/MacOSCompatibility.swift` -- platform-specific env fixes
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Wine/LauncherPresets.swift` -- launcher-specific env overrides
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Whisky/Program.swift` -- program launch flow, generateEnvironment()
- Codebase analysis: `WhiskyKit/Sources/WhiskyKit/Extensions/Program+Extensions.swift` -- launchWithUserMode, runInWine
- Codebase analysis: `Whisky/Utils/Winetricks.swift` -- current winetricks invocation, verb parsing
- Codebase analysis: `Whisky/Views/Bottle/WinetricksView.swift` -- current winetricks UI
- Codebase analysis: `Whisky/Views/Programs/EnvironmentArgView.swift` -- current env var editor pattern
- Codebase analysis: Config section views (DXVKConfigSection, PerformanceConfigSection, etc.) -- UI patterns
- Codebase analysis: `WhiskyKit/Tests/WhiskyKitTests/EnvironmentVariablesTests.swift` -- test patterns

### Secondary (MEDIUM confidence)
- Swift 6 concurrency model -- `Sendable` requirements for cross-actor data types
- PropertyListEncoder/Decoder backward compatibility -- adding optional fields does not break existing plists

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, pure Swift/SwiftUI
- Architecture: HIGH -- EnvironmentBuilder is a straightforward refactor of existing mutable-dict code into layered builder
- Data model: HIGH -- ProgramOverrides and DLLOverride follow established Codable patterns in the codebase
- Winetricks integration: MEDIUM -- `list-installed` behavior needs runtime verification, but fallback path (log parsing) is well-understood
- UI patterns: HIGH -- follows established Section/Table patterns from existing config views
- Pitfalls: HIGH -- identified from direct codebase analysis of conflict points

**Research date:** 2026-02-09
**Valid until:** 2026-03-11 (30 days -- stable domain, no external dependency changes expected)
