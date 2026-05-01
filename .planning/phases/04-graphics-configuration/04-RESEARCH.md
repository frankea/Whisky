# Phase 4: Graphics Configuration - Research

**Researched:** 2026-02-09
**Domain:** Wine graphics backend selection (D3DMetal/DXVK/wined3d), DXVK configuration, tiered settings UI
**Confidence:** HIGH

## Summary

Phase 4 adds a tiered Simple/Advanced graphics configuration UI to Whisky, introducing backend selection (D3DMetal, DXVK, wined3d, or Auto/Recommended) as a first-class concept alongside the existing DXVK and Metal settings. The implementation builds entirely on infrastructure created in Phases 2 and 3: the EnvironmentBuilder cascade, per-program override model (`ProgramOverrides`), and process tracking (`ProcessRegistry`/`Wine.isWineserverRunning`).

The core technical challenge is introducing a `GraphicsBackend` enum with an `.recommended` (Auto) case that resolves to a concrete backend at launch time based on GPU/OS heuristics, while storing the user's abstract choice (`.recommended`, `.d3dMetal`, `.dxvk`, `.wined3d`) in `BottleSettings`. This new backend concept must integrate with the existing DXVK toggle (which currently controls both DLL overrides and environment variables) and the `populateBottleManagedLayer` method that writes to the EnvironmentBuilder. The dxvk.conf file management is a filesystem operation (check existence, open in external editor, reset) with no inline editing required in Phase 4.

No external dependencies are needed. This is pure SwiftUI + WhiskyKit work using Foundation, Metal framework (for GPU capability detection), and existing codebase patterns.

**Primary recommendation:** Add `GraphicsBackend` enum to WhiskyKit with `.recommended` auto-resolution, refactor `BottleDXVKConfig` into a broader `BottleGraphicsConfig` (or extend it), integrate backend selection into `populateBottleManagedLayer` for environment variable emission, then build the tiered UI with a global Simple/Advanced `@AppStorage` toggle and selection card backend picker.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Simple/Advanced toggle**: Segmented control at top of Graphics section. Persisted as global (app-wide) user preference in UserDefaults via `@AppStorage`, not per-bottle. Stable layout with disclosure animation for Advanced controls. Simple mode shows: backend picker, Force DX11, Sequoia Compatibility Mode. Advanced mode reveals: DXVK async, HUD, dxvk.conf management, per-program overrides, and other granular settings. Badge "Advanced settings active" with jump link when bottle has advanced-only settings configured.
- **Backend picker**: Selection card control (2x2 grid or 1x4 on wide): Recommended (Auto), D3DMetal, DXVK, WineD3D. Each card shows icon + name, 1-line summary, optional tags. Recommended is a real Auto enum case (`backend = .recommended`) that resolves at launch via EnvironmentBuilder using GPU/OS heuristics. Helper text below grid showing resolved backend for Recommended, "Takes effect next launch" for manual choices. Optional "Why?" popover explaining auto-selection rationale. Resolved backend shown subtly in bottle header/info bar when Auto is selected.
- **Backend switching behavior**: Setting changes immediately, takes effect on next launch. No confirmation dialog. Warning banner if bottle has running processes with "Apply on next launch" (default) and "Stop Bottle Now..." options. Inline warning (not modal) if selecting incompatible backend. Never auto-relaunch programs.
- **DXVK settings**: First-class UI controls: Enable DXVK toggle, DXVK Async toggle, DXVK HUD preset picker (Off/FPS/Partial/Full). DXVK controls visible only when DXVK is active backend. Simple mode: show when backend is DXVK or Recommended->DXVK. Advanced mode: show collapsed "DXVK" section with "Inactive" note when another backend is active. No per-element HUD builder.
- **dxvk.conf file management (Advanced only)**: Show config file location. Actions: Open in Editor (NSWorkspace), Reveal in Finder, Reset/Delete. Optional "Apply preset" with known-safe snippet. No inline text editor in Phase 4.
- **Per-program graphics overrides**: Follow exact same inherit/override pattern from Phase 2 (02-04). Available in Advanced mode only. In Simple mode: show note "Per-program overrides active" with jump link if overrides exist. Override scope: full graphics settings (backend, dxvkEnabled, dxvkAsync, dxvkHud) -- each as optional nil = inherit. One "Override Graphics" toggle enables the group. "Takes effect next launch" note always shown. Programs with active graphics overrides show badge in program list.

