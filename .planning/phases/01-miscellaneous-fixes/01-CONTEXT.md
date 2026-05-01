# Phase 1: Miscellaneous Fixes - Context

**Gathered:** 2026-02-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Close out PR #79 with ClickOnce application support, clipboard safety for multiplayer games, automatic temp file cleanup, and basic process resource management. All four components have backend implementations in progress (ClickOnceManager, ClipboardManager, TempFileTracker, ProcessRegistry). This phase finalizes them with UI integration, proper lifecycle hooks, and user-facing behavior.

</domain>

<decisions>
## Implementation Decisions

### ClickOnce app presentation
- ClickOnce apps are first-class launchable entries in the bottle's Programs list, not just auto-pins
- Represent each app by its `.appref-ms` file (the stable on-disk artifact to launch)
- Display name: friendly app name (strip `.appref-ms` and trailing `.application` from manifest URL); fall back to `.appref-ms` filename if parsing fails
- Show a "ClickOnce" badge or separate section in the Programs list; generic icon is fine; no architecture tag
- Do NOT surface internal ClickOnce cache executables as separate programs (too noisy/confusing)
- Management actions parallel regular Programs: Run, Run in Terminal (Shift), Pin/Unpin, Show in Finder, Create Shortcut, plus ClickOnce-specific: Copy Deployment URL, Remove/Forget (.appref-ms + optionally clear cache)
- Auto-detect ClickOnce apps when a bottle is opened or Programs view appears; fast-gated (`if ClickOnce dir exists`), background scan, cached, refresh on directory change
- Provide a manual "Rescan ClickOnce apps" action as fallback
- Best-effort live detection: if a ClickOnce app is installed inside Wine, it appears in the program list on next view-appear or background refresh (not instant notifications)

### Clipboard intervention
- Clipboard safeguards activate at launch time, right before starting a Wine process
- For known multiplayer launchers (`LauncherType.usesClipboard` = true): auto-clear large clipboard content, show a brief non-blocking toast ("Clipboard cleared to prevent game hang" with type/size)
- For other programs with large clipboard: show a blocking alert/sheet explaining the risk, approximate size, truncated text preview (text only), with "Clear Clipboard" (recommended) and "Keep" buttons; optional "Don't warn again for this bottle" toggle
- Per-bottle setting with 4 options: `Auto (Recommended)` (default — auto-clear for known launchers, warn for others), `Always warn`, `Always clear on launch`, `Never warn/clear`
- Keep 10 KB as the default "large" threshold (`ClipboardManager.largeContentThreshold`); allow per-bottle override in the setting
- Images/unknown types treated more conservatively than text

### Cleanup feedback
- Temp file cleanup is **silent by default** — no toasts, no alerts, only `os_log` for diagnostics
- Show a non-blocking warning toast only if cleanup repeatedly fails while the app is still running ("Couldn't remove some temporary files; will retry later" with "Show Details" affordance)
- On app quit: never block termination for cleanup; just log and retry next launch
- Zombie process cleanup: no UI if cleanup succeeds silently; if processes were force-killed, show a single non-blocking toast per bottle ("Cleaned up leftover Wine processes in '<Bottle Name>' (3)") with optional "Details" action
- Use a **blocking alert** only when killing processes the user likely considers "active" (bottle has running apps and user initiated close/quit)
- No persistent cleanup history in the UI; cleanup events go to logs/diagnostics only; optionally surface in an "Advanced Diagnostics" view if one exists

### Cleanup triggers
- **Temp files**: (1) immediately after use when consumer has read it, (2) on associated Wine process exit, (3) on bottle shutdown/close, (4) best-effort `cleanupAll()` on app quit (never block termination), (5) `cleanupOldFiles(olderThan:)` on next launch or periodically to catch orphans from crashes (>24h)
- **Zombie processes**: (1) on app launch — background sweep for crash leftovers, (2) on bottle open / Programs view — quick check if no tracked processes, (3) before launching a program — reconcile stray wineserver for the prefix, (4) on user-initiated bottle stop/close and on app quit
- Only act on processes that clearly belong to a Whisky bottle (match `WINEPREFIX` to known bottle paths); rate-limit sweeps
- On crash recovery (next launch): auto-cleanup orphaned temp files older than safety window + graceful SIGTERM → SIGKILL escalation for orphaned Wine processes; silent unless it fails
- Per-bottle "Kill on quit" setting with 3 states: `Inherit (default)`, `Always kill on app quit`, `Never kill on app quit` — overrides the existing global `killOnTerminate` setting

### Claude's Discretion
- Exact toast/banner implementation (SwiftUI overlay vs system notification)
- ClickOnce directory watching mechanism (FSEvents, polling interval, etc.)
- Cleanup retry timing and backoff strategy details
- Rate-limiting approach for zombie process sweeps
- Internal cache structure for ClickOnce scan results

</decisions>

<specifics>
## Specific Ideas

- ClickOnce apps should "just appear" like regular programs — users shouldn't need to know about `.appref-ms` internals
- Clipboard toast should mention detected content type (text/image/other) and approximate size
- Cleanup should never block app termination — best-effort on quit, retry on next launch
- The per-bottle clipboard setting avoids surprising global clipboard changes while letting power users force a policy for problematic bottles
- "Kill on quit" override uses `Inherit` as default so current global behavior doesn't change

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-miscellaneous-fixes*
*Context gathered: 2026-02-08*
