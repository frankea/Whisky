# Phase 1: Miscellaneous Fixes - Research

**Researched:** 2026-02-08
**Domain:** SwiftUI macOS app (WhiskyKit + Whisky app targets), Wine bottle management
**Confidence:** HIGH

## Summary

Phase 1 finalizes four in-progress backend implementations (ClickOnceManager, ClipboardManager, TempFileTracker, ProcessRegistry) by integrating them into the existing Whisky app UI and lifecycle. All four singletons already exist in `WhiskyKit/Sources/WhiskyKit/` with working core logic but zero integration points: they are not called from any views, app lifecycle hooks, or Wine execution paths.

The primary work is **wiring**, not creation. The ClickOnceManager needs to surface detected apps in the Programs list. The ClipboardManager needs to be called before `Wine.runProgram()` with per-bottle settings. The TempFileTracker needs `register()` calls where temp files are created and `cleanupAll()`/`cleanupOldFiles()` calls on lifecycle events. The ProcessRegistry needs `register()`/`updatePID()`/`unregister()` calls around Wine process launch and `cleanup()` calls on bottle close/app quit.

**Primary recommendation:** Wire the four existing managers into the app using the established patterns (BottleSettings for per-bottle config, AppDelegate for lifecycle hooks, toast system for user feedback, `os_log` for diagnostics). No new frameworks needed; this is purely integration work within the existing SwiftUI + WhiskyKit architecture.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### ClickOnce app presentation
- ClickOnce apps are first-class launchable entries in the bottle's Programs list, not just auto-pins
- Represent each app by its `.appref-ms` file (the stable on-disk artifact to launch)
- Display name: friendly app name (strip `.appref-ms` and trailing `.application` from manifest URL); fall back to `.appref-ms` filename if parsing fails
- Show a "ClickOnce" badge or separate section in the Programs list; generic icon is fine; no architecture tag
- Do NOT surface internal ClickOnce cache executables as separate programs (too noisy/confusing)
- Management actions parallel regular Programs: Run, Run in Terminal (Shift), Pin/Unpin, Show in Finder, Create Shortcut, plus ClickOnce-specific: Copy Deployment URL, Remove/Forget (.appref-ms + optionally clear cache)
- Auto-detect ClickOnce apps when a bottle is opened or Programs view appears; fast-gated (`if ClickOnce dir exists`), background scan, cached, refresh on directory change
- Provide a manual "Rescan ClickOnce apps" action as fallback
- Best-effort live detection: if a ClickOnce app is installed inside Wine, it appears in the program list on next view-appear or background refresh (not instant notifications)

#### Clipboard intervention
- Clipboard safeguards activate at launch time, right before starting a Wine process
- For known multiplayer launchers (`LauncherType.usesClipboard` = true): auto-clear large clipboard content, show a brief non-blocking toast ("Clipboard cleared to prevent game hang" with type/size)
- For other programs with large clipboard: show a blocking alert/sheet explaining the risk, approximate size, truncated text preview (text only), with "Clear Clipboard" (recommended) and "Keep" buttons; optional "Don't warn again for this bottle" toggle
- Per-bottle setting with 4 options: `Auto (Recommended)` (default -- auto-clear for known launchers, warn for others), `Always warn`, `Always clear on launch`, `Never warn/clear`
- Keep 10 KB as the default "large" threshold (`ClipboardManager.largeContentThreshold`); allow per-bottle override in the setting
- Images/unknown types treated more conservatively than text

#### Cleanup feedback
- Temp file cleanup is **silent by default** -- no toasts, no alerts, only `os_log` for diagnostics
- Show a non-blocking warning toast only if cleanup repeatedly fails while the app is still running ("Couldn't remove some temporary files; will retry later" with "Show Details" affordance)
- On app quit: never block termination for cleanup; just log and retry next launch
- Zombie process cleanup: no UI if cleanup succeeds silently; if processes were force-killed, show a single non-blocking toast per bottle ("Cleaned up leftover Wine processes in '<Bottle Name>' (3)") with optional "Details" action
- Use a **blocking alert** only when killing processes the user likely considers "active" (bottle has running apps and user initiated close/quit)
- No persistent cleanup history in the UI; cleanup events go to logs/diagnostics only; optionally surface in an "Advanced Diagnostics" view if one exists