### Claude's Discretion
- Exact selection card visual design and icon choices
- GPU detection heuristics for Recommended backend resolution
- Animation/transition details for Simple<->Advanced disclosure
- Specific summary text and tags on backend cards
- Layout of DXVK preset picker
- Badge design for "Advanced settings active" and program override indicators

### Deferred Ideas (OUT OF SCOPE)
- Custom per-element DXVK HUD builder -- future enhancement to Advanced mode
- Inline text editor for dxvk.conf -- future if demand warrants
- "Stop and relaunch last program" after backend switch -- future convenience feature
- Per-program dxvk.conf management -- consider in later phases if needed
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | macOS 15+ | PropertyListEncoder/Decoder, FileManager, NSWorkspace | Already used throughout WhiskyKit and Whisky app |
| SwiftUI | macOS 15+ | Form, Section, Picker, Toggle, segmented controls, selection cards | Already used for all config views |
| Metal | macOS 15+ | `MTLCreateSystemDefaultDevice()`, `supportsFamily(.apple9)` | Already used in MetalConfigSection.swift for GPU detection |
| os.log | macOS 15+ | Logger for launch logging and diagnostics | Already used via `Logger` throughout codebase |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| XCTest | Swift 6 | Unit tests for GraphicsBackend enum, resolution logic, EnvironmentBuilder integration | Required for data model validation |
| ProcessInfo | macOS 15+ | OS version detection via `MacOSVersion.current` | Already used for Sequoia compatibility checks |

### Alternatives Considered
No new external dependencies needed. All capabilities are provided by the existing stack.

**Installation:** No new packages required.

## Architecture Patterns

### Recommended File Structure

```
WhiskyKit/Sources/WhiskyKit/
  Whisky/
    BottleGraphicsConfig.swift       # NEW: GraphicsBackend enum + BottleGraphicsConfig struct
    BottleDXVKConfig.swift           # EXISTING: Keep as-is (DXVK-specific fields)
    BottleMetalConfig.swift          # EXISTING: Keep as-is (Metal-specific fields)
    BottleSettings.swift             # MODIFIED: Add graphicsConfig, backend property, update populateBottleManagedLayer
    ProgramOverrides.swift           # MODIFIED: Add graphicsBackend field
  Wine/
    GraphicsBackendResolver.swift    # NEW: Auto-resolution logic, GPU/OS heuristic
    EnvironmentBuilder.swift         # EXISTING: No changes needed
    WineEnvironment.swift            # MODIFIED: Pass backend context to applyProgramOverrides

WhiskyKit/Tests/WhiskyKitTests/
    GraphicsBackendTests.swift       # NEW: Enum serialization, resolution, env var emission
    GraphicsBackendResolverTests.swift # NEW: Heuristic resolution tests

Whisky/Views/Bottle/
    GraphicsConfigSection.swift      # NEW: Replaces/wraps DXVKConfigSection + MetalConfigSection
    BackendPickerView.swift          # NEW: Selection card grid for backend choice
    DXVKSettingsView.swift           # NEW: DXVK-specific controls (toggle, async, HUD, conf)
    ConfigView.swift                 # MODIFIED: Replace separate DXVK/Metal sections with unified GraphicsConfigSection
```

### Pattern 1: GraphicsBackend Enum with Auto Resolution

**What:** A `GraphicsBackend` enum with `.recommended`, `.d3dMetal`, `.dxvk`, `.wined3d` cases. The `.recommended` case stores the user's intent to defer to heuristic resolution. At launch time, `GraphicsBackendResolver.resolve()` maps `.recommended` to a concrete backend.

**When to use:** Backend selection at both bottle and program levels.

**Implementation notes:**

```swift
// In WhiskyKit/Sources/WhiskyKit/Whisky/BottleGraphicsConfig.swift
public enum GraphicsBackend: String, Codable, CaseIterable, Equatable, Sendable {
    case recommended  // Auto -- resolved at launch
    case d3dMetal     // Apple's D3DMetal translation
    case dxvk         // DXVK via MoltenVK/Vulkan
    case wined3d      // Wine's built-in OpenGL-based D3D
}

public struct BottleGraphicsConfig: Codable, Equatable {
    var backend: GraphicsBackend = .recommended

    public init() {}
    // Defensive decoding with defaults (matching existing config pattern)
}
```

