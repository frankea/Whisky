# Pitfalls Research

**Domain:** Wine GUI manager (macOS) -- issue backlog resolution, configuration UI, game compatibility, process management
**Researched:** 2026-02-08
**Confidence:** MEDIUM-HIGH (domain expertise from codebase analysis + community evidence; some macOS-specific areas are LOW due to limited public documentation)

## Critical Pitfalls

### Pitfall 1: Treating Wine-Layer Bugs as App-Layer Fixable

**What goes wrong:**
The app layer adds environment variables, registry tweaks, or DLL overrides that appear to fix a Wine-layer issue in one scenario but silently break other games or configurations. For example, setting `WINEFSYNC=0` globally to fix Steam on macOS 15.4 may cause performance regressions in games that benefit from fsync. Setting `D3DM_FORCE_D3D11=1` for launcher compatibility may prevent D3D12-only games from rendering. The codebase already shows this tension: `MacOSCompatibility.swift` sets `WINEFSYNC=0` on macOS 15.4+ globally, while `BottleSettings.swift` may then try to re-enable esync, creating conflicting override chains.

**Why it happens:**
Developers conflate "the app can set environment variables" with "the app can fix the problem." Wine environment variables are heuristic workarounds with side effects, not surgical fixes. The actual bugs live in Wine's D3DMetal translation, wineserver syscall handling, or MoltenVK shader compilation -- layers the app cannot modify.

**How to avoid:**
- Treat every environment variable override as a **per-bottle or per-program** setting, never a global default. The current `MacOSCompatibility.swift` applies fixes to ALL bottles regardless of what they run.
- Implement an explicit **precedence documentation system**: macOS compat fixes < bottle defaults < launcher presets < user overrides. The current code has this cascade implicit in the order of `environmentVariables()` calls but it is not tested or documented as a contract.
- For each Wine-layer workaround, document **what it breaks** alongside what it fixes. Add this to the launcher preset descriptions (currently `LauncherPresets.swift` only documents what each preset fixes, e.g., `fixesDescription`).
- Add an **environment variable diff view** so users can see exactly what env vars are being set before launch. This makes debugging feasible without reading source code.

**Warning signs:**
- Issue reports saying "Game X stopped working after I enabled launcher compatibility for Game Y in the same bottle"
- The `environmentVariables()` method in `BottleSettings.swift` growing past its current 100+ lines with more conditional branches
- Settings that override each other silently (e.g., Sequoia compat mode sets `MTL_DEBUG_LAYER=0` but Metal Validation setting sets `MTL_DEBUG_LAYER=1` -- last-write-wins is currently position-dependent)

**Phase to address:**
Graphics configuration UI phase. This is the phase where DXVK/Metal/D3DMetal settings become user-facing, so the precedence model must be solid before exposing controls.

---

### Pitfall 2: Building a Stale Compatibility Database

