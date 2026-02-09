# Phase 3: Process Lifecycle Management - Context

**Gathered:** 2026-02-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Users have accurate visibility into Wine process state per bottle and can manage the full process lifecycle from the UI. Covers wineserver-level tracking, orphan detection, process cleanup, and kill actions. Does not include crash diagnostics (Phase 5) or log parsing.

</domain>

<decisions>
## Implementation Decisions

### Process visibility
- Promote and improve existing `RunningProcessesView` rather than inventing a new concept
- Dedicated Processes page/section inside each bottle (alongside Programs/Config)
- Bottle header/toolbar shows a small running indicator + count that deep-links to Processes page
- Default view: user-launched programs only (Apps)
- Toggle/filter to show system/internal processes (services.exe, explorer.exe) for debugging
- wineserver/wine64-preloader host processes in an "Advanced" section if shown at all; primary action is "Stop Bottle" rather than per-process kills on these
- Per-process row info: Name (Windows image name), PID, Memory (working set), Started (if cheap), Kind (App vs Service if classifiable)
- Row click/info drawer: executable path, command line/args, owner/source (Whisky-launched vs discovered), notes for critical processes
- Hybrid updates: event-driven instant updates from ProcessRegistry for Whisky-launched processes + background polling via `tasklist.exe` every ~2-5s while Processes view is visible; stop polling when view disappears; ensure single poll at a time

### Cleanup behavior
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

### Kill actions & confirmation
- Single process kill: no confirmation dialog; make it easy to relaunch
- Force kill: secondary action (hold Option/Shift) with clearer labeling, or small confirm
- Bulk actions ("Stop Bottle", "Kill all", "Kill across all bottles"): always confirm
- Per-process row: "Quit" (graceful) primary action, "Force Quit" secondary (behind menu or Option/Shift)
- Context menu: Copy PID, Show Details, Force Quit
- Per-bottle toolbar: "Stop Bottle" (graceful), "Force Stop Bottle", "Refresh"
- User-centric labeling: "Quit/Force Quit", "Stop Bottle" — not "SIGTERM", "wineserver -k"
- Visual feedback: disable buttons + inline spinner + status text during shutdown ("Stopping...", "Still running, forcing stop...")
- Toast on completion ("Stopped 3 processes"), auto-refresh list
- Keyboard shortcuts (scoped to Processes view with selection): Delete = graceful quit, Shift+Delete = force quit, Cmd+R = refresh, Cmd+Delete = stop bottle (confirm)
- Shortcuts wired through menu items/commands for discoverability

### Orphan detection UX
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

</decisions>

<specifics>
## Specific Ideas

- "Keep labeling user-centric — Quit/Force Quit, Stop Bottle — not SIGTERM, wineserver -k"
- Existing `RunningProcessesView.swift` and `BottleView.swift` wiring should be the starting point — promote and improve, don't reinvent
- Global "All bottles" process view is a nice-to-have for later, not required for this phase
- Per-bottle "remember kill-on-close" behavior inspired by macOS "Keep Windows" pattern

</specifics>

<deferred>
## Deferred Ideas

- Global "All Bottles" process aggregation view — future UX enhancement
- Crash pattern detection from process exit codes — Phase 5 (Stability & Diagnostics)
- Process resource monitoring over time (CPU/memory graphs) — out of scope

</deferred>

---

*Phase: 03-process-lifecycle-management*
*Context gathered: 2026-02-09*