**Critical implementation detail:** The existing `dxvk` Bool in `BottleDXVKConfig` controls both (a) whether DXVK DLL overrides are applied and (b) whether DXVK env vars like `DXVK_HUD` and `DXVK_ASYNC` are set. With the new backend picker, the DXVK toggle meaning changes: when `backend == .dxvk`, DXVK is implicitly enabled. The `dxvk` Bool in `BottleDXVKConfig` should be retained for backward compatibility but its role shifts to an internal derived state. The relationship:

- `backend == .dxvk` -> DXVK DLL overrides applied, DXVK env vars active
- `backend == .d3dMetal` -> No DXVK DLLs, D3DMetal env vars active
- `backend == .wined3d` -> No DXVK DLLs, `WINED3DMETAL=0` set (forces wined3d path)
- `backend == .recommended` -> Resolved to one of the above at launch

### Pattern 2: Environment Variable Emission per Backend

**What:** The `populateBottleManagedLayer` method in `BottleSettings` must emit different environment variables depending on the resolved backend.

**Environment variables by backend:**

| Backend | Key Environment Variables | DLL Overrides |
|---------|---------------------------|---------------|
| D3DMetal | (default -- no special vars needed, D3DMetal is Wine's default on macOS) | None |
| DXVK | `DXVK_ASYNC`, `DXVK_HUD`, `DXVK_CONFIG_FILE` | `dxgi,d3d9,d3d10core,d3d11=n,b` |
| wined3d | `WINED3DMETAL=0` (disables D3DMetal, falls back to wined3d OpenGL) | None |
| Recommended | Resolved to one of the above | Per resolved backend |

**Critical finding from codebase:** The current `populateBottleManagedLayer` emits DXVK env vars when `dxvk == true`. The new code should key off the resolved backend rather than the raw `dxvk` Bool. The existing DXVK DLL overrides flow through `DLLOverrideResolver` (Phase 2 infrastructure) which already supports managed overrides -- the backend selection should produce managed DLL overrides the same way.

### Pattern 3: Tiered UI with Global Simple/Advanced Preference

**What:** A single `@AppStorage("graphicsSettingsMode")` Bool or enum controlling whether Simple or Advanced controls are shown across all bottles. This matches the existing pattern of `@AppStorage` for section expansion state (e.g., `dxvkSectionExpanded`).

**Existing pattern from codebase:**
```swift
// ConfigView.swift -- existing @AppStorage pattern
@AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
@AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true
```

**New global preference:**
```swift
@AppStorage("graphicsAdvancedMode") private var graphicsAdvancedMode: Bool = false
```

**Layout structure:**
```
Graphics Section (always visible)
├── [Simple | Advanced] segmented control
├── Backend Picker (selection cards) -- always visible
├── Force DX11 toggle -- always visible (Simple + Advanced)
├── Sequoia Compatibility Mode toggle -- always visible (if macOS 15+)
│
├── [Advanced only] DXVK Settings subsection
│   ├── DXVK Async toggle
│   ├── DXVK HUD preset picker
│   └── dxvk.conf management (Open, Reveal, Reset)
│
├── [Advanced only] Metal Settings subsection
│   ├── Metal HUD toggle
│   ├── Metal Trace toggle
│   ├── DXR toggle (if GPU supports it)
│   └── Metal Validation toggle
│
└── [Advanced only] Per-program overrides note/link
```

### Pattern 4: Per-Program Graphics Override (extends Phase 2 pattern)

**What:** Extends the existing `ProgramOverrides` struct (from Phase 2) with a `graphicsBackend: GraphicsBackend?` field. Follows the identical inherit/override toggle pattern already established in `ProgramOverrideSettingsView`.

**Existing pattern from codebase:**
```swift
// ProgramOverrides.swift -- existing pattern (nil = inherit from bottle)
public var dxvk: Bool?
public var dxvkAsync: Bool?
public var dxvkHud: DXVKHUD?
```

**Extension:**
```swift
// Add to ProgramOverrides
public var graphicsBackend: GraphicsBackend?  // nil = inherit from bottle
```

**The existing `applyProgramOverrides` in `WineEnvironment.swift` already handles per-program DXVK overrides.** The new `graphicsBackend` override needs to be wired into this method so that a program-level backend choice overrides the bottle-level choice before environment variables are emitted.

### Pattern 5: Backend Selection Card View

**What:** A custom SwiftUI view displaying backend options as tappable cards rather than a standard Picker. Each card shows an icon, name, short description, and optional tags.

**Implementation approach:** Use a `LazyVGrid` with 2 columns (or 4 on wide) containing `Button` views styled as selection cards with a `.selected` state indicated by border/background highlight.

**SwiftUI pattern:**
```swift
struct BackendPickerView: View {
    @Binding var selection: GraphicsBackend
    let resolvedBackend: GraphicsBackend  // For displaying "Currently: D3DMetal" under Recommended

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                BackendCard(
                    backend: backend,
                    isSelected: selection == backend,
                    resolvedBackend: backend == .recommended ? resolvedBackend : nil
                ) {
                    selection = backend
                }
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Coupling DXVK toggle to backend picker:** The `dxvk` Bool must NOT be independently toggleable when a backend picker exists. If `backend == .dxvk`, DXVK is on. If `backend == .d3dMetal`, DXVK is off. The old `dxvk` Bool becomes derived state. Allowing both creates contradictory states.
- **Resolving `.recommended` at settings-save time:** The resolution must happen at launch time (in `constructWineEnvironment`) not when the user picks "Recommended." This ensures the resolution uses the latest GPU/OS state.
- **Modal dialogs for backend switching:** Per locked decision, no confirmation dialog. Use inline warnings only.
- **Inline dxvk.conf editing:** Per locked decision and deferred ideas, use `NSWorkspace.shared.open(url)` for external editor only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GPU capability detection | Custom IOKit GPU enumeration | `MTLCreateSystemDefaultDevice()` + `device.supportsFamily()` | Already used in MetalConfigSection.swift; reliable on Apple Silicon |
| macOS version detection | Custom sysctl calls | `MacOSVersion.current` (existing utility) | Already implemented and tested in MacOSCompatibility.swift |
| Environment variable cascade | Direct dict mutation | `EnvironmentBuilder` layers (Phase 2) | Avoids the exact override-conflict pitfall documented in PITFALLS.md #5 |
| DLL override composition | String concatenation for WINEDLLOVERRIDES | `DLLOverrideResolver` (Phase 2) | Handles managed vs custom, per-DLL precedence, and warnings |
| Per-program override UI | New inherit/override mechanism | Existing `ProgramOverrideSettingsView` pattern | Copy-on-enable, nil-check state, and reset are already proven |
| Process running detection | Custom process scanning | `ProcessRegistry.shared.getProcessCount(for:)` + `Wine.isWineserverRunning(for:)` | Phase 3 infrastructure, already used in Bottle+Extensions.swift |
| File operations (dxvk.conf) | Custom file editor | `NSWorkspace.shared.open(url)` for editing, `FileManager` for existence/delete | Standard macOS APIs, keeps scope minimal |

**Key insight:** Phase 2 and Phase 3 invested heavily in infrastructure (EnvironmentBuilder, DLLOverrideResolver, ProgramOverrides, ProcessRegistry) specifically to support this phase. Using that infrastructure avoids duplicating logic and ensures consistency.

## Common Pitfalls

### Pitfall 1: Contradictory DXVK Toggle and Backend Selection

**What goes wrong:** The existing `dxvk` Bool in `BottleDXVKConfig` can be `true` while the new backend is `.d3dMetal`, creating a contradictory state where DXVK DLL overrides are applied but D3DMetal environment variables are also set. This causes undefined behavior at runtime.

**Why it happens:** The current codebase treats DXVK as an independent toggle (`bottle.settings.dxvk`). The new backend picker introduces a higher-level concept that subsumes the DXVK toggle. If both coexist as independent settings, they will conflict.

**How to avoid:**
- Make the backend picker authoritative. The `dxvk` Bool in `BottleDXVKConfig` should become derived from `backend == .dxvk` for environment variable emission purposes.
- For backward compatibility, existing bottles with `dxvk == true` and no `graphicsConfig.backend` should default to `backend = .dxvk`.
- The `populateBottleManagedLayer` method should check the resolved backend, not the raw `dxvk` Bool, when deciding whether to emit DXVK environment variables.

**Warning signs:** Users seeing DXVK HUD overlay when they selected D3DMetal backend, or D3DMetal rendering when they selected DXVK.

### Pitfall 2: Settings File Migration Breaking Existing Bottles

**What goes wrong:** Adding `BottleGraphicsConfig` to `BottleSettings` changes the plist schema. Existing bottles that don't have this key fail to decode, or silently lose their existing DXVK settings.

**Why it happens:** `BottleSettings.init(from decoder:)` uses `decodeIfPresent` with fallback defaults for all config groups. A new `graphicsConfig` key will default to `BottleGraphicsConfig()` which has `backend = .recommended`. But the user may have had `dxvk = true` in their old settings, which should map to `backend = .dxvk`.

**How to avoid:**
- In the `BottleSettings.init(from decoder:)`, after decoding both `dxvkConfig` and `graphicsConfig`, check: if `graphicsConfig` was not present in the plist (newly migrated) AND `dxvkConfig.dxvk == true`, then set `graphicsConfig.backend = .dxvk`.
- Add a unit test that decodes an old-format plist (without graphicsConfig) with dxvk=true and verifies the migration logic.

**Warning signs:** Users upgrading and finding their DXVK bottles suddenly running on D3DMetal.

### Pitfall 3: Recommended Backend Resolution Changing Between Launches

**What goes wrong:** A user selects "Recommended" and their game works with D3DMetal. They update macOS, and "Recommended" now resolves to a different backend, breaking their game.

**Why it happens:** The Auto/Recommended resolution is inherently dynamic -- it depends on GPU family and OS version. If the heuristic changes (or if we update it in a Whisky update), the resolved backend changes silently.

**How to avoid:**
- Show the resolved backend prominently: "Recommended (currently: D3DMetal)" so users know what they're getting.
- Include the "Why?" popover that explains the current rationale.
- Consider logging the resolved backend at launch time (already partially done via `logLaunchSummary`).
- Keep the heuristic stable -- prefer D3DMetal as the default on macOS 15+ with Apple Silicon unless there's a strong reason to change.

**Warning signs:** Support reports where users say "it worked before the update" but they had "Recommended" selected.

### Pitfall 4: dxvk.conf File Location Confusion

**What goes wrong:** DXVK searches for `dxvk.conf` in multiple locations with a priority order. The UI shows one location but DXVK reads from another.

**Why it happens:** DXVK's search order for config files is: (1) `DXVK_CONFIG_FILE` env var, (2) working directory of the executable, (3) next to the DXVK DLL. Whisky should standardize on one location and set `DXVK_CONFIG_FILE` explicitly.

**How to avoid:**
- Store `dxvk.conf` at a well-known bottle-level path: `<bottle>/dxvk.conf` (next to Metadata.plist).
- Always set `DXVK_CONFIG_FILE=<bottle>/dxvk.conf` in the `bottleManaged` layer when DXVK is the active backend.
- The UI should show and manage only this canonical location.

**Warning signs:** Users editing the wrong dxvk.conf and seeing no effect.

### Pitfall 5: Running Process Warning Without Actual Danger

**What goes wrong:** The warning banner "Bottle has running processes" appears for every backend change, even though the change is completely safe (takes effect next launch only). Users become anxious or confused.

**Why it happens:** The "Stop Bottle Now..." option implies danger that doesn't exist for a settings-only change.

**How to avoid:**
- Make the default action prominent: "Apply on next launch" should be the clear default, not "Stop Bottle Now..."
- The warning should be informational, not alarming: "Changes will take effect when you next launch a program. Running programs are not affected."
- Only show the warning when there ARE running processes (check `ProcessRegistry.shared.getProcessCount(for:)` and/or `Wine.isWineserverRunning(for:)`).

## Code Examples

### Example 1: GraphicsBackend Enum Definition

```swift
// Source: Follows existing enum patterns from BottleDXVKConfig.swift (DXVKHUD)
// and BottlePerformanceConfig.swift (PerformancePreset)

public enum GraphicsBackend: String, Codable, CaseIterable, Equatable, Sendable {
    case recommended  // Auto - resolved at launch via GPU/OS heuristics
    case d3dMetal     // Apple's D3DMetal (Wine's default on macOS)
    case dxvk         // DXVK (Direct3D to Vulkan via MoltenVK)
    case wined3d      // Wine's built-in OpenGL-based D3D translation

    /// Human-readable display name for the backend
    public var displayName: String {
        switch self {
        case .recommended: String(localized: "config.graphics.backend.recommended")
        case .d3dMetal: "D3DMetal"
        case .dxvk: "DXVK"
        case .wined3d: "WineD3D"
        }
    }

    /// Short description for selection card
    public var summary: String {
        switch self {
        case .recommended: String(localized: "config.graphics.backend.recommended.summary")
        case .d3dMetal: String(localized: "config.graphics.backend.d3dmetal.summary")
        case .dxvk: String(localized: "config.graphics.backend.dxvk.summary")
        case .wined3d: String(localized: "config.graphics.backend.wined3d.summary")
        }
    }
}
```

### Example 2: Backend Resolution Logic

```swift
// Source: Follows existing patterns from MacOSCompatibility.swift (version checks)
// and MetalConfigSection.swift (GPU family detection)

public enum GraphicsBackendResolver {
    /// Resolves .recommended to a concrete backend based on current system state.
    /// Called at launch time in constructWineEnvironment, NOT at settings-save time.
    public static func resolve(
        macOSVersion: MacOSVersion = .current
    ) -> GraphicsBackend {
        // D3DMetal is the default and best-supported path on macOS 15+ with Apple Silicon.
        // Apple actively maintains it as part of Game Porting Toolkit.
        // DXVK requires MoltenVK Vulkan translation which adds overhead.
        // wined3d is the fallback for compatibility only.
        return .d3dMetal
    }

    /// Returns a human-readable explanation of why the current resolution was chosen.
    public static func rationale(
        macOSVersion: MacOSVersion = .current
    ) -> String {
        // "D3DMetal provides the best performance on macOS 15 with Apple Silicon."
        String(localized: "config.graphics.backend.recommended.rationale.d3dmetal")
    }
}
```

### Example 3: Environment Variable Emission by Backend

```swift
// Source: Extends existing pattern from BottleSettings.populateBottleManagedLayer()

// Inside populateBottleManagedLayer, replace the current "if dxvk { ... }" block:
let resolvedBackend: GraphicsBackend
if graphicsBackend == .recommended {
    resolvedBackend = GraphicsBackendResolver.resolve()
} else {
    resolvedBackend = graphicsBackend
}

switch resolvedBackend {
case .d3dMetal, .recommended:
    // D3DMetal is Wine's default on macOS -- no special env vars needed
    // Ensure WINED3DMETAL is NOT set to 0
    break

case .dxvk:
    // DXVK: apply DLL overrides and env vars
    for entry in DLLOverrideResolver.dxvkPreset {
        managedDLLOverrides.append((entry: entry, source: .dxvk))
    }
    if dxvkAsync {
        builder.set("DXVK_ASYNC", "1", layer: .bottleManaged)
    }
    switch dxvkHud {
    case .full:  builder.set("DXVK_HUD", "full", layer: .bottleManaged)
    case .partial: builder.set("DXVK_HUD", "devinfo,fps,frametimes", layer: .bottleManaged)
    case .fps:   builder.set("DXVK_HUD", "fps", layer: .bottleManaged)
    case .off:   break
    }
    // Set dxvk.conf path if file exists
    let confPath = bottleURL.appending(path: "dxvk.conf")
    if FileManager.default.fileExists(atPath: confPath.path(percentEncoded: false)) {
        builder.set("DXVK_CONFIG_FILE", confPath.path, layer: .bottleManaged)
    }

case .wined3d:
    // Disable D3DMetal, forcing Wine's OpenGL-based wined3d path
    builder.set("WINED3DMETAL", "0", layer: .bottleManaged)
}
```

### Example 4: Backward-Compatible Settings Migration

```swift
// Source: Follows existing pattern from BottleSettings.init(from decoder:)

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... existing decoding ...
    self.graphicsConfig = try container.decodeIfPresent(
        BottleGraphicsConfig.self, forKey: .graphicsConfig
    ) ?? BottleGraphicsConfig()
    self.dxvkConfig = try container.decodeIfPresent(
        BottleDXVKConfig.self, forKey: .dxvkConfig
    ) ?? BottleDXVKConfig()

    // Migration: if graphicsConfig was absent (old bottle) and DXVK was enabled,
    // preserve the user's DXVK choice in the new backend picker
    if !container.contains(.graphicsConfig) && self.dxvkConfig.dxvk {
        self.graphicsConfig.backend = .dxvk
    }
}
```

### Example 5: Simple/Advanced Toggle with Conditional Content

```swift
// Source: Follows existing Section(isExpanded:) pattern from ConfigView.swift

