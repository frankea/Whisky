# Phase 3: Process Lifecycle Management - Research

**Researched:** 2026-02-09
**Domain:** Wine process management, macOS process lifecycle, SwiftUI state management
**Confidence:** HIGH

## Summary

Phase 3 involves overhauling Whisky's process tracking and management capabilities to give users accurate, real-time visibility into Wine process state per bottle, with full lifecycle management from the UI. The existing codebase provides a solid foundation: `ProcessRegistry` already tracks Whisky-launched processes with per-bottle bucketing and cleanup, `RunningProcessesView` already parses `tasklist.exe` output, `Wine.killBottle()` already calls `wineserver -k`, and the kill-on-quit infrastructure (global `killOnTerminate` + per-bottle `KillOnQuitPolicy`) is already wired end-to-end in `AppDelegate.applicationWillTerminate`.

The core work is: (1) enhancing `ProcessRegistry` to track wineserver state per prefix and support hybrid updates (event-driven from Whisky-launched processes + polling via `tasklist.exe`), (2) building a proper Processes page inside the bottle view with filtering, classification, and kill actions, (3) implementing orphan detection using `wineserver -k0` as a non-spawning probe, and (4) integrating the 3-step shutdown strategy (taskkill per-process, wineserver -k, SIGKILL fallback) into the existing kill infrastructure.

**Primary recommendation:** Evolve the existing `ProcessRegistry` and `RunningProcessesView` rather than rebuilding. The existing code handles ~60% of what's needed. Focus implementation effort on the wineserver probe, hybrid update model, shutdown orchestration, and the new Processes UI with filtering/actions.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Process visibility
- Promote and improve existing `RunningProcessesView` rather than inventing a new concept
- Dedicated Processes page/section inside each bottle (alongside Programs/Config)
- Bottle header/toolbar shows a small running indicator + count that deep-links to Processes page
- Default view: user-launched programs only (Apps)
- Toggle/filter to show system/internal processes (services.exe, explorer.exe) for debugging
- wineserver/wine64-preloader host processes in an "Advanced" section if shown at all; primary action is "Stop Bottle" rather than per-process kills on these
- Per-process row info: Name (Windows image name), PID, Memory (working set), Started (if cheap), Kind (App vs Service if classifiable)
- Row click/info drawer: executable path, command line/args, owner/source (Whisky-launched vs discovered), notes for critical processes
- Hybrid updates: event-driven instant updates from ProcessRegistry for Whisky-launched processes + background polling via `tasklist.exe` every ~2-5s while Processes view is visible; stop polling when view disappears; ensure single poll at a time

