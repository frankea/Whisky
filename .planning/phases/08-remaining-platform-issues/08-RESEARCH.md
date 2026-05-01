# Phase 8: Remaining Platform Issues - Research

**Researched:** 2026-02-10
**Domain:** Launcher compatibility, game controller input, dependency installation, platform detection
**Confidence:** HIGH

## Summary

Phase 8 extends four major subsystems of the Whisky codebase: launcher workarounds (already well-scaffolded by `LauncherPresets`, `LauncherDetection`, `MacOSCompatibility`, and `EnvironmentBuilder`), controller input (currently limited to SDL env-var toggles in `BottleInputConfig`), dependency tracking (with `WinetricksVerbCache` and `Winetricks+InstalledVerbs` already providing the detection foundation), and diagnostics integration (where the Phase 5 `CrashClassifier`/`RemediationAction` pipeline is ready to accept new pattern categories).

The codebase is well-structured for this phase. The `EnvironmentBuilder` cascade (base -> platform -> bottleManaged -> launcherManaged -> bottleUser -> programUser -> featureRuntime -> callsiteOverride) means launcher and controller fixes layer cleanly. The `ProgramOverrides` inherit/override pattern already handles input settings. The `StatusToast` and `ToastModifier` provide the notification primitives needed for banners. The `DiagnosticExporter`, `CrashPattern`, and `RemediationAction` types define the schema for adding new diagnostic findings.