struct GraphicsConfigSection: View {
    @ObservedObject var bottle: Bottle
    @AppStorage("graphicsAdvancedMode") private var advancedMode: Bool = false

    var body: some View {
        Section("config.title.graphics") {
            // Simple/Advanced segmented control
            Picker("", selection: $advancedMode) {
                Text("config.graphics.simple").tag(false)
                Text("config.graphics.advanced").tag(true)
            }
            .pickerStyle(.segmented)

            // Backend picker -- always visible
            BackendPickerView(
                selection: $bottle.settings.graphicsBackend,
                resolvedBackend: GraphicsBackendResolver.resolve()
            )

            // Simple mode controls
            Toggle(isOn: $bottle.settings.forceD3D11) {
                Text("config.forceD3D11")
            }

            // Sequoia Compatibility Mode (macOS 15+)
            Toggle(isOn: $bottle.settings.sequoiaCompatMode) {
                Text("config.sequoiaCompat")
            }

            // Advanced settings badge in Simple mode
            if !advancedMode && hasAdvancedSettingsConfigured {
                HStack {
                    Image(systemName: "gearshape.2")
                        .foregroundStyle(.secondary)
                    Text("config.graphics.advancedActive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("config.graphics.showAdvanced") {
                        advancedMode = true
                    }
                    .font(.caption)
                }
            }

            // Advanced mode content
            if advancedMode {
                DXVKSettingsView(bottle: bottle)
                MetalSettingsView(bottle: bottle)
                // dxvk.conf management, per-program override link, etc.
            }
        }
    }
}
```

### Example 6: Running Process Warning Banner

```swift
// Source: Uses ProcessRegistry (Phase 3) and async Wine.isWineserverRunning