#### Cleanup triggers
- **Temp files**: (1) immediately after use when consumer has read it, (2) on associated Wine process exit, (3) on bottle shutdown/close, (4) best-effort `cleanupAll()` on app quit (never block termination), (5) `cleanupOldFiles(olderThan:)` on next launch or periodically to catch orphans from crashes (>24h)
- **Zombie processes**: (1) on app launch -- background sweep for crash leftovers, (2) on bottle open / Programs view -- quick check if no tracked processes, (3) before launching a program -- reconcile stray wineserver for the prefix, (4) on user-initiated bottle stop/close and on app quit
- Only act on processes that clearly belong to a Whisky bottle (match `WINEPREFIX` to known bottle paths); rate-limit sweeps
- On crash recovery (next launch): auto-cleanup orphaned temp files older than safety window + graceful SIGTERM -> SIGKILL escalation for orphaned Wine processes; silent unless it fails
- Per-bottle "Kill on quit" setting with 3 states: `Inherit (default)`, `Always kill on app quit`, `Never kill on app quit` -- overrides the existing global `killOnTerminate` setting

### Claude's Discretion
- Exact toast/banner implementation (SwiftUI overlay vs system notification)
- ClickOnce directory watching mechanism (FSEvents, polling interval, etc.)
- Cleanup retry timing and backoff strategy details
- Rate-limiting approach for zombie process sweeps
- Internal cache structure for ClickOnce scan results

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 15+ | UI framework | Already used throughout Whisky app views |
| AppKit (NSPasteboard, NSAlert) | macOS 15+ | Clipboard access, modal alerts | Already used in ClipboardManager and throughout the app |
| os.log (Logger) | macOS 15+ | Structured logging | Already used in all four managers and app-wide |
| Foundation (Process, FileManager, NSLock) | macOS 15+ | Process management, file ops, thread safety | Already used in ProcessRegistry and TempFileTracker |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| PropertyListEncoder/Decoder | Foundation | Settings serialization | Already used via BottleSettings for per-bottle config persistence |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSLock (current in TempFileTracker/ProcessRegistry) | Swift actors | Actors would be more idiomatic Swift 6 but existing code uses NSLock consistently; changing would widen scope |
| SwiftUI overlay toast | NSUserNotification / UNUserNotificationCenter | System notifications require entitlements and are more intrusive; the existing toast system is already built and used |
| Manual ClickOnce dir polling | DispatchSource.makeFileSystemObjectSource / FSEvents | FSEvents is more efficient but adds complexity; polling on view-appear is simpler and sufficient per user decisions |

**Installation:** No additional dependencies needed. All required frameworks are already available in the project.

## Architecture Patterns

### Recommended File Locations
```
WhiskyKit/Sources/WhiskyKit/
├── ClickOnceManager.swift          # EXISTS - backend logic (needs display name helper)
├── ClipboardManager.swift          # EXISTS - backend logic (needs per-bottle settings integration)
├── TempFileTracker.swift           # EXISTS - backend logic (needs lifecycle call sites)
├── ProcessRegistry.swift           # EXISTS - backend logic (needs lifecycle call sites)
├── Whisky/
│   ├── BottleSettings.swift        # EXISTS - add clipboard/kill-on-quit settings
│   └── BottleCleanupConfig.swift   # NEW - config struct for clipboard + kill-on-quit settings
│
Whisky/
├── AppDelegate.swift               # EXISTS - add quit-time cleanup hooks
├── Views/
│   ├── Bottle/
│   │   ├── BottleView.swift        # EXISTS - add ClickOnce detection on appear
│   │   └── ConfigView.swift        # EXISTS - add clipboard/cleanup settings sections
│   ├── Programs/
│   │   ├── ProgramsView.swift      # EXISTS - integrate ClickOnce apps into program list
│   │   └── ProgramMenuView.swift   # EXISTS - add ClickOnce-specific context menu actions
│   └── Common/
│       └── StatusToast.swift       # EXISTS - toast system already built
├── Extensions/
│   └── Bottle+Extensions.swift     # EXISTS - add ClickOnce scan to updateInstalledPrograms()
└── Utils/
    └── LauncherDetection.swift     # EXISTS - clipboard check hook point before Wine launch
```