#### Cleanup behavior
- Closing bottle UI does NOT stop Wine processes; keep running with "running (N)" indicator on bottle in sidebar
- Explicit "Stop Bottle" / "Kill all processes in bottle" action available (graceful first, then force)
- Optional confirm sheet on bottle close if processes running: "Keep Running" (default) / "Stop Bottle" with "Remember for this bottle" option
- Deleting a bottle must stop processes first with confirmation before removal
- On app quit: default behavior is kill all Wine processes across all bottles (best-effort, non-blocking)
- Respect global `killOnTerminate` setting and per-bottle `killOnQuit` override
- On app quit: skip per-process graceful, go straight to `wineserver -k` (best-effort, don't block termination)
- No prompts on quit; log results, optionally show one-time warning next launch if cleanup failed
- Shutdown strategy for explicit stop: (1) `taskkill /PID <pid>` per app process, wait 3-5s; (2) `wineserver -k` for the WINEPREFIX; (3) SIGKILL remaining tracked PIDs as last resort
- Per-bottle override settings for kill-on-quit; avoid per-bottle knobs for timeouts/retry counts (keep those as internal constants)

#### Kill actions & confirmation
- Single process kill: no confirmation dialog; make it easy to relaunch
- Force kill: secondary action (hold Option/Shift) with clearer labeling, or small confirm
- Bulk actions ("Stop Bottle", "Kill all", "Kill across all bottles"): always confirm
- Per-process row: "Quit" (graceful) primary action, "Force Quit" secondary (behind menu or Option/Shift)
- Context menu: Copy PID, Show Details, Force Quit
- Per-bottle toolbar: "Stop Bottle" (graceful), "Force Stop Bottle", "Refresh"
- User-centric labeling: "Quit/Force Quit", "Stop Bottle" -- not "SIGTERM", "wineserver -k"
- Visual feedback: disable buttons + inline spinner + status text during shutdown ("Stopping...", "Still running, forcing stop...")
- Toast on completion ("Stopped 3 processes"), auto-refresh list
- Keyboard shortcuts (scoped to Processes view with selection): Delete = graceful quit, Shift+Delete = force quit, Cmd+R = refresh, Cmd+Delete = stop bottle (confirm)
- Shortcuts wired through menu items/commands for discoverability

#### Orphan detection UX
- Orphan = Wine process in a known bottle prefix but not tracked by Whisky's current session
- Detection triggers: app launch, bottle selection, Processes UI open + manual refresh, before stop/kill/delete bottle, app quit
- Non-spawning probe first (wineserver query) to check if prefix is running before heavy enumeration (`tasklist.exe`)
- Rate-limit background checks (once per bottle per minute)
- Surface orphans as "Untracked" in Processes list with Source indicator per row ("Whisky" vs "Untracked")
- Tag in Name column or dedicated hideable Source column
- Bottle list/header: badge "Running" with tooltip "Some processes were started outside Whisky" when prefix is active but no tracked processes
- Actions: per-process Quit/Force Quit, bottle-level "Clean Up Orphans" (graceful then force)
- No alert dialogs on orphan discovery; only toast if auto-cleaned in background
- Startup sweep: flag only by default, do NOT auto-clean
- Exception: if user has kill-on-quit policy enabled, auto-clean orphans on launch (graceful first, short timeout, then force) with non-blocking "Cleaned up leftover Wine processes" notice + Details affordance
- Bulk "Stop Bottle" confirmation mentions "including untracked processes"

### Claude's Discretion
- Exact polling interval tuning (2-5s range)
- tasklist.exe output parsing approach
- Non-spawning wineserver probe implementation
- Process Kind classification heuristic (App vs Service)
- Toast/notification implementation pattern
- Exact shutdown timeout constants
- Memory usage display formatting

### Deferred Ideas (OUT OF SCOPE)
- Global "All Bottles" process aggregation view -- future UX enhancement
- Crash pattern detection from process exit codes -- Phase 5 (Stability & Diagnostics)
- Process resource monitoring over time (CPU/memory graphs) -- out of scope
</user_constraints>

## Standard Stack

### Core (existing in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 15+ | Process list UI, toolbar, context menus | Already used for all views in the app |
| Foundation Process | macOS 15+ | `tasklist.exe`/`taskkill.exe`/`wineserver` execution | Already used via `Wine.runWine()`/`Wine.runWineserverProcess()` |
| os.log Logger | macOS 15+ | Process lifecycle logging | Already used throughout WhiskyKit |
| Combine/@Published | macOS 15+ | Reactive process state updates | Already used by Bottle, Program, BottleVM |

### Supporting (existing patterns)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| NSLock | Foundation | Thread-safe ProcessRegistry | Already used in ProcessRegistry |
| AsyncStream | Swift 5.9+ | Process output streaming | Already used in Process+Extensions.swift |
| Timer/Task.sleep | Foundation | Polling interval for tasklist | Use for background process refresh |
| NotificationCenter | Foundation | Cross-view event signaling (e.g. zombie cleanup toast) | Already used for `.zombieProcessesCleaned` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSLock | Swift actors | ProcessRegistry is `@unchecked Sendable` with NSLock; converting to actor would change API surface. NSLock is fine for this use case. |
| Timer polling | DispatchSource (process exit monitoring) | DispatchSource only monitors macOS PIDs, not Wine internal PIDs. Polling via `tasklist.exe` is the only way to see Windows-level process state. |
| Manual CSV parsing | Swift CSV library | Overkill for 5-column tasklist output. Simple split-on-comma with quote stripping is sufficient. |

## Architecture Patterns

### Recommended Project Structure
```
WhiskyKit/Sources/WhiskyKit/
├── ProcessRegistry.swift           # Enhanced: wineserver tracking, hybrid model, orphan detection
├── Wine/Wine.swift                 # Enhanced: wineserver probe, structured process management
├── Wine/WineProcessTypes.swift     # NEW: shared types (WineProcess, ProcessKind, ProcessSource)
├── Whisky/BottleCleanupConfig.swift # Enhanced: any new per-bottle process settings

Whisky/Views/Bottle/
├── RunningProcessesView.swift      # REWRITTEN: full Processes page with Table, toolbar, filters
├── ProcessRowView.swift            # NEW: per-process row with actions, context menu
├── ProcessDetailDrawer.swift       # NEW: info drawer for selected process details
├── BottleView.swift                # MODIFIED: uncomment processes navigation, add indicator
├── BottleListEntry.swift           # MODIFIED: running indicator badge in sidebar

Whisky/View Models/
├── ProcessesViewModel.swift        # NEW: drives Processes UI, owns polling, merges registry+tasklist
```

### Pattern 1: Hybrid Update Model
**What:** Combine event-driven updates (ProcessRegistry) with polling (tasklist.exe) for a unified process list.
**When to use:** When the Processes view is visible and needs real-time state.
**Implementation approach:**

The ViewModel maintains two data sources:
1. **ProcessRegistry** (event-driven): Instant updates for Whisky-launched processes. Registry is already in-memory and accessible synchronously.
2. **tasklist.exe polling** (background): Discovers all Wine processes in the prefix, including system processes and orphans. Runs every ~3 seconds while view is visible; stops when view disappears.

The ViewModel merges both sources: Registry entries provide "Source: Whisky" annotation and launch metadata; tasklist entries not found in the registry are marked "Source: Untracked" (orphans). The merged list is published as `@Published var processes: [WineProcess]`.

```swift
@MainActor
final class ProcessesViewModel: ObservableObject {
    @Published var processes: [WineProcess] = []
    @Published var isPolling = false
    @Published var shutdownState: ShutdownState = .idle

    private var pollingTask: Task<Void, Never>?
    private let bottle: Bottle
    private let pollingInterval: TimeInterval = 3.0  // ~3s, tunable

    func startPolling() {
        guard pollingTask == nil else { return }
        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshProcessList()
                try? await Task.sleep(for: .seconds(self?.pollingInterval ?? 3.0))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
}
```

### Pattern 2: 3-Step Shutdown Orchestration
**What:** Graceful-first, escalating shutdown for "Stop Bottle" actions.
**When to use:** Explicit user action to stop all processes in a bottle.
**Steps:**
1. `taskkill /PID <pid>` for each app-level process (graceful WM_CLOSE). Wait 3-5s.
2. `wineserver -k` for the WINEPREFIX (kills the wineserver and all child processes). Wait 2s.
3. SIGKILL remaining tracked macOS PIDs as last resort.

On app quit, skip step 1 and go straight to `wineserver -k` (non-blocking, best-effort).

### Pattern 3: Wineserver Probe for Orphan Detection
**What:** Use `wineserver -k0` (signal 0 probe) to check if a wineserver is running for a given WINEPREFIX without spawning new processes.
**When to use:** Before expensive `tasklist.exe` enumeration; at app launch, bottle selection, and before delete.
**How it works:**

`wineserver -k0` sends signal 0 to the wineserver process for the given WINEPREFIX. Signal 0 is a POSIX probe -- it checks if the process exists and is accessible without actually killing it.
- Exit code 0: wineserver is running (prefix has active processes)
- Non-zero exit code: wineserver is not running (prefix is idle)

```swift
/// Check if wineserver is running for a bottle's prefix.
/// Returns true if the prefix has an active wineserver (processes are running).
@MainActor
static func isWineserverRunning(for bottle: Bottle) async -> Bool {
    do {
        var exitCode: Int32 = 1
        for await output in try Wine.runWineserverProcess(
            name: "wineserver-probe",
            args: ["-k0"],
            bottle: bottle
        ) {
            if case let .terminated(code) = output {
                exitCode = code
            }
        }
        return exitCode == 0
    } catch {
        return false
    }
}
```

### Pattern 4: Process Kind Classification
**What:** Classify Wine processes as App vs Service for filtering.
**When to use:** Default "Apps only" filter hides internal/system processes.
**Heuristic (Claude's discretion):**

Known system/service process names:
- `services.exe`, `winedevice.exe`, `plugplay.exe`, `svchost.exe`
- `explorer.exe`, `rpcss.exe`, `tabtip.exe`, `conhost.exe`
- `start.exe` (launcher wrapper, transient)

Everything else defaults to "App". The classification is a static set lookup, not a dynamic detection. This is good enough for the "filter system processes" toggle.

```swift
enum ProcessKind: String, CaseIterable {
    case app
    case service
    case system

    static let knownServiceProcesses: Set<String> = [
        "services.exe", "winedevice.exe", "plugplay.exe",
        "svchost.exe", "rpcss.exe", "tabtip.exe", "conhost.exe"
    ]

    static let knownSystemProcesses: Set<String> = [
        "explorer.exe", "start.exe", "csrss.exe", "wininit.exe",
        "winlogon.exe", "lsass.exe", "smss.exe"
    ]

    static func classify(_ imageName: String) -> ProcessKind {
        let lower = imageName.lowercased()
        if knownServiceProcesses.contains(lower) { return .service }
        if knownSystemProcesses.contains(lower) { return .system }
        return .app
    }
}
```

### Anti-Patterns to Avoid
- **Polling when not visible:** Never poll `tasklist.exe` when the Processes view is not on screen. Use `.onAppear`/`.onDisappear` to start/stop. The `tasklist.exe` call spawns a Wine process which is expensive.
- **Multiple concurrent polls:** Guard against overlapping `tasklist.exe` invocations. Use a single Task with sequential polling, not Timer-based fire-and-forget.
- **Blocking shutdown on app quit:** `applicationWillTerminate` must not `await`. Use fire-and-forget `wineserver -k` calls (which is what `Wine.killBottle()` already does).
- **Killing wineserver/wine64-preloader directly:** These are host processes; killing them kills all Wine processes in the prefix. Only use as "Stop Bottle" (step 2), never as individual process kill.
- **SIGKILL as first resort:** Always try graceful shutdown first. SIGKILL can leave Wine prefix state corrupted (dangling locks in wineserver shared memory).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Wine process enumeration | Custom `ps`/`pgrep` parsing | `tasklist.exe` via `Wine.runWine()` | `tasklist.exe` shows Windows-level processes with Windows PIDs. macOS PIDs from `ps` don't map cleanly to Wine internal processes. |
| Wine process termination | Direct SIGTERM/SIGKILL to macOS PIDs | `taskkill.exe` via `Wine.runWine()` for per-process, `wineserver -k` for bottle-level | Wine processes run under wineserver; direct signals may not clean up Windows state properly. `taskkill` sends proper WM_CLOSE messages. |
| Wineserver status check | File system socket checks | `wineserver -k0` (signal 0 probe) | Socket path is implementation-dependent and varies across Wine versions. `-k0` is the documented probe mechanism. |
| CSV parsing for tasklist | Full CSV parser library | Simple `String.split(separator: ",")` + quote stripping | tasklist outputs 5 fixed columns, no embedded commas in field values. Simple parsing is correct and sufficient. |
| Toast/notification UI | Custom notification system | Existing `ToastData` + `.toast()` modifier | Already implemented in `StatusToast.swift`, used throughout the app. Supports `.success`, `.error`, `.info` styles with auto-dismiss. |

**Key insight:** Wine provides Windows-compatible tools (`tasklist.exe`, `taskkill.exe`) that operate at the correct abstraction level. The app should use these rather than trying to map between macOS process IDs and Wine internal state.

## Common Pitfalls

### Pitfall 1: PID Confusion (macOS PID vs Wine PID)
**What goes wrong:** Wine processes have both a macOS PID (the actual process on the host) and a Windows PID (assigned by wineserver). `tasklist.exe` reports Windows PIDs. `ProcessRegistry` currently tracks macOS PIDs (from `Process.processIdentifier`). Kill operations via `taskkill.exe` use Windows PIDs, while `kill()` syscall uses macOS PIDs.
**Why it happens:** Wine is a compatibility layer that creates its own process abstraction.
**How to avoid:** The `WineProcess` model should track both PID types. Use Windows PIDs for display and for `taskkill.exe` operations. Use macOS PIDs only for the SIGKILL fallback (step 3 of shutdown). Document clearly which PID type each field represents.
**Warning signs:** "Process not found" errors when trying to kill by PID; wrong process killed.

### Pitfall 2: tasklist.exe Output Parsing Quirks
**What goes wrong:** Wine's `tasklist.exe` output may differ from Windows. The existing code splits on commas but doesn't strip quotes. Fields may contain `"Image Name","PID","Session Name","Session#","Mem Usage"` with quoted values.
**Why it happens:** Wine's implementation mimics Windows but may have formatting differences.
**How to avoid:** Strip leading/trailing `"` from each field after splitting. Skip the header line (first line). Handle empty output gracefully (wineserver not running). The current RunningProcessesView's parsing is minimal -- enhance it with proper quote handling.
**Warning signs:** Process names displayed with surrounding quotes; PID parsing failures.

### Pitfall 3: Race Between Stop and Refresh
**What goes wrong:** User clicks "Stop Bottle", shutdown begins, but a concurrent poll refreshes the process list and shows stale data or re-adds processes that are being killed.
**Why it happens:** Polling and shutdown run concurrently.
**How to avoid:** Set a `shutdownState` flag that pauses polling during shutdown. Only resume polling after shutdown completes. Show "Stopping..." UI state instead of stale process data.
**Warning signs:** Process list flickers during shutdown; stopped processes reappear momentarily.

### Pitfall 4: Orphan Detection False Positives
**What goes wrong:** `wineserver -k0` reports a running wineserver, but all processes have exited. The wineserver persists briefly after the last process exits (configurable persistence timeout, default 3 seconds).
**Why it happens:** wineserver has a `-p` (persistence) option that keeps it alive for a configurable delay.
**How to avoid:** After `wineserver -k0` returns success, confirm with `tasklist.exe` enumeration. If tasklist returns empty, treat the prefix as idle (wineserver will exit on its own). Rate-limit checks to once per minute per bottle to avoid hammering.
**Warning signs:** "Running" badge appears briefly after all programs close, then disappears.

### Pitfall 5: Blocking App Quit
**What goes wrong:** `applicationWillTerminate` hangs waiting for async cleanup.
**Why it happens:** The existing implementation uses fire-and-forget `Wine.killBottle()` which is correct, but new code might accidentally introduce `await`.
**How to avoid:** Keep `applicationWillTerminate` synchronous. Use `Wine.killBottle()` (which already wraps `wineserver -k` in a fire-and-forget `Task`). Never `await` in this method. Log results for post-mortem review.
**Warning signs:** App hangs on quit; force quit required.

### Pitfall 6: ProcessRegistry Stale Entries
**What goes wrong:** Registry tracks a Whisky-launched process, but the process has crashed or been killed externally. Registry still shows it as active.
**Why it happens:** ProcessRegistry only unregisters via explicit `unregister(pid:)` or cleanup. No automatic detection of process death.
**How to avoid:** During each polling cycle, cross-reference registry entries against tasklist output. If a registry PID is not found in tasklist, mark it as terminated and unregister. This is the "hybrid" model -- registry provides immediate awareness, polling provides ground truth.
**Warning signs:** Process count badge shows stale number; "ghost" entries in process list.

## Code Examples

### Wineserver Probe (checking if prefix has active processes)
```swift
// Source: Wine.swift pattern + wineserver man page
// Run wineserver -k0 with WINEPREFIX set to the bottle's path
// Exit code 0 = running, non-zero = not running
@MainActor
static func isWineserverRunning(for bottle: Bottle) async -> Bool {
    do {
        var exitCode: Int32 = 1
        for await output in try runWineserverProcess(
            name: "wineserver-probe",
            args: ["-k0"],
            bottle: bottle
        ) {
            if case let .terminated(code) = output {
                exitCode = code
            }
        }
        return exitCode == 0
    } catch {
        return false
    }
}
```

### tasklist.exe CSV Parsing
```swift
// Source: existing RunningProcessesView.fetchProcesses() pattern, enhanced
// Output format: "Image Name","PID","Session Name","Session#","Mem Usage"
func parseTasklistOutput(_ output: String) -> [WineProcess] {
    var processes: [WineProcess] = []
    let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

    for line in lines {
        let fields = line.split(separator: ",").map { field in
            // Strip surrounding quotes
            var s = String(field).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("\"") && s.hasSuffix("\"") {
                s = String(s.dropFirst().dropLast())
            }
            return s
        }

        guard fields.count >= 5 else { continue }
        // Skip header line
        guard fields[1] != "PID" else { continue }

        let imageName = fields[0]
        let winePID = Int32(fields[1]) ?? 0
        let memUsage = fields[4]  // e.g., "24 K" or "1,024 K"
        let kind = ProcessKind.classify(imageName)

        processes.append(WineProcess(
            imageName: imageName,
            winePID: winePID,
            memoryUsage: memUsage,
            kind: kind,
            source: .untracked  // Will be updated during merge
        ))
    }
    return processes
}
```

### Merging Registry + tasklist (Hybrid Model)
```swift
// Source: pattern for ProcessesViewModel
func mergeProcessSources(
    registryProcesses: [ProcessRegistry.ProcessInfo],
    tasklistProcesses: [WineProcess]
) -> [WineProcess] {
    var merged: [WineProcess] = []
    var matchedWinePIDs: Set<Int32> = []

    // For each tasklist process, check if it's tracked in registry
    for var taskProc in tasklistProcesses {
        if let regInfo = registryProcesses.first(where: {
            // Match by program name (registry has macOS PID, tasklist has Wine PID)
            $0.programName.lowercased() == taskProc.imageName.lowercased()
        }) {
            taskProc.source = .whisky
            taskProc.launchTime = regInfo.launchTime
            taskProc.macosPID = regInfo.pid
            matchedWinePIDs.insert(taskProc.winePID)
        }
        merged.append(taskProc)
    }

    return merged
}
```

### 3-Step Shutdown
```swift
// Source: existing ProcessRegistry.cleanup() + Wine.killBottle() patterns
func stopBottle(_ bottle: Bottle) async {
    shutdownState = .stopping

    // Step 1: Graceful per-process kill via taskkill
    let appProcesses = processes.filter { $0.kind == .app }
    for process in appProcesses {
        try? await Wine.runWine(
            ["taskkill.exe", "/PID", String(process.winePID)],
            bottle: bottle
        )
    }

    // Wait for graceful shutdown
    try? await Task.sleep(for: .seconds(4))
    await refreshProcessList()

    // Step 2: wineserver -k (kills all processes in prefix)
    if !processes.isEmpty {
        shutdownState = .forceKilling
        try? await Wine.runWine([], bottle: nil)  // placeholder
        Wine.killBottle(bottle: bottle)  // wineserver -k, fire-and-forget
        try? await Task.sleep(for: .seconds(2))
    }

    // Step 3: SIGKILL remaining tracked macOS PIDs
    let remaining = ProcessRegistry.shared.getProcesses(for: bottle)
    for info in remaining where info.pid > 0 {
        kill(info.pid, SIGKILL)
    }

    // Clear registry
    ProcessRegistry.shared.cleanup(for: bottle, force: true)
    shutdownState = .idle
    await refreshProcessList()
}
```

### Sidebar Running Indicator
```swift
// Source: existing BottleListEntry pattern
// Add running indicator to bottle list entry in sidebar
HStack {
    Text(name)
    Spacer()
    if runningCount > 0 {
        Text("\(runningCount)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(.blue)
    }
}
```

## State of the Art

| Old Approach (current code) | New Approach (Phase 3) | Impact |
|-----|------|--------|
| ProcessRegistry tracks macOS PIDs only | Track wineserver state + merge with tasklist Wine PIDs | Accurate cross-reference between Whisky-launched and external processes |
| RunningProcessesView: manual refresh only, no filtering | Hybrid auto-polling + event-driven, with App/Service/System filters | Real-time process visibility without manual clicks |
| Wine.killBottle() is the only kill action | 3-step shutdown + per-process graceful/force kill | Granular control without killing the whole bottle |
| No orphan detection | wineserver probe + tasklist enumeration on trigger events | Stale processes from previous sessions are surfaced and manageable |
| Processes tab commented out in BottleView | Full Processes page with Table, toolbar, context menus | First-class process management UI |
| Bottle removal ignores running processes | Pre-deletion check with confirmation and auto-cleanup | No more orphaned processes from deleted bottles |

**Current code to modify (not deprecated):**
- `ProcessRegistry.swift` -- extend, don't replace. Add wineserver tracking, source annotation.
- `RunningProcessesView.swift` -- substantial rewrite as the new Processes page.
- `BottleView.swift` -- uncomment processes NavigationLink (line 61-63), add running indicator.
- `BottleListEntry.swift` -- add running count badge.
- `AppDelegate.swift` -- extend `applicationWillTerminate` and `applicationDidFinishLaunching` with orphan sweep logic.
- `Wine.swift` -- add `isWineserverRunning()` probe method, possibly add structured tasklist/taskkill convenience methods.
- `Bottle+Extensions.swift` -- modify `remove(delete:)` to check for running processes before deletion.

## Open Questions

1. **tasklist.exe output format in Wine on macOS**
   - What we know: The existing `RunningProcessesView.fetchProcesses()` splits on commas and gets `pid` from index 1, `procName` from index 0. This works today.
   - What's unclear: Whether Wine's tasklist.exe outputs with or without quotes, whether `/FO CSV` flag is needed, and whether the header line is included.
   - Recommendation: Test empirically during implementation. Add defensive quote-stripping and header-skip logic. The cost of robustness here is minimal.

2. **wineserver -k0 behavior on macOS/WhiskyWine**
   - What we know: `wineserver -k0` is documented to send signal 0 (probe) to the wineserver for the WINEPREFIX. This is the standard non-spawning probe.
   - What's unclear: Whether WhiskyWine's build of wineserver supports this flag identically to upstream Wine. The existing code uses `wineserver -k` (without the 0) successfully.
   - Recommendation: Test `wineserver -k0` during implementation. Fallback: check for wineserver socket file existence in the prefix's temp directory if `-k0` is unreliable.

3. **Matching registry entries to tasklist entries**
   - What we know: Registry stores program name + macOS PID. tasklist reports Windows image name + Wine PID. These are different namespaces.
   - What's unclear: Whether program name matching (e.g., `game.exe` in registry vs `game.exe` in tasklist) is reliable across all programs. Some launchers spawn child processes with different names.
   - Recommendation: Match by program name (case-insensitive) as primary key. Accept that some matches will be imperfect. The "Source" indicator (Whisky vs Untracked) is informational, not security-critical.

4. **Memory usage parsing from tasklist**
   - What we know: Windows tasklist shows memory like `"24 K"` or `"1,024 K"`.
   - What's unclear: Exact format from Wine's implementation (may use different locale formatting).
   - Recommendation: Display memory as raw string from tasklist initially. Parse to numeric for sorting if needed. Formatting is Claude's discretion.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** - Direct reading of all relevant source files (ProcessRegistry.swift, RunningProcessesView.swift, Wine.swift, Process+Extensions.swift, BottleView.swift, AppDelegate.swift, BottleSettings.swift, BottleCleanupConfig.swift, ContentView.swift, Bottle+Extensions.swift, ConfigView.swift, SettingsView.swift, StatusToast.swift)
- **[wineserver man page](https://man.archlinux.org/man/wineserver.1.en)** - `-k[n]` flag documentation, signal 0 probe
- **[tasklist Microsoft Learn](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-xp/bb491010(v=technet.10))** - CSV output format, column documentation
- **[taskkill Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/taskkill)** - `/PID` graceful vs `/F` force kill semantics

### Secondary (MEDIUM confidence)
- **[WineHQ wineserver page](https://wiki.winehq.org/Wineserver)** - General wineserver behavior, persistence timeout
- **[WineHQ Commands list](https://wiki.winehq.org/List_of_Commands)** - Available Wine commands
- **[WineHQ Forum: detecting wineserver](https://forum.winehq.org/viewtopic.php?t=28967&p=110950)** - Community discussion of wineserver probe techniques

### Tertiary (LOW confidence)
- **[WineHQ Forum: killing processes](https://forum.winehq.org/viewtopic.php?t=12346)** - Community approaches (needs validation against macOS/WhiskyWine)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries are already in use in the codebase; no new dependencies needed.
- Architecture: HIGH - Patterns are direct extensions of existing code (ProcessRegistry, Wine.swift, toast system, NavigationStack). Low novelty risk.
- Pitfalls: HIGH - Based on direct codebase reading (PID confusion between macOS/Wine PIDs, existing ProcessRegistry limitations, applicationWillTerminate constraints).
- Wine tooling: MEDIUM - wineserver -k0 probe and tasklist CSV format need empirical validation against WhiskyWine's macOS build. Documented behavior may differ slightly.

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (stable domain; Wine tools change slowly)