// Inside GraphicsConfigSection or BackendPickerView
@State private var hasRunningProcesses: Bool = false

.task {
    let wineserverActive = await Wine.isWineserverRunning(for: bottle)
    let trackedCount = ProcessRegistry.shared.getProcessCount(for: bottle)
    hasRunningProcesses = wineserverActive || trackedCount > 0
}

// Show inline warning when processes are running
if hasRunningProcesses {
    HStack {
        Image(systemName: "info.circle")
            .foregroundStyle(.blue)
        Text("config.graphics.nextLaunch")
            .font(.caption)
        Spacer()
        Button("config.graphics.stopBottle") {
            Wine.killBottle(bottle: bottle)
        }
        .font(.caption)
        .foregroundStyle(.red)
    }
    .padding(8)
    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
}
```

### Example 7: dxvk.conf File Management

```swift
// Source: Standard NSWorkspace + FileManager patterns

struct DXVKConfManagement: View {
    let bottle: Bottle

    private var confURL: URL {
        bottle.url.appending(path: "dxvk.conf")
    }

    private var confExists: Bool {
        FileManager.default.fileExists(atPath: confURL.path(percentEncoded: false))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("config.dxvk.confFile")
                    .font(.caption)
                Spacer()
                Text(confExists ? confURL.lastPathComponent : "Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("config.dxvk.openInEditor") {
                    if confExists {
                        NSWorkspace.shared.open(confURL)
                    } else {
                        // Create with default content, then open
                        createDefaultConf()
                        NSWorkspace.shared.open(confURL)
                    }
                }

                Button("config.dxvk.revealInFinder") {
                    if confExists {
                        NSWorkspace.shared.activateFileViewerSelecting([confURL])
                    }
                }
                .disabled(!confExists)

                Button("config.dxvk.reset", role: .destructive) {
                    try? FileManager.default.removeItem(at: confURL)
                }
                .disabled(!confExists)
            }
        }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Independent DXVK toggle only | Backend picker (D3DMetal/DXVK/wined3d/Auto) | Phase 4 (this work) | Backend selection becomes first-class concept |
