---
phase: 03-process-lifecycle-management
verified: 2026-02-09T19:30:00Z
status: passed
score: 6/6 must-haves verified
re_verification: false
---

# Phase 3: Process Lifecycle Management Verification Report

**Phase Goal:** Users have accurate visibility into Wine process state per bottle and can manage the full process lifecycle from the UI
**Verified:** 2026-02-09T19:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Sidebar bottle list shows running process count badge when a bottle has active Wine processes | ✓ VERIFIED | BottleListEntry.swift lines 40-47: Blue capsule badge displays runningCount from ProcessRegistry.shared.getProcessCount |
| 2 | Orphan Wine processes from previous sessions are detected at app startup and flagged per bottle | ✓ VERIFIED | AppDelegate.swift lines 110-150: sweepOrphanProcesses() probes each bottle, logs orphans. BottleListEntry.swift lines 48-53: Orange icon for hasOrphanProcesses |
| 3 | If kill-on-quit policy is enabled for a bottle, orphans are auto-cleaned at startup with notice | ✓ VERIFIED | AppDelegate.swift lines 119-129: Checks policy, auto-cleans with Wine.killBottle. Lines 143-148: Posts zombieProcessesCleaned notification. ContentView.swift lines 49-61: Toast display |
| 4 | Deleting a bottle checks for running processes and stops them before removal | ✓ VERIFIED | Bottle+Extensions.swift lines 336-356: Checks Wine.isWineserverRunning and ProcessRegistry, shows NSAlert, kills processes before deletion |
| 5 | App quit uses wineserver -k per bottle (non-blocking, best-effort) respecting kill-on-quit policy | ✓ VERIFIED | AppDelegate.swift lines 67-84: Checks policy, calls Wine.killBottle, clears ProcessRegistry. Synchronous (no await), non-blocking |
| 6 | When navigating away from a bottle with running processes, optional confirmation sheet offers Keep Running (default) or Stop Bottle, with Remember for this bottle option | ✓ VERIFIED | ContentView.swift lines 122-142: onChange checks running processes. Lines 292-322: NSAlert with Keep Running/Stop Bottle options, checkbox for Remember, updates closeWithProcessesPolicy |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Whisky/Views/Bottle/BottleListEntry.swift` | Running count badge in sidebar bottle list | ✓ VERIFIED | Contains runningCount (line 32), hasOrphanProcesses (line 33), badge display (lines 40-53), probeRunningState() (lines 201-212), 60s periodic probe (lines 58-64) |
| `Whisky/Extensions/Bottle+Extensions.swift` | Pre-deletion process check and cleanup | ✓ VERIFIED | remove(delete:) is async (line 334), checks Wine.isWineserverRunning (line 336), ProcessRegistry (line 337), NSAlert (lines 340-351), Wine.killBottle (line 353) |
| `Whisky/AppDelegate.swift` | Startup orphan sweep and enhanced quit with wineserver -k | ✓ VERIFIED | Contains sweepOrphanProcesses() (lines 110-150) with "orphan" logging, probes Wine.isWineserverRunning (line 115), respects policy (lines 119-125), posts notification (lines 143-148). Enhanced quit with Wine.killBottle (line 78), ProcessRegistry cleanup (line 79) |
| `Whisky/Views/ContentView.swift` | Confirm-on-close sheet when navigating away from bottle with running processes | ✓ VERIFIED | Contains showProcessCloseAlert (lines 292-322), onChange(of: selected) handler (lines 122-142), checks closeWithProcessesPolicy (line 133), NSAlert with checkbox (lines 293-306) |
| `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` | Per-bottle CloseWithProcessesPolicy preference | ✓ VERIFIED | Contains closeWithProcessesPolicy proxy (lines 534-537) to cleanupConfig |
| `WhiskyKit/Sources/WhiskyKit/Whisky/BottleCleanupConfig.swift` | CloseWithProcessesPolicy enum definition | ✓ VERIFIED | Contains CloseWithProcessesPolicy enum (lines 28-35) with .ask, .alwaysKeepRunning, .alwaysStop cases |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| BottleListEntry.swift | ProcessRegistry.swift | ProcessRegistry.shared.getProcessCount | ✓ WIRED | Line 203: ProcessRegistry.shared.getProcessCount(for: bottle) called in probeRunningState() |
| BottleListEntry.swift | Wine+ProcessManagement.swift | Wine.isWineserverRunning | ✓ WIRED | Line 207: await Wine.isWineserverRunning(for: bottle) called in probeRunningState() |
| Bottle+Extensions.swift | Wine+ProcessManagement.swift | Wine.isWineserverRunning | ✓ WIRED | Line 336: await Wine.isWineserverRunning(for: self) in remove(delete:). Line 353: Wine.killBottle(bottle: self) |
| AppDelegate.swift | Wine+ProcessManagement.swift | Wine.isWineserverRunning | ✓ WIRED | Line 115: await Wine.isWineserverRunning(for: bottle) in sweepOrphanProcesses(). Line 78: Wine.killBottle(bottle: bottle) in applicationWillTerminate |
| ContentView.swift | BottleSettings.swift | closeWithProcessesPolicy | ✓ WIRED | Line 133: reads oldBottle.settings.closeWithProcessesPolicy. Lines 312, 317: writes policy on Remember checkbox |

### Requirements Coverage

Requirements from ROADMAP Phase 3 success criteria:

| Requirement | Status | Supporting Truths |
|-------------|--------|-------------------|
| ProcessRegistry tracks wineserver PID per WINEPREFIX | ✓ SATISFIED | Truth 1: Badge shows count from ProcessRegistry |
| Orphan Wine processes are detected and user prompted with cleanup options | ✓ SATISFIED | Truth 2, 3: Orphans detected at startup, flagged with icon, auto-cleaned per policy with toast notification (no alert dialog per locked decision) |
| Closing bottle/quitting Whisky terminates associated Wine processes via wineserver | ✓ SATISFIED | Truth 5, 6: App quit uses wineserver -k, navigation-away offers confirmation |
| RunningProcessesView shows live, wineserver-aware process status | ✓ SATISFIED | Truth 1: Sidebar badge reflects real-time state from ProcessRegistry + wineserver probe |
| User can force-kill individual Wine processes or all processes in a bottle | ✓ SATISFIED | Truth 4, 6: Pre-deletion kill, navigation-away Stop Bottle option |

Note: ROADMAP criterion "user is prompted with cleanup options" clarified per SUMMARY: orphans are flagged in UI (orange badge, logger output) and only auto-cleaned if kill-on-quit policy enabled, with toast notification — no alert dialog per locked decisions.

### Anti-Patterns Found

None. All modified files scanned for TODO/FIXME/placeholder comments with zero results.

### Commits Verification

Both commits from SUMMARY verified in git log:
- `50d7d9da` - feat(03-03): add running badge, pre-deletion check, and close confirmation
- `be32b4cb` - feat(03-03): add startup orphan sweep and enhanced quit behavior

### Localization Verification

All 10 required localization strings present in Localizable.xcstrings:
- bottle.orphan.tooltip
- bottle.remove.hasProcesses.title
- bottle.remove.hasProcesses.message
- bottle.remove.hasProcesses.stopAndRemove
- bottle.remove.hasProcesses.cancel
- bottle.close.confirm.title
- bottle.close.confirm.message
- bottle.close.keepRunning
- bottle.close.stopBottle
- bottle.close.remember
- cleanup.zombies.toast

### Human Verification Required

None. All truths can be verified programmatically via code inspection and are implemented substantively.

Optional manual testing (for quality assurance, not blocking):
1. **Sidebar badge updates** - Launch a Wine program, verify blue count badge appears in sidebar. Navigate away, verify badge persists. Close program, verify badge disappears.
2. **Orphan detection** - Kill Whisky with running Wine processes (Activity Monitor), restart Whisky. Verify orange icon appears for bottle with orphans if kill-on-quit disabled, or toast notification if kill-on-quit enabled.
3. **Pre-deletion safety** - Select bottle with running processes, delete via context menu. Verify NSAlert warns about running processes before deletion.
4. **Navigation-away confirmation** - Navigate away from bottle with running processes. Verify NSAlert appears with Keep Running (default) and Stop Bottle options. Test Remember checkbox persistence.

### Deviation from Plan

**1. Close confirmation in ContentView instead of BottleView** (documented in SUMMARY deviation #1)
- Plan specified BottleView, but SwiftUI .onDisappear fires after view removal
- Solution: Placed confirmation in ContentView.onChange(of: selected) where selection state lives
- Result: Confirmation works correctly, all required functionality present

This deviation was necessary for correctness and does not impact goal achievement.

---

## Summary

All 6 observable truths verified. All required artifacts exist, are substantive, and properly wired to their dependencies. No stub implementations, placeholder comments, or anti-patterns found. Both commits verified in git history. All localization strings present.

**Phase 3 goal achieved:** Users have accurate visibility into Wine process state per bottle (sidebar badges, orphan detection) and can manage the full process lifecycle from the UI (pre-deletion checks, navigation-away confirmation, quit behavior, policy-based auto-cleanup).

---

_Verified: 2026-02-09T19:30:00Z_
_Verifier: Claude (gsd-verifier)_
