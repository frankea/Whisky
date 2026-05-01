# Phase 9: UI/UX & Feature Requests - Research

**Researched:** 2026-02-11
**Domain:** SwiftUI macOS app, Wine prefix management, CLI tooling
**Confidence:** HIGH

## Summary

Phase 9 covers eight distinct feature areas across the Whisky macOS app and WhiskyCmd CLI: GPTK update dialog simplification, path handling fixes, App Nap toggle, bottle duplication, display resolution control, console persistence, Build Version/Retina Mode display fixes, and WhiskyCmd improvements including a new `shortcut` subcommand.

The codebase is well-structured with clear separation between WhiskyKit (Swift package with core logic) and the Whisky app target (SwiftUI views, view models). Most features follow established patterns: settings are stored in plist via `BottleSettings`/`ProgramSettings` with `didSet` auto-persistence, Wine registry operations use `Wine.addRegistryKey`/`Wine.queryRegistryKey`, UI follows SwiftUI `Form` with expandable `Section` blocks, and WhiskyCmd uses Swift ArgumentParser. All features in this phase build on existing infrastructure rather than introducing new dependencies.

**Primary recommendation:** Implement features in dependency order: fixes first (Build Version, Retina Mode, GPTK dialog, path handling), then settings additions (App Nap toggle is already implemented, resolution control), then major features (bottle duplication enhancement, console persistence, WhiskyCmd improvements).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Bottle duplication: full prefix clone with deep copy, settings rewrite, naming convention ("<Original Name> Copy" with increment), context menu + toolbar + menu bar entry points, determinate progress bar, toast on completion
- Console persistence: per-run log files with runId/timestamps/exit status, stream to UI and disk, run history in Program View, last 10 runs retained, stdout/stderr/winedebug channel separation with filter controls, explicit Clear/Delete/Copy/Export actions
- Resolution control: two-level model (bottle default + per-program override), virtual desktop as Advanced option, 16:9 presets (720p through 4K plus "Match Mac display" and custom), Retina Mode fix (configurable toggle, tri-state UI), Build Version fix (display actual value)
- WhiskyCmd: deterministic launch output line, keep --command unchanged, add --follow and --tail-log flags, proper exit codes, path handling with URL(fileURLWithPath:) and argument arrays, new `whisky shortcut` subcommand reusing ProgramShortcut.swift logic, test paths with spaces/parentheses/apostrophes/ampersands

### Claude's Discretion
- GPTK update dialog simplification (clear requirement: single confirmation step)
- App Nap toggle implementation details (simple per-bottle toggle)
- Progress bar implementation for bottle duplication (byte counting vs file counting)
- Exact log file format and storage location for console persistence
- Internal architecture for virtual desktop registry keys

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 15+ | All UI views, forms, sheets | Already used throughout app |
| WhiskyKit | Local SPM | Core logic, Wine interface, settings models | Central package for all features |
| ArgumentParser | 1.x | WhiskyCmd CLI parsing | Already used for all CLI subcommands |
| Foundation | macOS 15+ | FileManager, Process, PropertyListEncoder | Standard for file ops, plist serialization |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| os.log | System | Structured logging via Logger | All new modules need Logger instances |
| SemanticVersion | SPM dep | Version string parsing | Already a WhiskyKit dependency |
| QuickLookThumbnailing | System | Icon extraction for shortcuts | Used in ProgramShortcut.swift |

### No New Dependencies Needed
All phase 9 features are implementable with existing dependencies. No new libraries required.

## Architecture Patterns

### Existing Pattern: Settings Storage via Plist
All bottle and program configuration uses `Codable` structs serialized to plist files via `PropertyListEncoder/Decoder`. New settings fields follow the pattern:

```swift
// In the config struct (e.g., BottlePerformanceConfig):
var newField: SomeType = defaultValue

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.newField = try container.decodeIfPresent(SomeType.self, forKey: .newField) ?? defaultValue
}

// In BottleSettings, expose via computed property:
public var newField: SomeType {
    get { someConfig.newField }
    set { someConfig.newField = newValue }
}
```

### Existing Pattern: Wine Registry Operations
Registry keys are read/written via `Wine.addRegistryKey()` and `Wine.queryRegistryKey()`. The registry key paths are defined as `RegistryKey` enum cases in WineRegistry.swift. Virtual desktop requires adding new keys:

```
HKCU\Software\Wine\Explorer       -> "Desktop" = "Default" (string)
HKCU\Software\Wine\Explorer\Desktops -> "Default" = "1920x1080" (string)
```

### Existing Pattern: LoadingState for Async Registry Values
The `SettingItemView` + `LoadingState` pattern handles async-loaded Wine registry values with loading/success/failed states and retry buttons. Build Version and Retina Mode already use this pattern.

### Existing Pattern: BottleListEntry Context Menu
Context menu items on bottles follow the pattern in `BottleListEntry.swift`:
```swift
.contextMenu {
    Button("button.someAction", systemImage: "icon.name") {
        // action
    }
    .disabled(!bottle.isAvailable || bottle.inFlight)
    .labelStyle(.titleAndIcon)
}
```

### Existing Pattern: Toast Notifications
Success/error feedback uses `ToastData` + `.toast($toast)` modifier. Toast styles: `.success`, `.error`, `.info`, `.launcherFixes`.

### Existing Pattern: Sheet Dialogs
Confirmation dialogs use `RenameView` for text input sheets. The bottle duplication already uses this pattern via `showBottleDuplicate` in `BottleListEntry.swift`.

### Existing Pattern: WhiskyCmd Subcommands
CLI subcommands follow the Swift ArgumentParser pattern:
```swift
struct NewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Description.")
    @Argument var bottleName: String
    @Flag(name: .shortAndLong, help: "Flag description") var someFlag: Bool = false
    @MainActor mutating func run() async throws { ... }
}
```

### Recommended Project Structure for New Files
```
WhiskyKit/Sources/WhiskyKit/
    Wine/WineRegistry.swift           # Add virtual desktop registry keys
    Whisky/BottleSettings.swift       # Add resolution/virtual desktop settings
    Whisky/ProgramOverrides.swift     # Add resolution override fields
    Whisky/ProgramSettings.swift      # Add console run history fields
    Whisky/RunLog.swift               # NEW: Per-run log session model

Whisky/
    Views/Bottle/
        WineConfigSection.swift       # Modify: Build Version fix, Retina Mode tri-state
        ResolutionConfigSection.swift  # NEW: Resolution control UI section
    Views/Programs/
        ProgramView.swift             # Modify: Add Console/Runs section
        ConsoleRunHistoryView.swift   # NEW: Run history list + console viewer
    Views/Bottle/
        BottleListEntry.swift         # Modify: Enhanced duplicate progress
    Utils/
        ProgramShortcut.swift         # Modify: Extract shared logic for CLI
    Views/Setup/
        (no changes)                  # GPTK dialog is in ContentView.swift

WhiskyCmd/
    Main.swift                        # Add Shortcut subcommand, modify Run

WhiskyKit/Tests/
    WhiskyKitTests/
        PathHandlingTests.swift       # NEW: Test paths with special chars
        RunLogTests.swift             # NEW: Console persistence tests
```

### Anti-Patterns to Avoid
- **Splitting argument strings on whitespace:** The current `settings.arguments.split { $0.isWhitespace }` pattern is fragile for paths with spaces. Use `URL(fileURLWithPath:)` for paths, and argument arrays in Process, never string splitting.
- **Blocking the main thread with FileManager.copyItem:** Large bottle directories can be multiple GB. Always use `Task.detached` for copies (already done in existing `duplicate()` method).
- **Storing absolute log paths in settings:** Log file URLs should be relative to the bottle directory or use filename-only references that resolve against the log folder, so settings survive bottle moves.
- **Writing new files to the Wine prefix during copy:** The bottle duplicate operation should complete the deep copy before modifying the new bottle's metadata to avoid corrupting the clone.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Shell escaping | Custom string quoting | `String.esc` extension | Already handles all metacharacters; tested in EscapeTests.swift |
| Plist serialization | Custom JSON/plist code | `PropertyListEncoder/Decoder` | Entire codebase uses this; Codable structs with `decodeIfPresent` |
| Registry interaction | Direct file writes to user.reg | `Wine.addRegistryKey` / `Wine.queryRegistryKey` | Uses Wine's `reg` command; handles Wine prefix state correctly |
| CLI argument parsing | Manual argc/argv handling | Swift ArgumentParser | Already used for all WhiskyCmd subcommands |
| Progress estimation for copy | Custom byte counting | `Progress` with `FileManager` | macOS provides `Progress` integration; or use `du -sb` for pre-count |
| File size calculation | Recursive enumeration | `FileManager.allocatedSizeOfDirectory(at:)` or `URLResourceValues.totalFileAllocatedSize` | Avoid hand-rolling recursive size calculation |
| Shortcut .app bundle creation | Custom bundle generation | `ProgramShortcut.createShortcut()` | Existing logic handles Info.plist, icon extraction, permissions |