### Pattern 1: Per-Bottle Settings via BottleSettings Config Structs
**What:** Each configuration domain gets its own `Codable` struct nested in `BottleSettings`, with proxy properties on `BottleSettings` for convenient access.
**When to use:** Any new per-bottle setting (clipboard policy, kill-on-quit override, ClickOnce scan cache).
**Example from existing code:**
```swift
// BottleLauncherConfig.swift pattern:
public struct BottleLauncherConfig: Codable, Equatable {
    var compatibilityMode: Bool = false
    var launcherMode: LauncherMode = .auto
    // ... with custom init(from decoder:) providing defaults
}

// BottleSettings.swift proxy:
public var launcherCompatibilityMode: Bool {
    get { launcherConfig.compatibilityMode }
    set { launcherConfig.compatibilityMode = newValue }
}
```
**Use this pattern for:** New `BottleCleanupConfig` (clipboard policy, clipboard threshold, kill-on-quit override).

### Pattern 2: Singleton Manager with os_log
**What:** Backend managers are `final class` singletons marked `@unchecked Sendable` with `NSLock` for thread safety and `os.log` Logger for diagnostics.
**When to use:** All four managers already follow this pattern. No changes to their structure needed.
**Example from existing code:**
```swift
public final class TempFileTracker: @unchecked Sendable {
    public static let shared = TempFileTracker()
    private let lock = NSLock()
    private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "TempFileTracker")
}
```

### Pattern 3: Toast Notifications for Non-Blocking Feedback
**What:** `ToastData` structs displayed via the `.toast($toast)` view modifier. Support `.success`, `.error`, `.info` styles with optional auto-dismiss.
**When to use:** Clipboard cleared notification, zombie process cleanup notification, failed cleanup warning.
**Example from existing code:**
```swift
// Set toast in any view that has @State private var toast: ToastData?
toast = ToastData(message: "Clipboard cleared to prevent game hang", style: .info)
// Or non-dismissable:
toast = ToastData(message: "Launch failed: ...", style: .error, autoDismiss: false)
```

### Pattern 4: App Lifecycle Hooks via AppDelegate
**What:** `applicationDidFinishLaunching` for startup tasks, `applicationWillTerminate` for cleanup.
**When to use:** Orphan temp file cleanup on launch, process cleanup on quit.
**Example from existing code:**
```swift
func applicationWillTerminate(_ notification: Notification) {
    if UserDefaults.standard.bool(forKey: "killOnTerminate") {
        WhiskyApp.killBottles()
    }
}
```
**Important constraint:** `applicationWillTerminate` runs synchronously. Must not await async operations. Use synchronous `kill()` calls or fire-and-forget `Task {}`.

### Pattern 5: Program List Population via updateInstalledPrograms()
**What:** `Bottle.updateInstalledPrograms()` (in `Bottle+Extensions.swift`) scans `Program Files` directories and builds the `programs` array. Called on bottle appear and refresh.
**When to use:** This is the integration point for ClickOnce apps -- either extend this method or create a parallel scan that merges results.
**Key consideration:** `Program` currently requires a `.exe` URL and parses a PE file. ClickOnce apps use `.appref-ms` files, so a new type or adapter is needed.

### Anti-Patterns to Avoid
- **Blocking app termination for async cleanup:** `applicationWillTerminate` cannot await. TempFileTracker.cleanupAll() is async. Must use synchronous best-effort or fire-and-forget.
- **Modifying NSPasteboard from background thread:** NSPasteboard operations should happen on the main thread. ClipboardManager methods already require `@MainActor` for `sanitizeForMultiplayer`.
- **Surfacing ClickOnce cache executables:** The ClickOnce cache in `drive_c/users/.../Local Settings/Apps/2.0/...` contains internal `.exe` files that should NOT appear in the Programs list (user decision: too noisy/confusing).
- **Force-killing processes without SIGTERM first:** Always SIGTERM -> wait -> SIGKILL (ProcessRegistry already does this correctly).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Toast UI | Custom notification overlay | Existing `StatusToast` + `ToastModifier` | Already built, tested, and used throughout the app |
| Settings persistence | Custom file I/O | `BottleSettings` + `PropertyListEncoder` | Automatic `didSet` persistence pattern is established |
| Process signal management | Custom signal handling | Existing `ProcessRegistry.cleanup()` with `kill()` | Already handles SIGTERM/SIGKILL escalation correctly |
| Thread-safe collections | Custom mutex patterns | `NSLock` pattern from existing managers | Consistent with codebase; Swift actors would be a larger refactor |
| Wine environment setup | Custom env construction | `Wine.constructWineEnvironment()` | Already handles all env var merging and validation |