**Primary recommendation:** Build each subsystem (launcher guidance, controller panel, dependency tracking, Steam stall detection, volume access) as an independent vertical slice, since they share infrastructure but not state. Wire them together through the existing diagnostics pipeline at the end.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Three-tier launcher discovery model: (1) launch-time banner/toast, (2) Bottle Config Launcher section as source of truth, (3) Diagnostics remediation cards with deep-links
- No separate "launcher fixes screen" -- workarounds surface at launch time, in Config, or in Diagnostics
- All 7 existing LauncherType entries are first-class; everything else gets generic Chromium/CEF/macOS-compat fixes
- Mostly automatic for reversible env/settings; user-confirmed for prefix/file changes or process stops
- Managed version-gated fixes in MacOSCompatibility layer, keyed by MacOSVersion ranges
- Bottle-level Controllers section (InputConfigSection) as primary location; per-program overrides via ProgramOverrides
- Connected Controllers subpanel (collapsed by default) showing: name + type badge, connection badge, battery, status
- Minimal mapping in Phase 8: existing compatibility toggles only (HIDAPI off, background events, native labels); simple "Treat as XInput" vs "Native labels" choice via SDL hints
- Persist settings only, not device identity; lightweight recent history for diagnostics/export
- Dependencies section in bottle Config showing 3-5 named components with status/refresh/install/details
- Tiered detection: (1) winetricks list-installed, (2) WinetricksCache.plist, (3) winetricks.log parse, (4) DLL/registry probes labeled "Detected (heuristic)"
- Guided install sheet with sections: What/Preflight/Plan/Run/Verify; never silently install; run winetricks headlessly via Process
- Recommend only with high-confidence signals; track dismiss per program/bottle
- Steam stall detection gated on detected launcher + steamapps/downloading/* subdirs; sample every 30-60s
- Default passive alert stance; push alert only on high confidence; rate-limited once per bottle per session
- Run winetricks headlessly via Process (not Terminal) to reduce permission prompts; copy installers into prefix or managed temp dir
- Steam stall detection emits diagnostic finding in Phase 5 pipeline (category: networkingLaunchers)

### Claude's Discretion
- Exact sampling intervals and stall thresholds for download detection
- Controller subpanel layout and collapse behavior
- Dependency section ordering and component grouping
- Banner/toast animation and positioning details
- Preflight check implementation for dependency installer
- SDL hint mapping for XInput vs Native labels

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 15+ | All UI views | Project standard |
| GameController.framework | macOS 15+ | Controller discovery, battery, type badges | Apple's official controller API |
| Foundation/Process | macOS 15+ | Headless winetricks execution | Already used by `Winetricks+InstalledVerbs` |
| os.log / Logger | macOS 15+ | Structured logging | Project standard |
| WhiskyKit | local | Core models, diagnostics, config types | Project standard |

### Supporting (Already in Project)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `EnvironmentBuilder` | local | Layered env var cascade with provenance | All launcher/controller env var changes |
| `CrashClassifier` + `PatternLoader` | local | Diagnostics pipeline | Steam stall findings, dependency recommendations |
| `WinetricksVerbCache` | local | Cached installed verb tracking | Dependency status display |
| `StatusToast` + `ToastModifier` | local | Non-blocking notifications | Launch-time banners, stall alerts |
| `RemediationCardView` | local | Diagnostics fix cards | Dependency/launcher remediation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `GCController` | Raw IOKit HID | GCController is higher-level and gives type/battery for free; IOKit only needed for unsupported controllers |
| `DispatchSourceFileSystemObject` | Timer-based polling | Timer polling is simpler for sampling steamapps/downloading dirs; DSFSO would need a watcher per subdirectory |
| NSOpenPanel + Security-Scoped Bookmarks | Raw file access | Security-scoped bookmarks persist access across launches; essential for external volumes |

**No new external dependencies required.** Everything builds on existing project infrastructure.

## Architecture Patterns

### Recommended Project Structure
```
WhiskyKit/Sources/WhiskyKit/
  Wine/
    LauncherPresets.swift          # EXTEND: add version-gated fixes, provenance descriptions
    MacOSCompatibility.swift       # EXTEND: version-scoped fix registry
    EnvironmentBuilder.swift       # EXISTING: no changes needed
  Whisky/
    BottleInputConfig.swift        # EXTEND: add SDL_HINT_GAMECONTROLLER_TYPE hint
    BottleLauncherConfig.swift     # EXISTING: already supports all needed fields
    BottleDependencyConfig.swift   # NEW: dependency status model (installed/missing/unknown)
  Diagnostics/
    CrashPattern.swift             # EXISTING
    Resources/patterns.json        # EXTEND: add steam-stall and dependency patterns
    Resources/remediations.json    # EXTEND: add stall and dependency remediations
  GameDatabase/
    GameConfigApplicator.swift     # EXTEND: preflight dependency check

Whisky/
  Utils/
    LauncherDetection.swift        # EXISTING: already comprehensive
    Winetricks.swift               # REFACTOR: extract headless execution from Terminal
    Winetricks+InstalledVerbs.swift # EXISTING: already has headless list-installed
    ControllerMonitor.swift        # NEW: GCController wrapper for discovery/status
    SteamDownloadMonitor.swift     # NEW: steamapps/downloading stall detector
    DependencyManager.swift        # NEW: orchestrates detection + guided install
  Views/
    Bottle/
      InputConfigSection.swift     # EXTEND: add Connected Controllers subpanel
      LauncherConfigSection.swift  # EXTEND: add provenance display, fix summary banner
      DependencyConfigSection.swift # NEW: dependencies UI with status rows
    Common/
      StatusToast.swift            # EXTEND: add .warning style for stall alerts
      LaunchTimeBanner.swift       # NEW: "Fixes applied" notification at launch time
    Diagnostics/
      RemediationCardView.swift    # EXISTING: works for dependency remediations
    Programs/
      ProgramOverrideSettingsView.swift # EXTEND: dependency badges
    Install/
      DependencyInstallSheet.swift # NEW: guided install flow
```

### Pattern 1: Launch-Time Banner via Toast Extension
**What:** Extend the existing `StatusToast`/`ToastModifier` system to show what launcher fixes were applied at launch time.
**When to use:** After `LauncherDetection.detectAndApplyLauncherFixes()` returns true.
**Example:**
```swift
// Source: Existing StatusToast pattern from Whisky/Views/Common/StatusToast.swift
enum ToastStyle: Equatable {
    case success
    case error
    case info
    case launcherFixes  // NEW: amber/orange style for "fixes applied"
    // ...
}

// At launch site, after detection:
let fixesSummary = launcher.fixesDescription
toast = ToastData(
    message: "Launcher fixes applied: \(launcher.displayName)",
    style: .launcherFixes,
    autoDismiss: true
)
```

### Pattern 2: EnvironmentBuilder Provenance Display
**What:** Surface the `EnvironmentProvenance` metadata in UI to show users where each env var came from.
**When to use:** In the Launcher Config section, showing "Applied because macOS >= 15.4" or "Applied by Steam preset".
**Example:**
```swift
// Source: Existing EnvironmentBuilder from WhiskyKit/Wine/EnvironmentBuilder.swift
let (environment, provenance) = builder.resolve()
// Display in Config UI:
for (key, entry) in provenance.entries {
    HStack {
        Text(key)
        Spacer()
        Text(layerDescription(entry.layer))
            .foregroundStyle(.secondary)
    }
}
```

### Pattern 3: GCController Discovery for Connected Controllers Panel
**What:** Use Apple's GameController framework to list connected controllers with type, connection, and battery info.
**When to use:** In the InputConfigSection's Connected Controllers subpanel.
**Example:**
```swift
// Source: Apple GameController framework documentation
import GameController

class ControllerMonitor: ObservableObject {
    @Published var controllers: [ControllerInfo] = []

    func startMonitoring() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }

        refresh()
    }

    func refresh() {
        controllers = GCController.controllers().map { controller in
            ControllerInfo(
                name: controller.vendorName ?? "Unknown Controller",
                productCategory: controller.productCategory,
                batteryLevel: controller.battery?.batteryLevel,
                batteryState: controller.battery?.batteryState,
                isAttachedToDevice: controller.isAttachedToDevice
            )
        }
    }
}
```

### Pattern 4: Headless Winetricks Execution via Process
**What:** Run winetricks verb installation as a headless `Process` instead of via Terminal AppleScript.
**When to use:** For all dependency installations in Phase 8 (guided install sheet).
**Example:**
```swift
// Source: Existing pattern from Winetricks+InstalledVerbs.swift line 46-88
// The listInstalledVerbs method already demonstrates headless Process execution.
// Extend this pattern for verb installation:
static func installVerb(
    _ verb: String,
    for bottle: Bottle
) -> AsyncStream<WinetricksProgress> {
    AsyncStream { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", winetricksURL.path(percentEncoded: false), verb]
        process.environment = buildWinetricksEnvironment(for: bottle)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Stream progress updates
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8) {
                continuation.yield(.output(line))
            }
        }

        process.terminationHandler = { proc in
            continuation.yield(.completed(exitCode: proc.terminationStatus))
            continuation.finish()
        }

        try? process.run()
    }
}
```

### Pattern 5: Steam Download Stall Detection via Polling
**What:** Periodically sample `steamapps/downloading/` subdirectory mtimes to detect stalled downloads.
**When to use:** When Steam is the detected launcher and is running in the bottle.
**Example:**
```swift
// Source: Custom implementation based on CONTEXT.md decisions
actor SteamDownloadMonitor {
    private var lastSnapshot: [String: (size: UInt64, mtime: Date)] = [:]
    private var stallStartTime: Date?
    private let stallThreshold: TimeInterval = 180  // 3 minutes

    func sample(bottleURL: URL) -> StallStatus {
        let downloadingDir = bottleURL
            .appending(path: "drive_c/Program Files (x86)/Steam/steamapps/downloading")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: downloadingDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ), !contents.isEmpty else {
            stallStartTime = nil
            return .noDownloads
        }

        let snapshot = buildSnapshot(contents)
        let hasProgress = snapshot != lastSnapshot
        lastSnapshot = snapshot

        if hasProgress {
            stallStartTime = nil
            return .downloading
        } else {
            let start = stallStartTime ?? Date()
            stallStartTime = start
            let elapsed = Date().timeIntervalSince(start)
            return elapsed >= stallThreshold ? .likelyStalled(duration: elapsed) : .downloading
        }
    }
}
```

### Anti-Patterns to Avoid
- **Running winetricks via Terminal AppleScript for installations:** The existing `Winetricks.runCommand()` uses AppleScript to open Terminal, which triggers macOS volume access prompts attributed to Terminal.app instead of Whisky. Always use headless `Process` for dependency installs.
- **Polling controller state with a timer:** Use `GCControllerDidConnect`/`GCControllerDidDisconnect` notifications instead. Only use timer-based refresh for the subpanel's "Refresh" button.
- **Storing controller device IDs for persistence:** Controller identifiers change with re-pairing (Bluetooth address rotation). Persist settings (SDL hints) not device binding.
- **Blocking the main thread for winetricks operations:** All winetricks verb installation and list-installed calls must be async. The existing `listInstalledVerbs` already demonstrates the correct async pattern.
- **Creating a custom dependency detection system:** Leverage the existing `WinetricksVerbCache` + `Winetricks+InstalledVerbs` infrastructure from Phase 2.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Controller discovery | Custom IOKit HID enumeration | `GameController.framework` `GCController` | Gives type badges, battery, connect/disconnect notifications for free |
| Winetricks verb status | Custom DLL file scanning | `WinetricksVerbCache` + `listInstalledVerbs()` | Already built in Phase 2; handles caching, staleness, and fallback |
| Environment variable layering | Manual dict merging | `EnvironmentBuilder` with `EnvironmentLayer` | Provenance tracking, layer ordering, removal semantics already correct |
| Toast notifications | Custom overlay system | `StatusToast` + `ToastModifier` | Animation, auto-dismiss, tap-to-dismiss already implemented |
| Crash pattern matching | Custom string scanning | `CrashClassifier` + `patterns.json` | Prefilter optimization, confidence scoring, remediation linking already working |
| DLL override composition | Manual WINEDLLOVERRIDES string building | `DLLOverrideResolver` | Deduplication, source tracking, warning generation already handled |
| Config snapshot/revert | Manual settings backup | `GameConfigApplicator` + `GameConfigSnapshot` | Diff preview, revert with verb tracking already implemented |

**Key insight:** Phase 8 is primarily an extension phase, not a greenfield build. Every major subsystem already has infrastructure. The risk is duplicating existing patterns rather than extending them.

## Common Pitfalls

### Pitfall 1: Terminal.app Volume Access Cascading
**What goes wrong:** Running winetricks via AppleScript/Terminal causes macOS to attribute volume access to Terminal.app, triggering repeated permission prompts that Whisky cannot manage.
**Why it happens:** The current `Winetricks.runCommand()` opens Terminal via AppleScript. macOS sandboxing attributes file access to the app that performs it.
**How to avoid:** Use headless `Process` execution (as `Winetricks.listInstalledVerbs()` already does). Copy any external installers into the prefix or Whisky's temp directory before running.
**Warning signs:** Users seeing "Terminal would like to access..." dialogs during dependency installation.

### Pitfall 2: GCController.controllers() Returns Empty on First Call
**What goes wrong:** The `controllers()` class method may return empty before the framework has completed discovery.
**Why it happens:** GameController framework performs async discovery. Controllers may not be available immediately at view appear time.
**How to avoid:** Register for `GCControllerDidConnect` notification before calling `controllers()`. Use the notification-driven pattern to populate the list. Add a short initial delay or handle empty state gracefully.
**Warning signs:** "No controllers detected" showing briefly then populating.

### Pitfall 3: Winetricks Verb Names Don't Match Dependency Display Names
**What goes wrong:** User-facing dependency names (e.g., "Visual C++ Runtime") don't map 1:1 to winetricks verb names (e.g., `vcrun2019`).
**Why it happens:** A single logical dependency may correspond to multiple winetricks verbs, and vice versa.
**How to avoid:** Create a mapping layer (`DependencyDefinition`) that maps display names to one or more winetricks verbs. Status = "Installed" only when ALL required verbs for that dependency are confirmed installed.
**Warning signs:** Status showing "Installed" when only one of multiple required verbs is present.

### Pitfall 4: Steam Download Stall False Positives During Decompression
**What goes wrong:** Steam stall detection triggers during normal Steam behavior -- Steam downloads compressed data, then pauses network activity to decompress/validate.
**Why it happens:** File sizes in `steamapps/downloading/` stop growing during decompression, which looks identical to a stall.
**How to avoid:** Require corroboration from Wine log analysis (WinHTTP timeout/TLS errors or Steam content log stall patterns) before escalating to high confidence. Show "Download health" as passive status, only push-alert on corroborated evidence.
**Warning signs:** Users getting stall warnings for normal Steam behavior, leading to alert fatigue and permanent dismissal.

### Pitfall 5: MacOSVersion Comparison Edge Cases
**What goes wrong:** Version-gated fixes don't activate or activate incorrectly on unexpected macOS versions.
**Why it happens:** The `MacOSVersion` comparison is fine for standard versions, but beta versions or future releases may have unexpected version numbers.
**How to avoid:** Use `>=` comparisons for "this version and newer" fixes. Always log which version-gated fixes are active. Write tests with specific version values.
**Warning signs:** Fixes that work in development but fail on user machines with different macOS versions.

### Pitfall 6: Winetricks Process Hangs Without Display
**What goes wrong:** Some winetricks verbs spawn GUI installers (e.g., .NET Framework) that hang when run headlessly because they need a display.
**Why it happens:** Wine creates windows even for "silent" installers, and without a display context, the process blocks.
**How to avoid:** Ensure DISPLAY or equivalent is set in the process environment. Wine on macOS uses its built-in display driver (Mac Driver), so headless execution should work as long as the Wine prefix is configured. Test each verb that will be offered in the guided installer. Consider adding `/S` or `/q` flags for known installer types.
**Warning signs:** Winetricks install processes that start but never complete.

## Code Examples

### Dependency Definition Mapping
```swift
// Source: Custom implementation for Phase 8
struct DependencyDefinition: Codable, Identifiable, Sendable {
    let id: String              // "vcruntime", "dotnet48", "directx"
    let displayName: String     // "Visual C++ Runtime"
    let description: String     // "Required by most Windows games"
    let winetricksVerbs: [String] // ["vcrun2019"] or ["dotnet48"]
    let category: DependencyCategory

    enum DependencyCategory: String, Codable, Sendable {
        case runtime    // vcredist, dotnet
        case directx    // directx, d3dx9
        case audio      // xact, xaudio
    }
}

// Standard definitions:
static let standardDependencies: [DependencyDefinition] = [
    DependencyDefinition(
        id: "vcruntime",
        displayName: "Visual C++ Runtime",
        description: "Required by most Windows games and applications",
        winetricksVerbs: ["vcrun2019"],
        category: .runtime
    ),
    DependencyDefinition(
        id: "dotnet48",
        displayName: ".NET Framework 4.8",
        description: "Required by .NET applications and some game launchers",
        winetricksVerbs: ["dotnet48"],
        category: .runtime
    ),
    DependencyDefinition(
        id: "directx",
        displayName: "DirectX Runtime",
        description: "DirectX End-User Runtime for legacy DirectX components",
        winetricksVerbs: ["d3dx9", "d3dcompiler_47"],
        category: .directx
    ),
]
```

### Dependency Status Checking
```swift
// Source: Extends existing Winetricks+InstalledVerbs.swift pattern
struct DependencyStatus: Sendable {
    let definition: DependencyDefinition
    let status: Status
    let lastChecked: Date?
    let confidence: Confidence

    enum Status: Sendable {
        case installed
        case notInstalled
        case partiallyInstalled(installed: [String], missing: [String])
        case unknown
    }

    enum Confidence: Sendable {
        case authoritative   // from winetricks list-installed
        case cached          // from WinetricksCache.plist
        case heuristic       // from DLL/registry probes
    }
}

// Check all dependencies for a bottle:
static func checkDependencies(
    for bottle: Bottle,
    definitions: [DependencyDefinition]
) async -> [DependencyStatus] {
    let (verbs, fromCache) = await Winetricks.loadInstalledVerbs(for: bottle)

    return definitions.map { def in
        let installed = def.winetricksVerbs.filter { verbs.contains($0) }
        let missing = def.winetricksVerbs.filter { !verbs.contains($0) }

        let status: DependencyStatus.Status
        if missing.isEmpty {
            status = .installed
        } else if installed.isEmpty {
            status = .notInstalled
        } else {
            status = .partiallyInstalled(installed: installed, missing: missing)
        }

        return DependencyStatus(
            definition: def,
            status: status,
            lastChecked: fromCache ? nil : Date(),
            confidence: fromCache ? .cached : .authoritative
        )
    }
}
```

### Connected Controllers Subpanel Data Model
```swift
// Source: Apple GameController framework
import GameController

struct ControllerInfo: Identifiable {
    let id = UUID()
    let name: String
    let productCategory: String     // "Xbox", "DualShock4", "DualSense", etc.
    let batteryLevel: Float?        // 0.0...1.0, nil if not available
    let batteryState: GCDeviceBattery.State?
    let isAttachedToDevice: Bool    // True = USB, False = Bluetooth/wireless

    var typeBadge: ControllerType {
        switch productCategory {
        case "DualShock 4": .playStation
        case "DualSense": .playStation
        case _ where productCategory.contains("Xbox"): .xbox
        default: .generic
        }
    }

    var connectionBadge: ConnectionType {
        isAttachedToDevice ? .usb : .bluetooth
    }

    enum ControllerType: String {
        case playStation = "PlayStation"
        case xbox = "Xbox"
        case generic = "Generic"

        var sfSymbol: String {
            switch self {
            case .playStation: "gamecontroller"
            case .xbox: "gamecontroller"
            case .generic: "gamecontroller"
            }
        }
    }

    enum ConnectionType: String {
        case usb = "USB"
        case bluetooth = "Bluetooth"

        var sfSymbol: String {
            switch self {
            case .usb: "cable.connector"
            case .bluetooth: "wave.3.right"
            }
        }
    }
}
```

### Steam Stall Detection -> Diagnostics Integration
```swift
// Source: Extends existing CrashPattern/CrashClassifier pipeline
// New pattern for patterns.json:
{
    "id": "steam-download-stall",
    "category": "networkingLaunchers",
    "severity": "warning",
    "confidence": 0.6,
    "substringPrefilter": "download",
    "regex": "(?:Steam|steam).*(?:download|content).*(?:stall|timeout|failed|error)",
    "tags": ["steam", "download", "stall", "network"],
    "captureGroups": null,
    "remediationActionIds": ["steam-download-fix"]
}

// New remediation for remediations.json:
{
    "id": "steam-download-fix",
    "title": "Fix Steam Download Stall",
    "description": "Steam downloads can stall due to network configuration.",
    "category": "networkingLaunchers",
    "actionType": "changeSetting",
    "risk": "low",
    "settingKeyPath": "networkTimeout",
    "settingValue": "90000",
    "winetricksVerb": null,
    "whatWillChange": "Increases network timeout and enables HTTP/1.1 fallback",
    "undoPath": "Reset network timeout in Launcher settings",
    "appliesNextLaunch": true
}
```

### SDL Hint for XInput vs Native Labels
```swift
// Source: SDL wiki (https://wiki.libsdl.org/SDL2/CategoryHints)
// For the "Treat as XInput" vs "Native labels" choice:

// XInput mode (default Windows behavior - A/B/X/Y layout):
builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "0", layer: .bottleManaged)

// Native labels mode (physical button positions - Cross/Circle/Square/Triangle):
builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "1", layer: .bottleManaged)

// Additional hint to control PS5 DualSense behavior:
builder.set("SDL_JOYSTICK_HIDAPI_PS5", "1", layer: .bottleManaged)  // Enable HIDAPI for PS5
builder.set("SDL_JOYSTICK_HIDAPI_PS4", "1", layer: .bottleManaged)  // Enable HIDAPI for PS4

// If controller is not detected, try disabling HIDAPI:
builder.set("SDL_JOYSTICK_HIDAPI", "0", layer: .bottleManaged)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Winetricks via Terminal AppleScript | Headless Process execution | Phase 2 (installed verb detection) | Volume access attributed to Whisky, not Terminal |
| Manual env var dict mutation | EnvironmentBuilder with layers | Phase 2 | Provenance tracking, deterministic cascade |
| Single crash pattern matching | CrashClassifier with JSON pattern database | Phase 5 | Extensible, confidence-scored, remediation-linked |
| No launcher detection | Auto-detection + manual mode | Phase 2 | 7 launcher types with optimized env vars |
| No controller settings | BottleInputConfig + SDL hints | Phase 2 | 4 toggle settings with ProgramOverrides support |

**Deprecated/outdated:**
- `BottleSettings.environmentVariables(wineEnv:)` -- Marked `@available(*, deprecated)`. Use EnvironmentBuilder layer populators instead.
- `Winetricks.runCommand()` via Terminal AppleScript -- Still exists but should NOT be used for Phase 8 dependency installs. Use headless Process pattern from `Winetricks.listInstalledVerbs()`.

## Open Questions

1. **GCController `isAttachedToDevice` reliability for USB vs Bluetooth distinction**
   - What we know: `isAttachedToDevice` returns true for controllers physically connected via USB. Apple docs say it indicates "whether the controller is attached to the device."
   - What's unclear: Whether this reliably distinguishes USB from Bluetooth for all controller types (Xbox wireless adapter via USB dongle may report as attached).
   - Recommendation: Use `isAttachedToDevice` as the primary signal. Add a note in the UI that USB dongle connections may show as USB. This is acceptable for a "Connected Controllers" info panel.

2. **Winetricks headless verb installation for GUI-requiring verbs**
   - What we know: `listInstalledVerbs()` runs headlessly successfully. Wine's Mac Driver provides display context.
   - What's unclear: Whether verbs like `dotnet48` that spawn complex GUI installers will complete headlessly without hanging.
   - Recommendation: Test each offered verb headlessly during development. Add timeout handling (e.g., 10 minutes for dotnet48) with graceful cancellation. Display progress via stdout streaming.

3. **Steam content log location for stall corroboration**
   - What we know: Steam writes content download logs. The `steamapps/downloading/` directory approach is decided.
   - What's unclear: Exact path to Steam's content download log within the Wine prefix.
   - Recommendation: Check `drive_c/Program Files (x86)/Steam/logs/content_log.txt` and `steamapps/downloading/*/state_*.patch`. Start with mtime-only detection; add log corroboration as a confidence booster in a follow-up if the path varies.

4. **CTRL-02 (Microphone permission) and CTRL-04 (Retina mouse scaling) scope**
   - What we know: These are listed in requirements but not discussed in CONTEXT.md decisions.
   - What's unclear: Whether these are in-scope for this phase or deferred.
   - Recommendation: CTRL-02 (mic permission) is a simple Info.plist usage description string + runtime permission check. CTRL-04 (retina mouse scaling) involves Wine's DPI/retina mode settings already accessible via `Wine.retinaMode(bottle:)` in ConfigView. Both are small, independent tasks that fit within Phase 8.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `LauncherPresets.swift`, `EnvironmentBuilder.swift`, `MacOSCompatibility.swift`, `BottleInputConfig.swift`, `BottleLauncherConfig.swift`, `WinetricksVerbCache.swift`, `Winetricks+InstalledVerbs.swift`, `LauncherDetection.swift`, `CrashClassifier.swift`, `ProgramOverrides.swift`, `ConfigView.swift`, `StatusToast.swift`, `RemediationCardView.swift`, `GameConfigApplicator.swift`, `DiagnosticExporter.swift`, `ProgramOverrideSettingsView.swift`, `patterns.json`
- [GCController | Apple Developer Documentation](https://developer.apple.com/documentation/gamecontroller/gccontroller) - Controller discovery, battery, productCategory
- [GCDeviceBattery | Apple Developer Documentation](https://developer.apple.com/documentation/gamecontroller/gcdevice/3626030-productcategory) - productCategory for controller type identification
- [SDL2 HIDAPI hints | SDL Wiki](https://wiki.libsdl.org/SDL2/SDL_HINT_JOYSTICK_HIDAPI_XBOX_ONE) - SDL controller hints

### Secondary (MEDIUM confidence)
- [Xbox Series X HIDAPI issue on macOS | SDL GitHub](https://github.com/libsdl-org/SDL/issues/4036) - HIDAPI detection problems on macOS
- [Wine DualSense support via hidraw](https://nick.tay.blue/2024/01/21/wine-dualsense/) - Wine/Proton controller approach
- [Security-scoped bookmarks | SwiftLee](https://www.avanderlee.com/swift/security-scoped-bookmarks-for-url-access/) - Persistent file access for external volumes
- [Steam download issues with Whisky | GitHub #991](https://github.com/Whisky-App/Whisky/issues/991) - Download stall patterns
- [macOS 15.4.1 breaks Steam | GitHub #1372](https://github.com/Whisky-App/Whisky/issues/1372) - Version-specific compatibility

### Tertiary (LOW confidence)
- WebSearch results on winetricks headless execution - Docker-focused, not directly applicable to macOS native process execution. Validated against existing `listInstalledVerbs()` implementation which proves headless Process works.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries are either already in the project or are Apple frameworks with stable APIs
- Architecture: HIGH - Clear extension points in existing code; no architectural changes needed
- Pitfalls: HIGH - Based on direct analysis of current codebase patterns and known macOS/Wine interaction behaviors
- Controller API: MEDIUM - GCController API is stable but `isAttachedToDevice` behavior with wireless dongles needs validation
- Steam stall detection: MEDIUM - Approach is sound but false positive rate during decompression needs real-world testing
- Headless winetricks: MEDIUM - Proven for `list-installed` but GUI-spawning verbs need testing

**Research date:** 2026-02-10
**Valid until:** 2026-03-10 (30 days - these are stable APIs and existing codebase patterns)