| All settings flat in one view | Tiered Simple/Advanced UI | Phase 4 (this work) | Reduces cognitive overload for casual users |
| No per-program backend override | Full per-program graphics override via ProgramOverrides | Phase 4 (this work) | Addresses upstream #600 (DXVK vs D3DMetal per-game) |
| DXVK env vars always emitted when toggle on | Backend-conditional env var emission | Phase 4 (this work) | Eliminates D3DMetal+DXVK contradiction |

**Deprecated/outdated:**
- The `dxvk` Bool in `BottleDXVKConfig` will still exist for serialization but its role as the primary DXVK control shifts to the `graphicsBackend` enum. Direct reads of `bottle.settings.dxvk` for environment variable logic should be replaced with resolved backend checks.

## Open Questions

1. **WINED3DMETAL environment variable name and behavior**
   - What we know: Research documents reference `WINED3DMETAL=0` to disable D3DMetal. This is consistent with Wine environment variable naming patterns.
   - What's unclear: Exact behavior of `WINED3DMETAL=0` with the specific WhiskyWine build (Wine 11 + D3DMetal patches). Whether additional variables are needed for a clean wined3d fallback.
   - Recommendation: Test `WINED3DMETAL=0` with the bundled WhiskyWine build. If it doesn't work, check for `D3DM_DISABLE` or similar. The planner should include a verification step that tests backend switching with the actual Wine binary.