**Key insight:** The four managers already contain the hard logic (retry with backoff, lock detection, graceful process shutdown). The remaining work is pure integration plumbing at well-defined call sites.

## Common Pitfalls

### Pitfall 1: applicationWillTerminate Cannot Await
**What goes wrong:** Trying to call `await TempFileTracker.shared.cleanupAll()` or `await ProcessRegistry.shared.cleanupAll()` in `applicationWillTerminate` -- the method returns before async work completes, and the process exits.
**Why it happens:** `applicationWillTerminate` is a synchronous AppKit callback. The app may exit at any time after it returns.
**How to avoid:** Use synchronous cleanup for critical operations (Process `kill()` is synchronous). For temp files, use best-effort synchronous `FileManager.removeItem()` with no retry. Defer thorough cleanup to next launch via `cleanupOldFiles(olderThan:)`.
**Warning signs:** Tests pass but temp files or zombie processes persist after quit.

### Pitfall 2: ClickOnce Apps Don't Fit the Program Model
**What goes wrong:** Trying to make `.appref-ms` files work as `Program` objects, which expect `.exe` URLs and parse PE headers.
**Why it happens:** `Program.init(url:bottle:)` creates a `PEFile` from the URL, reads settings keyed by `.exe` filename, and checks pin URLs for `.exe` existence.
**How to avoid:** Either (a) create a dedicated `ClickOnceApp` type that conforms to a shared protocol with `Program`, or (b) extend `Program` with an optional `isClickOnce` flag that skips PE parsing. Option (a) is cleaner but requires more view changes; option (b) is simpler but muddies the `Program` type.
**Warning signs:** Crashes on PE parsing, missing icons, broken settings paths.

### Pitfall 3: ClickOnce Path Uses Hardcoded "crossover" Username
**What goes wrong:** The existing `ClickOnceManager.detectAppRefFile()` hardcodes `"crossover"` in the user profile path. Bottles created with different Wine builds may use different usernames.
**Why it happens:** Wine username varies between builds (e.g., "crossover", "steamuser", actual macOS username).
**How to avoid:** Use the existing `Bottle.wineUsername` property (from `Bottle+Extensions.swift`) to construct the ClickOnce directory path dynamically.
**Warning signs:** ClickOnce apps found in some bottles but not others.

### Pitfall 4: Clipboard Check Must Happen Before Wine.runProgram()
**What goes wrong:** Running clipboard check after `Wine.runProgram()` starts -- the freeze has already occurred.
**Why it happens:** The clipboard freeze happens when Wine's X11 clipboard integration attempts to read large macOS clipboard data synchronously during initialization.
**How to avoid:** Call clipboard intervention at every Wine launch site: `Program.launchWithUserMode()`, `Program.runInWine()`, `FileOpenView.run()`, and `BottleView`'s Run button handler. The call must be synchronous (main thread) before the async Wine process starts.
**Warning signs:** Clipboard is checked but games still freeze (check was too late).

### Pitfall 5: ClipboardManager Uses String Interpolation for Localization
**What goes wrong:** The existing `showLargeClipboardAlert` uses `.replacingOccurrences(of: "{size}", ...)` instead of proper string interpolation for localized strings.
**Why it happens:** The original implementation was a rough draft.
**How to avoid:** Use SwiftUI's `String(localized:)` with proper interpolation format, or pass parameters properly through the localization system.
**Warning signs:** Localized strings show `{size}` literally in non-English locales.

### Pitfall 6: Rate-Limiting Zombie Process Sweeps
**What goes wrong:** Every bottle open or program launch triggers a full process table scan, causing noticeable lag with many bottles.
**Why it happens:** Process sweeps call `kill(pid, 0)` for potentially many PIDs across all bottles.
**How to avoid:** Cache last sweep timestamp and skip if less than N seconds ago (e.g., 30 seconds). Only sweep the specific bottle being opened, not all bottles.
**Warning signs:** Slow bottle opening, excessive log entries for process checks.

## Code Examples