**Key insight:** This phase is about connecting existing infrastructure (settings storage, registry operations, process management, CLI framework) to new features rather than building new subsystems. Every feature touches existing patterns.

## Common Pitfalls

### Pitfall 1: Bottle Duplication Race Conditions
**What goes wrong:** User tries to delete, rename, or modify the source bottle while duplication is in progress.
**Why it happens:** `FileManager.copyItem` is a long-running operation on multi-GB prefixes.
**How to avoid:** Set `bottle.inFlight = true` on source bottle during copy (already done in existing `duplicate()` method). Disable destructive context menu actions when `inFlight`. The existing implementation handles this correctly.
**Warning signs:** Crash during copy, corrupt metadata, partial clone.

### Pitfall 2: Path References in Duplicated Bottles
**What goes wrong:** Duplicated bottle's pins, blocklist, and program settings still point to the original bottle's directory.
**Why it happens:** URLs in `PinnedProgram.url`, `blocklist`, and `Program.settingsURL` contain the old bottle UUID path.
**How to avoid:** The existing `duplicate()` method already rewrites `pins` and `blocklist` URLs via `updateParentBottle()`. For console persistence, ensure any per-program log references use relative paths (filenames only) rather than absolute URLs that would break on copy.
**Warning signs:** "File not found" when clicking pins in the duplicated bottle.

### Pitfall 3: Wine Registry Key Timing
**What goes wrong:** Setting virtual desktop resolution via registry has no effect because the key is written while Wine processes are running.
**Why it happens:** Wine reads registry keys at process startup. Changes to `HKCU\Software\Wine\Explorer\Desktops` don't take effect until the next wineserver restart.
**How to avoid:** Display a "Changes take effect on next launch" warning in the UI. Offer an option to kill running processes if the user wants immediate effect (warn first).
**Warning signs:** User changes resolution, nothing happens, files bug report.

### Pitfall 4: Build Version Display Showing "0"
**What goes wrong:** Build Version field shows "0" instead of the actual value.
**Why it happens:** `loadBuildName()` calls `Wine.buildVersion()` which queries registry. If the query returns nil (no registry key set yet), `buildVersion` is set to `Int(buildVersionString) ?? 0`, which gives 0. Then the UI shows "0" which is misleading.
**How to avoid:** Distinguish between "no value set" (show empty or placeholder like "Not Set") and "value is literally 0". The current code uses `Int` for `buildVersion` which loses the nil semantics.
**Warning signs:** New bottles always show "0" for Build Version.

### Pitfall 5: Retina Mode Read Failures
**What goes wrong:** Retina Mode toggle shows wrong state because registry query failed silently.
**Why it happens:** `Wine.retinaMode()` catches the "unknown" case by forcing a write of `false`, which could overwrite a valid setting the user previously set.
**How to avoid:** Implement tri-state UI: On / Off / Unknown. When in Unknown state, show the actual error and let user explicitly set a value without assuming false.
**Warning signs:** User's Retina Mode setting gets reset to Off after a read failure.

### Pitfall 6: Console Log Disk Usage
**What goes wrong:** Console persistence fills disk with unbounded log files.
**Why it happens:** Per-run logs can be large (especially with WINEDEBUG enabled), and retaining 10 runs per program across many programs adds up.
**How to avoid:** Apply the existing `Wine.maxLogFileBytes` cap (20 MiB per log file) and `Wine.maxLogsFolderBytes` (200 MiB total) retention policy. Add a separate global size cap for console run history (e.g., 500 MiB total across all programs). Older runs auto-pruned.
**Warning signs:** Disk usage complaints, slow startup while scanning old logs.