2. **Recommended backend resolution heuristic complexity**
   - What we know: D3DMetal is the primary and best-supported path on macOS 15+ Apple Silicon. DXVK might be preferred for specific GPU families or older macOS versions.
   - What's unclear: Whether there are real cases where Recommended should resolve to anything other than D3DMetal on the current supported hardware (Apple Silicon + macOS 15+).
   - Recommendation: Start with a simple heuristic that always returns `.d3dMetal` on the supported platform. The resolver architecture allows future sophistication without changing the UI or data model.

3. **Interaction between Sequoia Compatibility Mode and backend selection**
   - What we know: `sequoiaCompatMode` sets `MTL_DEBUG_LAYER=0`, `D3DM_VALIDATION=0`, and `WINEFSYNC=0`. These are D3DMetal-specific. When backend is wined3d, these are irrelevant.
   - What's unclear: Whether `sequoiaCompatMode` should be automatically disabled when wined3d is selected, or just documented as D3DMetal-specific.
   - Recommendation: Keep it visible in Simple mode regardless of backend (it may affect other Metal operations). Add a note "(D3DMetal only)" to the toggle when wined3d is active.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** - Direct reading of all configuration types, view files, and environment building infrastructure:
  - `WhiskyKit/Sources/WhiskyKit/Whisky/BottleDXVKConfig.swift` -- DXVK config model
  - `WhiskyKit/Sources/WhiskyKit/Whisky/BottleMetalConfig.swift` -- Metal config model
  - `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` -- Settings facade with `populateBottleManagedLayer`
  - `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift` -- Per-program override model
  - `WhiskyKit/Sources/WhiskyKit/Wine/EnvironmentBuilder.swift` -- Layer-based env var cascade
  - `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` -- `constructWineEnvironment` and `applyProgramOverrides`
  - `WhiskyKit/Sources/WhiskyKit/Wine/GPUDetection.swift` -- GPU spoofing utilities
  - `WhiskyKit/Sources/WhiskyKit/Wine/MacOSCompatibility.swift` -- `MacOSVersion` struct
  - `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift` -- `runProgram`, `enableDXVK`
  - `WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift` -- Process tracking
  - `Whisky/Views/Bottle/ConfigView.swift` -- Current config view structure
  - `Whisky/Views/Bottle/DXVKConfigSection.swift` -- Current DXVK UI
  - `Whisky/Views/Bottle/MetalConfigSection.swift` -- Current Metal UI
  - `Whisky/Views/Bottle/PerformanceConfigSection.swift` -- Preset pattern reference
  - `Whisky/Views/Programs/ProgramOverrideSettingsView.swift` -- Inherit/override UI pattern
  - `Whisky/Views/Programs/ProgramView.swift` -- Program view structure

### Secondary (MEDIUM confidence)
- `.planning/phases/02-configuration-foundation/02-04-PLAN.md` -- Phase 2 per-program override pattern
- `.planning/phases/02-configuration-foundation/02-04-SUMMARY.md` -- Phase 2 completion status
- `.planning/research/FEATURES.md` -- Feature research with WINED3DMETAL references
- `.planning/research/PITFALLS.md` -- Pitfall 4 (settings explosion) and Pitfall 5 (env var conflicts)
- `.planning/ROADMAP.md` -- Phase dependency chain

### Tertiary (LOW confidence)
- `WINED3DMETAL=0` environment variable behavior with WhiskyWine build -- referenced in research docs but not verified against actual binary. Flag for validation during implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all capabilities from existing codebase, no new dependencies
- Architecture: HIGH -- patterns directly extend proven Phase 2 infrastructure
- Pitfalls: HIGH -- identified from actual codebase analysis and existing pitfall documentation
- Backend resolution heuristics: MEDIUM -- D3DMetal default is well-justified but edge cases are unclear
- WINED3DMETAL env var: MEDIUM -- documented in research but not runtime-verified

**Research date:** 2026-02-09
**Valid until:** 2026-03-11 (30 days -- stable domain, no fast-moving external dependencies)