### Integrating Clipboard Check Before Wine Launch
```swift
// In Program+Extensions.swift, before Wine.runProgram():
@MainActor
func launchWithUserMode(useTerminal: Bool) async -> LaunchResult {
    // Clipboard intervention before Wine launch
    let clipboardPolicy = bottle.settings.clipboardPolicy
    if clipboardPolicy != .never {
        let launcher = bottle.settings.detectedLauncher
        ClipboardManager.shared.sanitizeForMultiplayer(
            launcher: launcher,
            autoClearForMultiplayer: clipboardPolicy == .alwaysClear
                || (clipboardPolicy == .auto && launcher?.usesClipboard == true)
        )
    }

    // ... existing launch logic
}
```

### Adding Per-Bottle Cleanup Settings to BottleSettings
```swift
// New BottleCleanupConfig.swift following BottleLauncherConfig pattern:
public struct BottleCleanupConfig: Codable, Equatable {
    /// Clipboard intervention policy
    var clipboardPolicy: ClipboardPolicy = .auto
    /// Custom clipboard size threshold (bytes), nil = use default
    var clipboardThreshold: Int?
    /// Per-bottle kill-on-quit override
    var killOnQuit: KillOnQuitPolicy = .inherit

    public init() {}
    public init(from decoder: Decoder) throws { /* ... with defaults */ }
}

public enum ClipboardPolicy: String, Codable, CaseIterable, Sendable {
    case auto       // Auto-clear for known launchers, warn for others
    case alwaysWarn // Always show warning dialog
    case alwaysClear // Always clear without asking
    case never      // Never check clipboard
}

public enum KillOnQuitPolicy: String, Codable, CaseIterable, Sendable {
    case inherit    // Use global killOnTerminate setting
    case always     // Always kill on app quit
    case never      // Never kill on app quit
}
```

### App Lifecycle Integration
```swift
// AppDelegate.swift additions:
func applicationDidFinishLaunching(_ notification: Notification) {
    // ... existing code ...

    // Orphan cleanup on launch (async, background)
    Task.detached {
        await TempFileTracker.shared.cleanupOldFiles(olderThan: 24 * 60 * 60)
    }
}

func applicationWillTerminate(_ notification: Notification) {
    // Existing: kill bottles if setting enabled
    // Enhanced: per-bottle kill-on-quit override
    for bottle in BottleVM.shared.bottles {
        let policy = bottle.settings.killOnQuit
        let shouldKill = switch policy {
        case .inherit: UserDefaults.standard.bool(forKey: "killOnTerminate")
        case .always: true
        case .never: false
        }
        if shouldKill {
            Wine.killBottle(bottle: bottle)
        }
    }

    // Best-effort synchronous temp file cleanup (never block)
    // Async cleanupAll() cannot be awaited here; use sync deletion
    for (url, _) in TempFileTracker.shared.getAllTrackedFiles() {
        try? FileManager.default.removeItem(at: url)
    }
}
```

### ClickOnce Display Name Derivation
```swift
// In ClickOnceManager or a helper:
func displayName(for appRefURL: URL, manifest: ClickOnceManifest?) -> String {
    if let manifest = manifest {
        // Strip ".application" suffix from manifest URL last component
        var name = manifest.url.lastPathComponent
        if name.hasSuffix(".application") {
            name = String(name.dropLast(".application".count))
        }
        // Remove ".appref-ms" if still present
        if name.hasSuffix(".appref-ms") {
            name = String(name.dropLast(".appref-ms".count))
        }
        if !name.isEmpty { return name }
    }
    // Fallback: filename without extension
    return appRefURL.deletingPathExtension().lastPathComponent
}
```

### ClickOnce Integration into Programs List
```swift
// In Bottle+Extensions.swift, updateInstalledPrograms():
func updateInstalledPrograms() {
    // ... existing exe scanning ...

    // Also scan for ClickOnce apps
    let clickOnceApps = ClickOnceManager.shared.detectAppRefFile(in: self)
    // Either: merge into self.programs with a flag
    // Or: maintain separate self.clickOnceApps property on Bottle
    // Decision depends on whether Program type can accommodate .appref-ms
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@unchecked Sendable` + `NSLock` | Swift actors | Swift 5.9+ / 6.0 | Existing managers use NSLock; keep consistent for this phase |
| `NSAlert.runModal()` | SwiftUI `.alert()` modifier | SwiftUI 3+ | ClipboardManager uses NSAlert; consider SwiftUI alert for new UI |
| Hardcoded "crossover" username | Dynamic `wineUsername` detection | This codebase (recent) | ClickOnceManager still hardcodes; must be updated |
| Global `killOnTerminate` only | Per-bottle kill-on-quit override | This phase | New feature; `Inherit` default preserves backward compatibility |