### Pitfall 7: WhiskyCmd Path Handling with Spaces
**What goes wrong:** `whisky run "My Bottle" "/path/to/My Game (x86)/game.exe"` fails because the path gets split.
**Why it happens:** The current `Run` subcommand uses `URL(fileURLWithPath: path)` which should handle spaces, but the shell may pre-split arguments before ArgumentParser sees them.
**How to avoid:** ArgumentParser already handles quoted arguments correctly. The issue is in how the path is passed to Wine: use the array-based Process arguments (already done via `Wine.runProgram(at:args:)` which builds `["start", "/unix", url.path(percentEncoded: false)]`). Test with paths containing spaces, parentheses, apostrophes, and ampersands.
**Warning signs:** "file not found" errors for paths with special characters.

### Pitfall 8: GPTK Update Dialog UX
**What goes wrong:** Users see a confusing two-step dialog flow when an update is available.
**Why it happens:** The current flow in `ContentView.swift` (.task body) uses an `NSAlert` that, when confirmed, uninstalls WhiskyWine and shows the setup sheet -- this is already a single confirmation step. The "unnecessary extra dialog" likely refers to a scenario where a second alert appears.
**How to avoid:** Trace the full flow carefully. The current code shows one alert, and if confirmed, sets `showSetup = true` which shows `SetupView`. If the user sees two dialogs, it may be because the setup view triggers its own confirmation. Simplify to: single alert with "Update Now" / "Later", and "Update Now" directly starts download+install without intermediate steps.
**Warning signs:** User reports seeing more than one dialog before the update proceeds.

## Code Examples

### Adding Virtual Desktop Registry Keys
```swift
// Source: Verified pattern from WineRegistry.swift + Wine docs
// In WineRegistry.swift, add RegistryKey cases:
private enum RegistryKey: String {
    // ... existing keys ...
    case explorer = #"HKCU\Software\Wine\Explorer"#
    case explorerDesktops = #"HKCU\Software\Wine\Explorer\Desktops"#
}

@MainActor
static func enableVirtualDesktop(bottle: Bottle, resolution: String) async throws {
    try await addRegistryKey(
        bottle: bottle,
        key: RegistryKey.explorer.rawValue,
        name: "Desktop",
        data: "Default",
        type: .string
    )
    try await addRegistryKey(
        bottle: bottle,
        key: RegistryKey.explorerDesktops.rawValue,
        name: "Default",
        data: resolution,  // e.g., "1920x1080"
        type: .string
    )
}

@MainActor
static func disableVirtualDesktop(bottle: Bottle) async throws {
    // Removing the "Desktop" value from Explorer key disables virtual desktop
    try await runWine(
        ["reg", "delete", RegistryKey.explorer.rawValue, "-v", "Desktop", "-f"],
        bottle: bottle
    )
}
```

### Per-Run Log Session Model
```swift
// Source: Architecture from existing ProgramSettings + Wine logging patterns
// New file: WhiskyKit/Sources/WhiskyKit/Whisky/RunLog.swift

public struct RunLogEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date?
    public var exitCode: Int32?
    public let logFileName: String  // Relative to logs folder, not absolute URL
    public let programURL: URL
    public var activeWineDebugPreset: WineDebugPreset?

    public var isRunning: Bool { endTime == nil }

    public init(programURL: URL, logFileName: String) {
        self.id = UUID()
        self.startTime = Date()
        self.logFileName = logFileName
        self.programURL = programURL
    }
}

public struct RunLogHistory: Codable, Equatable {
    public static let maxEntriesPerProgram = 10
    public var entries: [RunLogEntry] = []

    public mutating func append(_ entry: RunLogEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntriesPerProgram {
            // Remove oldest entries and delete their log files
            let excess = entries.count - Self.maxEntriesPerProgram
            let removed = entries.prefix(excess)
            entries.removeFirst(excess)
            for entry in removed {
                let logURL = Wine.logsFolder.appending(path: entry.logFileName)
                try? FileManager.default.removeItem(at: logURL)
            }
        }
    }
}
```