**What goes wrong:**
Game compatibility data becomes misleading within weeks because it is version-coupled to specific combinations of: Wine version, macOS version, game patch version, DXVK version, and GPU hardware. ProtonDB suffers this exact problem -- games rated "Platinum" have comment threads full of "doesn't work anymore since update X." The upstream Whisky project maintained a community game list (Discussion #348) that became unreliable as Wine versions changed. Building a database that appears authoritative but contains stale data is worse than having no database at all, because users trust it and waste hours on configurations that no longer apply.

**Why it happens:**
Compatibility databases are easy to seed (collect initial reports) but extremely hard to maintain (validate reports still hold after any component changes). Every macOS point release can break previously working games (macOS 15.3 vs 15.4 vs 15.4.1 all behaved differently per `MacOSCompatibility.swift`). Every Wine update changes compatibility. Game updates change requirements. Without an automated re-validation mechanism, data decays faster than it can be manually updated.

**How to avoid:**
- Do NOT build a traditional "works/broken" database. Instead, build a **troubleshooting guide system** that recommends settings to try, ordered by likelihood. "If Game X shows black screen, try: (1) Enable DXVK, (2) Force D3D11, (3) Set locale to en_US.UTF-8" is actionable regardless of version. "Game X: Gold rating" is not.
- Attach **version tuples** to every compatibility entry: `(macOS version, Wine version, game version, date)`. Display staleness prominently: "This report is from 3 months ago with Wine 9.x; you are on Wine 11.0."
- Implement **user feedback loops**: after suggesting settings, ask "Did this help?" to surface stale recommendations.
- Keep the database **small and curated** rather than crowd-sourced. Focus on the top 20-50 most-requested games from upstream issues rather than trying to cover thousands.

**Warning signs:**
- Users opening issues saying "I followed the compatibility guide for Game X but it doesn't work"
- Database entries without version information attached
- No process for invalidating entries when Wine or macOS is updated

**Phase to address:**
Game compatibility guidance phase (#48). Must be designed as "living troubleshooting guides" rather than static compatibility ratings from the start.

---

### Pitfall 3: Orphan Wine Processes and Incomplete Lifecycle Tracking

**What goes wrong:**
Wine creates complex process trees: the app launches `wine64`, which spawns `wineserver`, which manages `winedevice.exe`, `plugplay.exe`, `svchost.exe`, `services.exe`, and the actual game process. The current `ProcessRegistry` tracks only the initial `Process` object (the `wine64 start /unix` launcher), not the child tree. When `wine start` returns (it exits after launching the program), the actual game continues as a child of wineserver. The registry loses track. Lutris has the exact same bug (GitHub issue #4046: "Lutris leaves behind dead winedevice processes"). On macOS, these orphan processes consume memory, hold file locks on the Wine prefix, and can prevent future launches from the same bottle.

**Why it happens:**
Wine's process model does not map cleanly to POSIX process groups. `wine start /unix game.exe` returns immediately after queuing the launch with wineserver. The actual game process is a child of wineserver, not of the Process object the app created. Tracking by PID is fragile because PIDs can be reused. The current code in `Wine.runProgram()` uses `wine start` which completes before the game even starts. The `ProcessRegistry` documents this limitation explicitly in the App Nap comment: "The actual game process continues as a child of wineserver after the launcher exits."

**How to avoid:**
- Use `wineserver --wait` or monitor the wineserver process for the bottle's WINEPREFIX to detect when all processes in that prefix have exited.
- Track the wineserver PID per bottle (there is exactly one wineserver per WINEPREFIX) rather than individual game PIDs.
- On cleanup, use `wineserver -k` with the correct WINEPREFIX (the code already has `Wine.killBottle()` which does this) rather than sending SIGTERM/SIGKILL to individual PIDs.
- Implement periodic liveness checks: scan for processes with the bottle's WINEPREFIX in their environment to detect orphans that escaped registration.
- Never use `killall wineserver` -- this kills ALL wineservers and can corrupt other bottles' registries.

**Warning signs:**
- Users reporting "I can't launch Game X until I reboot" (stale wineserver holding prefix lock)
- Activity Monitor showing `winedevice.exe` processes with no corresponding Whisky bottle open
- `ProcessRegistry.getAllProcesses()` returning empty while Wine processes are clearly still running
- Disk space not freed after closing games (temp files locked by orphan processes)

**Phase to address:**
Process management phase (#50 miscellaneous fixes, then dedicated process lifecycle work). The current `ProcessRegistry` design needs to be augmented with wineserver-level tracking before expanding to auto-termination features.

---

### Pitfall 4: Configuration Setting Explosion Overwhelming Users

**What goes wrong:**
The settings UI grows to expose every Wine/DXVK/Metal/D3DMetal environment variable as a toggle or slider, creating an incomprehensible wall of options. The current `BottleSettings` already has 30+ configurable properties across 7 config sub-types. Adding graphics configuration UI for DXVK (async, HUD, shader optimization), D3DMetal (force D3D11, feature levels, validation, fast shader compile), Metal (HUD, trace, DXR, validation, GPU family), and MoltenVK settings could easily push this past 50+ options. Users cannot distinguish between "this toggle might fix my game" and "this toggle will break everything." Bottles (Linux) faced exactly this critique: powerful but intimidating for non-technical users.

**Why it happens:**
Each upstream issue suggests a specific environment variable fix. It is tempting to expose each one as a UI control. The incremental cost of adding one more toggle seems low, but the cognitive cost to users grows superlinearly. The existing code already shows this pattern: `BottlePerformanceConfig` has a `performancePreset` enum trying to bundle settings, but also exposes individual `forceD3D11`, `shaderCacheEnabled`, `disableShaderOptimizations` flags that contradict presets.

**How to avoid:**
- Use a **tiered UI**: "Simple" view shows presets (Balanced/Performance/Quality/Unity) and "Advanced" view shows individual toggles. Default to Simple.
- Group settings by **problem symptom** rather than by technical subsystem. Users know "my game has no sound" or "my game is slow," not "I need to set DXVK_ASYNC=1 and D3DM_FAST_SHADER_COMPILE=1."
- Validate setting combinations: if Force D3D11 is enabled, disable and grey out D3D12-specific options. If DXVK is off, hide DXVK HUD/async options.
- Provide **reset to defaults** per section and per bottle. Currently `BottleSettings` can be decoded from disk but there is no in-app "reset to defaults" for individual config sections.
- Include inline help text that explains consequences, not just what the setting does. "DXVK Async: Reduces stuttering but may cause brief visual glitches" is better than "Enable asynchronous shader compilation."

**Warning signs:**
- Users posting screenshots asking "what should I set all these to?"
- The settings view requiring scrolling to see all options
- Issues where the fix was "reset all settings to defaults"
- Users afraid to change settings because they don't know how to undo changes

**Phase to address:**
Graphics configuration UI phase (#43). The tiered design must be the first decision, not an afterthought. Audio settings phase (#44) should follow the same pattern.

---

### Pitfall 5: Environment Variable Override Conflicts in the Configuration Cascade

**What goes wrong:**
Multiple layers of the configuration system set the same environment variable to conflicting values, and the last writer wins based on execution order rather than explicit priority. This is already happening in the codebase: `MacOSCompatibility.swift` sets `WINEFSYNC=0`, then `BottleSettings.environmentVariables()` may set `WINEFSYNC` again based on Enhanced Sync selection, then launcher presets may set it again. The final value depends on which function runs last and whether it uses `updateValue` (always overwrites) vs `merge` with conflict resolution. The `applyLauncherCompatibility` method uses `.merge(launcherEnv) { _, new in new }` (launcher wins), but `gpuSpoofing` uses `.merge(gpuEnv) { current, new in current.isEmpty ? new : current }` (existing wins) -- inconsistent merge strategies in the same method.

**Why it happens:**
The configuration cascade grew organically as new features were added. Each feature (macOS compat, launcher presets, performance presets, Sequoia mode, user overrides) was added independently without a central authority documenting which layer has priority. The `environmentVariables()` method is already flagged with `swiftlint:disable cyclomatic_complexity function_body_length` because the override logic is too complex.

**How to avoid:**
- Implement an explicit **EnvironmentBuilder** with documented, tested precedence layers:
  1. Wine base defaults (`WINEPREFIX`, `WINEDEBUG`)
  2. macOS compatibility fixes (version-gated)
  3. Bottle-level settings (user-configured)
  4. Launcher presets (auto-detected or manual)
  5. Program-specific overrides (per-exe settings)
  6. User explicit overrides (highest priority)
- Each layer should log what it sets and what it overrides.
- Add **integration tests** that verify specific precedence scenarios (e.g., "user sets Enhanced Sync to None but macOS 15.4 forces ESYNC" should result in ESYNC enabled with a user-visible note).
- Provide a **"show effective environment"** debug feature that displays the final merged environment before launch, showing which layer contributed each variable.

**Warning signs:**
- The `environmentVariables()` method growing beyond its current complexity
- Bug reports where changing a setting has no effect (because a higher-priority layer overwrites it)
- Inconsistent merge strategies (`{ _, new in new }` vs `{ current, new in ... }`) appearing in the same codepath

**Phase to address:**
Must be addressed BEFORE the graphics configuration UI phase. The precedence model is foundational -- adding more settings on a broken foundation multiplies the problem.

---

### Pitfall 6: Audio "Fixes" That Require Wine-Layer Changes

**What goes wrong:**
The audio troubleshooting phase (#44) tries to solve no-sound and audio-glitch issues through app-layer configuration, but most Wine audio problems on macOS are in Wine's CoreAudio driver (`winecoreaudio.drv`), not in configuration. Setting `WINEDLLOVERRIDES` to use native `dsound.dll` or `xaudio2_7.dll` may fix one game but break system audio for others. Wine's audio driver had known regressions in Wine 6.22+ (GitHub issue Gcenx/macOS_Wine_builds#30) that no amount of environment variable tweaking can fix. The risk is shipping audio "settings" that provide a false sense of control while the actual problem requires Wine patches.

**Why it happens:**
Audio issues are the most-reported category in Wine on macOS after graphics. Users expect a Wine GUI manager to fix audio. The temptation is to add FAudio/dsound/GStreamer toggle settings that look helpful but are actually cargo-cult configurations. Unlike graphics (where DXVK/D3DMetal selection genuinely affects rendering), audio on macOS Wine goes through a single path: game -> Windows audio API -> Wine translation -> CoreAudio. There are fewer meaningful knobs to turn.

**How to avoid:**
- Scope the audio phase as **primarily guidance**, not configuration toggles. The honest answer for many audio issues is "this requires a Wine update."
- The actionable app-layer audio fixes are limited to: (1) Wine audio driver selection via registry (`HKEY_CURRENT_USER\Software\Wine\Drivers` "Audio"="coreaudio"), (2) GStreamer debug level (`GST_DEBUG`), (3) DLL overrides for specific audio libraries. Expose only these.
- Include a **diagnostic that checks** whether audio output devices are available, whether CoreAudio is responding, and whether the Wine audio driver registry key is correctly set.
- Document the boundary clearly: "Whisky can configure which audio libraries Wine uses. If audio still doesn't work, the issue is in Wine's audio driver and requires a Wine update."

**Warning signs:**
- Adding more than 3-4 audio-related settings
- Users reporting "I tried all audio settings and none fixed it"
- Audio settings that only work for one specific game

**Phase to address:**
Audio troubleshooting phase (#44). Must be scoped as guidance-first from the design stage.

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoding env var values in MacOSCompatibility.swift | Quick fix for macOS version regressions | Creates version-specific code branches that accumulate; each macOS update adds more conditional blocks | During initial triage of a new macOS regression, but must be refactored into configurable presets within 1 release |
| Using `@unchecked Sendable` on ProcessRegistry/TempFileTracker | Avoids Swift 6 concurrency errors quickly | Masks real thread safety bugs; NSLock-based synchronization is error-prone | Never for new code; existing instances should be migrated to actors |
| Adding settings to BottleSettings without UI validation | Fast to implement | Invalid combinations accumulate (DXVK + incompatible DLL overrides, D3D11 forced + D3D12 features enabled) | Only during rapid prototyping; must add validation before release |
| Global singleton for ProcessRegistry | Simple access pattern | Untestable without `reset()` hack; prevents multiple-bottle concurrent testing | Acceptable given macOS app lifecycle, but use dependency injection for testability |
| Storing game compatibility data as static in-app content | No backend needed | Stale within weeks; app update required to fix wrong guidance | Only if entries include version tuples and staleness warnings |

## Integration Gotchas

Common mistakes when connecting to external services and subsystems.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Wine/wineserver | Killing `wine64` process and assuming game stops | Track wineserver PID per WINEPREFIX; use `wineserver -k` for cleanup; `wineserver --wait` for completion detection |
| DXVK DLL installation | Installing only x64 DLLs and missing x32 | Always install both `x64/` and `x32/` to `system32/` and `syswow64/` respectively (the current code already does this correctly in `Wine.enableDXVK()`) |
| macOS CoreAudio | Setting audio env vars without checking registry | Always verify `HKEY_CURRENT_USER\Software\Wine\Drivers` Audio key is set to "coreaudio" first; env vars alone are insufficient |
| Wine registry | Reading registry values while wineserver is running | Registry files may be cached in memory by wineserver; stop wineserver or use `wine reg query` for live values |
| MoltenVK / Vulkan ICD | Hardcoding `VK_ICD_FILENAMES` path | Path varies by installation method (Homebrew, bundled, system); detect at runtime or use system default |
| Winetricks | Running winetricks without prefix validation | Wine prefix must have valid user directories; use `Wine.repairPrefix()` first (already implemented) |
| Apple Game Controller framework | Assuming SDL handles all controllers | Some controllers work with Apple's GCController framework but not SDL; may need both paths |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Scanning Wine prefix for programs on every bottle open | UI lag when opening bottle with many installed programs | Cache program list; invalidate on drive_c modification date change | >50 programs in a bottle |
| Running `enforceLogRetention()` synchronously on every launch | Launch delay increases with log count | Move to async timer-based retention; run at most once per app session | >1000 log files accumulated |
| Loading all bottle settings into memory at startup | Startup time grows with bottle count | Lazy-load settings on first access; only load metadata (name, icon) for list view | >10 bottles |
| Full PE parse for icon extraction on every list refresh | Visible jank scrolling program list | Use IconCache (already implemented); ensure cache invalidation doesn't trigger full re-parse | >20 programs with icons |
| ProcessRegistry polling in `waitForExit` with 100ms sleep | CPU usage during cleanup, blocks UI | Use `Process.waitUntilExit()` or kqueue-based notification instead of polling | Many concurrent processes |

## Security Mistakes

Domain-specific security issues beyond general app security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Logging full environment variable values | Secrets (API keys, tokens) in Wine logs accessible to any user-space process | Log keys only (already implemented in CHANGELOG); verify no regression paths bypass this |
| Shell injection via `generateRunCommand()` | Malicious program names or paths could execute arbitrary commands when pasted into terminal | Validate all user inputs through `isValidEnvKey()` and `.esc` (already implemented); never trust `preEscaped: true` from user data |
| CEF sandbox disabled globally | Embedded browser in Steam/Epic runs with full process privileges | Document the tradeoff (already done in MacOSCompatibility.swift); no alternative without breaking launchers; warn users to only use trusted launchers |
| Wine prefix accessible to all user processes | Any macOS app can read/modify drive_c contents including saved games and credentials | Apply appropriate POSIX permissions on prefix creation; warn users that Wine prefixes are not sandboxed |
| GPU spoofing PCI IDs visible to anti-cheat | Online games may flag GPU spoofing as tampering | Disable GPU spoofing by default for bottles not using launcher compatibility mode; warn users about online game risks |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing raw environment variable names in settings UI | Users don't know what `WINEFSYNC`, `D3DM_FORCE_D3D11`, or `DXVK_ASYNC` mean | Use human-readable labels with inline descriptions: "Enhanced Sync (improves performance)" not "WINEESYNC" |
| No feedback when settings change takes effect | Users toggle settings and don't know if they need to relaunch | Show toast: "Setting changed. Restart the program for it to take effect." |
| Compatibility database with only "works/broken" ratings | Users with "broken" games have no next step | Provide troubleshooting steps: "If broken, try: (1) DXVK on, (2) Force D3D11, (3) Change Windows version" |
| Exposing Wine version selection per bottle | Users downgrade Wine version expecting it to fix compatibility, but corrupt their prefix | Pin Wine version globally; explain that different Wine versions are not interchangeable per-bottle without prefix recreation |
| Error messages showing Wine stderr output directly | Users see `fixme:ntdll:NtQuerySystemInformation` noise and panic | Filter known-harmless fixme messages; only surface actionable errors |
| No distinction between "needs Wine fix" and "needs configuration fix" | Users blame the app for problems the app cannot solve | Label issues clearly: "This requires a Wine update" vs "Try these settings" |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Launcher compatibility**: Often missing locale override for non-English systems -- verify LC_ALL is set correctly for all launcher types, not just Steam
- [ ] **DXVK installation**: Often missing Wine DLL override registration -- verify `WINEDLLOVERRIDES` is set for all relevant DLLs (dxgi, d3d9, d3d10core, d3d11), not just the file copy
- [ ] **Process cleanup**: Often missing wineserver tracking -- verify that `ProcessRegistry.cleanupAll()` also calls `wineserver -k` per bottle, not just SIGTERM to tracked PIDs
- [ ] **Settings persistence**: Often missing migration for new settings -- verify that `BottleSettings.decode()` provides safe defaults for every newly added field via `decodeIfPresent`
- [ ] **Audio configuration**: Often missing registry verification -- verify Wine audio driver registry key exists before suggesting env var changes
- [ ] **Game compatibility entries**: Often missing version tuple -- verify every entry specifies macOS version, Wine version, and date tested
- [ ] **GPU spoofing**: Often missing VK_ICD_FILENAMES validation -- verify the MoltenVK ICD file actually exists at the hardcoded path before setting
- [ ] **Performance presets**: Often missing preset-to-individual-setting sync -- verify that switching from "Performance" to "Balanced" actually resets all individual settings that Performance changed
- [ ] **Controller settings**: Often missing SDL version compatibility -- verify SDL environment variables work with both SDL2 and SDL3 (games ship different versions)
- [ ] **Log retention**: Often missing first-run check -- verify retention runs even when the log directory was just created (currently it does, but the `guard total > maxTotalBytes` short-circuits)

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Environment variable conflicts breaking a game | LOW | Reset bottle settings to defaults; re-enable only necessary overrides; use "show effective environment" to diagnose |
| Stale compatibility data causing user trust loss | MEDIUM | Add prominent "last verified" dates; implement one-click "report this didn't work" feedback; prioritize re-testing top games after each Wine/macOS update |
| Orphan Wine processes filling memory | LOW | Implement "Kill All Wine Processes" nuclear option (find all wineserver/wine64 processes for user); already partially implemented via killBottle() |
| Settings explosion confusing users | MEDIUM | Implement "Simple/Advanced" toggle retroactively; move advanced settings to a disclosure group; add "Reset to Defaults" per section |
| Audio settings that do nothing | LOW | Convert non-functional audio settings into guidance text ("This issue requires a Wine update"); remove misleading toggles |
| Configuration cascade bugs | HIGH | Requires refactoring into EnvironmentBuilder with explicit layers and tests; cannot be patched incrementally because the problem is architectural |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Wine-layer bugs treated as app-fixable | Before Graphics Config UI | Integration tests verify each env var override has documented side effects; no env var set without a code comment explaining what it breaks |
| Stale compatibility database | Game Compatibility phase (#48) design | Every database entry has version tuple; staleness warning displays for entries older than 60 days |
| Orphan Wine processes | Process Management phase (#50) | After `cleanupAll()`, `pgrep -f WINEPREFIX=<bottle-path>` returns no results; tested via integration test |
| Configuration explosion | Graphics Config UI phase (#43) design | Settings view fits in one screen without scrolling in Simple mode; user testing with non-technical testers |
| Environment variable conflicts | Before Graphics Config UI (foundational) | EnvironmentBuilder with explicit layer precedence; test coverage for all 6 precedence layers with conflict scenarios |
| Audio false-fix settings | Audio Troubleshooting phase (#44) design | Maximum 4 audio-related settings; each setting has documented "what this does NOT fix" text |

## Sources

- [Lutris leaves behind dead winedevice processes (GitHub #4046)](https://github.com/lutris/lutris/issues/4046)
- [Lutris does not manage to terminate wineserver after quitting (GitHub #176)](https://github.com/lutris/lutris/issues/176)
- [Lutris wine.create_prefix executes with different environment variables (GitHub #4679)](https://github.com/lutris/lutris/issues/4679)
- [ProtonDB reliability problems analysis](https://ps2bios.gitlab.io/home/we-need-to-stop-telling-folks-to-simply-rely-on-protondb-its-not-that-simple/)
- [ProtonDB sucks analysis (NotebookCheck)](https://www.notebookcheck.net/The-Steam-Deck-and-Linux-gaming-have-a-problem-ProtonDB-sucks-let-me-explain.829702.0.html)
- [ProtonDB needs changes (Valve/Proton GitHub #2638)](https://github.com/ValveSoftware/Proton/issues/2638)
- [DXVK common issues wiki](https://github.com/doitsujin/dxvk/wiki/Common-issues)
- [Running wineserver -k creates defunct process (WineHQ Forums)](https://forum.winehq.org/viewtopic.php?t=29046)
- [Wine process killing (WineHQ Forums)](https://forum.winehq.org/viewtopic.php?t=32738)
- [Wine audio no output (Gcenx/macOS_Wine_builds #30)](https://github.com/Gcenx/macOS_Wine_builds/issues/30)
- [CrossOver configuration guide (CodeWeavers)](https://support.codeweavers.com/advanced-crossover-mac-configuration)
- [WineHQ Application Database](https://appdb.winehq.org./)
- [Whisky upstream game list discussion (#348)](https://github.com/orgs/Whisky-App/discussions/348)
- [Wine environment variables reference](https://simpler-website.pages.dev/html/2021/1/wine-environment-variables/)
- Codebase analysis: `MacOSCompatibility.swift`, `BottleSettings.swift`, `ProcessRegistry.swift`, `LauncherPresets.swift`, `WineEnvironment.swift`, `Wine.swift`, `GPUDetection.swift`

---
*Pitfalls research for: Wine GUI manager (macOS) issue backlog resolution*
*Researched: 2026-02-08*