**Deprecated/outdated:**
- The `NSAlert.runModal()` pattern in `ClipboardManager.showLargeClipboardAlert()` blocks the main thread. For new blocking alerts, prefer SwiftUI `.alert()` or `.sheet()` modifiers. However, since `ClipboardManager` lives in WhiskyKit (not SwiftUI), the alert must be presented from the app layer.

## Open Questions

1. **ClickOnce App Type Representation**
   - What we know: `Program` expects `.exe` files and parses PE headers. ClickOnce uses `.appref-ms` files.
   - What's unclear: Should we (a) create a new `ClickOnceApp` type + shared protocol, (b) extend `Program` with `isClickOnce` flag, or (c) create a wrapper that adapts `.appref-ms` to look like a Program?
   - Recommendation: Option (b) is pragmatic -- add an `isClickOnce` flag to `Program` and skip PE parsing when true. This minimizes view changes since `ProgramsView` already iterates `[Program]`. The display name can be computed from the `.appref-ms` URL/manifest. Less clean architecturally but fastest to ship.

2. **Clipboard Alert Presentation Layer**
   - What we know: `ClipboardManager.showLargeClipboardAlert()` uses `NSAlert.runModal()` and lives in WhiskyKit. The user decision requires a "Don't warn again for this bottle" toggle, which needs bottle context.
   - What's unclear: How to pass bottle context into ClipboardManager or move the alert to the app layer.
   - Recommendation: Move the alert presentation to the app layer (Whisky target). Have ClipboardManager return a `ClipboardCheckResult` enum instead of showing alerts directly. The calling view (or extension on Program) presents the appropriate UI based on the result.

3. **ClickOnce App Execution Mechanism**
   - What we know: The user decision says to "launch" ClickOnce apps. But `.appref-ms` files are not executables.
   - What's unclear: How Wine actually runs ClickOnce apps -- does it use `rundll32.exe dfshim.dll,ShOpenVerbApplication` or something else?
   - Recommendation: Launch via `wine start /unix <path-to-appref-ms>`. Wine's `start` command should handle `.appref-ms` files like Windows does (opens with the associated handler). If that fails, fall back to `wine rundll32.exe dfshim.dll,ShOpenVerbApplication <url>`.

4. **Synchronous vs Async Cleanup in applicationWillTerminate**
   - What we know: `applicationWillTerminate` is synchronous. `TempFileTracker.cleanupAll()` is async. `ProcessRegistry.cleanup()` is async. `Wine.killBottle()` is fire-and-forget (synchronous internally).
   - What's unclear: Whether macOS gives enough time for fire-and-forget Tasks started in `applicationWillTerminate`.
   - Recommendation: For process kills, continue using the existing synchronous `Wine.killBottle()` pattern (which uses `wineserver -k`). For temp files, use synchronous `FileManager.removeItem()` directly from `getAllTrackedFiles()`. Reserve async cleanup for next-launch recovery.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** - Read all four manager implementations, BottleSettings, Program model, Wine execution engine, all UI views, AppDelegate, SettingsView, LauncherPresets, and test suite
- **Apple Developer Documentation** - NSApplicationDelegate `applicationWillTerminate` behavior, NSPasteboard threading requirements, Process/kill() signal semantics

### Secondary (MEDIUM confidence)
- **Wine documentation** - ClickOnce `.appref-ms` file handling via `wine start` command (standard Wine behavior for registered file types)
- **Existing codebase patterns** - BottleLauncherConfig/BottleInputConfig as templates for new BottleCleanupConfig

### Tertiary (LOW confidence)
- **Wine ClickOnce execution** - Exact mechanism for running `.appref-ms` via `wine start` needs testing. The `dfshim.dll` fallback is based on Windows behavior but may not be implemented in Wine.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All frameworks already in use, no new dependencies
- Architecture: HIGH - All patterns directly observed in the codebase with specific file locations
- Pitfalls: HIGH - Identified from reading actual code (hardcoded username, sync/async mismatch, Program type limitation)
- ClickOnce execution: MEDIUM - Wine's `.appref-ms` handling needs runtime validation

**Research date:** 2026-02-08
**Valid until:** 2026-03-08 (stable codebase, no external dependency changes expected)