### WhiskyCmd Shortcut Subcommand
```swift
// Source: Pattern from existing WhiskyCmd/Main.swift + ProgramShortcut.swift
struct Shortcut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a macOS app shortcut for a Windows program."
    )

    @Argument(help: "Name of the bottle") var bottleName: String
    @Argument(help: "Path to the Windows executable") var exePath: String

    @Option(name: .long, help: "Display name for the shortcut")
    var name: String?

    @Option(name: .long, help: "Output directory (default: ~/Applications)")
    var output: String?

    @Flag(name: .long, help: "Overwrite existing shortcut")
    var overwrite: Bool = false

    @MainActor
    mutating func run() async throws {
        var bottlesList = BottleData()
        let bottles = bottlesList.loadBottles()

        guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
            throw ValidationError("No bottle called \"\(bottleName)\" found.")
        }

        let url = URL(fileURLWithPath: exePath)
        let program = Program(url: url, bottle: bottle)

        let shortcutName = name ?? program.name.replacingOccurrences(of: ".exe", with: "")
        let outputDir = output.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)[0]
        let appURL = outputDir.appendingPathComponent(shortcutName + ".app")

        if FileManager.default.fileExists(atPath: appURL.path) {
            if overwrite {
                try FileManager.default.removeItem(at: appURL)
            } else {
                throw ValidationError(
                    "Shortcut already exists at \(appURL.path). Use --overwrite to replace."
                )
            }
        }

        await ProgramShortcut.createShortcut(program, app: appURL, name: shortcutName)
        print("Created \(appURL.path(percentEncoded: false))")
    }
}
```

### Match Mac Display Resolution
```swift
// Source: Apple NSScreen documentation
static func currentDisplayResolution() -> (width: Int, height: Int)? {
    guard let screen = NSScreen.main else { return nil }
    let frame = screen.frame
    let scale = screen.backingScaleFactor
    // Return pixel dimensions (accounting for Retina)
    return (
        width: Int(frame.width * scale),
        height: Int(frame.height * scale)
    )
}
```

### Tri-State Retina Mode UI
```swift
// Source: Pattern from existing WineConfigSection.swift SettingItemView
enum RetinaModeState: Equatable {
    case on
    case off
    case unknown  // Registry read failed

    var label: String {
        switch self {
        case .on: String(localized: "config.retinaMode.on")
        case .off: String(localized: "config.retinaMode.off")
        case .unknown: String(localized: "config.retinaMode.unknown")
        }
    }
}
```

### Enhanced WhiskyCmd Run with --follow
```swift
// In the Run command's run() method:
if follow {
    let environment = program.generateEnvironment()
    let result = try await Wine.runProgram(
        at: url, args: args, bottle: bottle, environment: environment
    )
    // runProgram already iterates the AsyncStream; for --follow we need
    // to stream to stdout. This requires a modified flow that yields
    // lines to FileHandle.standardOutput.
    print("Exited with code \(result.exitCode)")
    if result.exitCode != 0 {
        throw ExitCode(result.exitCode)
    }
} else {
    // Default: launch and print single deterministic line
    let environment = program.generateEnvironment()
    let result = try await Wine.runProgram(
        at: url, args: args, bottle: bottle, environment: environment
    )
    print(#"Launched "\#(url.lastPathComponent)" in bottle "\#(bottleName)"."#)
    if result.exitCode != 0 {
        throw ExitCode(result.exitCode)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `BottleSettings.environmentVariables()` dict mutation | `EnvironmentBuilder` 8-layer resolution | Phase 2 | All env var logic uses builder pattern now |
| `Run` subcommand no output | Should print deterministic line | Phase 9 | Scripts can parse launch confirmation |
| Single Wine log per run (unlinked) | Log URL tracked in `ProgramSettings.lastLogFileURL` | Phase 5 | Foundation for console persistence |
| Retina Mode as Bool toggle | Tri-state (On/Off/Unknown) | Phase 9 | Handles registry read failures gracefully |
| Build Version shows Int (0 if unset) | Shows actual registry value or "Not Set" | Phase 9 | No more misleading "0" display |

**Existing implementations to build on:**
- `Bottle.duplicate()` in Bottle+Extensions.swift: Already implements deep copy with pin/blocklist rewriting. Phase 9 enhances with progress UI and naming convention.
- `disableAppNap` in BottlePerformanceConfig: Already implemented as a boolean field with `ProcessInfo.beginActivity()` in Wine.runProgram(). Phase 9 just ensures the UI toggle is properly surfaced.
- `Wine.logsFolder` and `Wine.makeFileHandleWithURL()`: Already creates per-run log files. Console persistence extends this to track run history per program.

## Open Questions

1. **ProgramShortcut sharing between app and CLI**
   - What we know: `ProgramShortcut.createShortcut()` is in the Whisky app target, not WhiskyKit. WhiskyCmd cannot import Whisky app target.
   - What's unclear: Whether to move ProgramShortcut to WhiskyKit or duplicate the logic. Moving it requires resolving AppKit/QuickLook dependencies in the SPM package.
   - Recommendation: Move the core bundle-creation logic (Info.plist, script, permissions) to WhiskyKit. Keep the QLThumbnailGenerator icon extraction in the app target since it requires AppKit. WhiskyCmd can skip icon extraction or use a simpler approach.

2. **Console persistence storage location**
   - What we know: Current Wine logs go to `~/Library/Logs/{bundle-id}/`. Run history metadata needs to be per-program.
   - What's unclear: Whether run history plist should live alongside existing program settings (in `{bottle}/Program Settings/{name}.plist`) or in a separate file.
   - Recommendation: Store run history in a separate plist per program: `{bottle}/Program Settings/{name}.run-history.plist`. This avoids bloating the main settings file and allows independent pruning. Log files stay in the existing logs folder with filenames that include the runId for correlation.

3. **Progress reporting for bottle duplication**
   - What we know: `FileManager.copyItem()` is a single blocking call with no progress callback. The user decision says "determinate progress bar (x / y GB) if byte count available."
   - What's unclear: macOS `FileManager.copyItem()` does not provide progress callbacks. Alternative approaches: (a) pre-calculate size with recursive enumeration, then copy files individually with progress, (b) use `Progress` framework with NSFileManager's `-copyItemAtURL:toURL:error:` which does support `NSProgress`, (c) use indeterminate spinner.
   - Recommendation: Use `NSFileManager` (Objective-C API) which integrates with `NSProgress`, or do a recursive file-by-file copy with byte counting. For large bottles (multi-GB), a file-by-file approach with `ByteCountFormatter` provides the best UX. For simplicity, start with indeterminate progress with phase labels ("Calculating size...", "Copying files...", "Updating metadata...", "Finalizing...") and enhance to determinate if time permits.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: All Swift source files listed in Architecture section
- `WineRegistry.swift` - Existing registry key patterns
- `BottleSettings.swift` - Settings storage architecture
- `ProgramSettings.swift` - Per-program settings model
- `ProgramShortcut.swift` - Shortcut creation logic
- `WhiskyCmd/Main.swift` - CLI subcommand patterns
- `Bottle+Extensions.swift` - Existing `duplicate()` implementation
- `Wine.swift` - Process execution and logging infrastructure
- `Process+Extensions.swift` - AsyncStream output handling

### Secondary (MEDIUM confidence)
- [WineHQ Forums: Virtual desktop registry](https://forum.winehq.org/viewtopic.php?t=30521) - `HKCU\Software\Wine\Explorer` and `HKCU\Software\Wine\Explorer\Desktops` registry keys
- [WineHQ Forums: Desktop mode](https://forum.winehq.org/viewtopic.php?t=37529) - Wine virtual desktop enable/disable via registry
- [Apple NSScreen documentation](https://developer.apple.com/documentation/appkit/nsscreen) - `NSScreen.main?.frame` and `backingScaleFactor` for "Match Mac display"
- [Lutris Wine virtual desktop issue](https://github.com/lutris/lutris/issues/82) - Confirms registry key structure for virtual desktop

### Tertiary (LOW confidence)
- None -- all findings verified against codebase or official sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All features use existing dependencies; no new libraries needed
- Architecture: HIGH - All patterns verified against existing codebase; every feature follows established conventions
- Pitfalls: HIGH - Based on direct code analysis of existing implementations and known Wine behavior
- Registry keys: MEDIUM - Virtual desktop keys confirmed by multiple WineHQ forum posts but not tested in this specific Wine build

**Research date:** 2026-02-11
**Valid until:** 2026-03-13 (stable codebase; Wine registry keys are long-standing)
