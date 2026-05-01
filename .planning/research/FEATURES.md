# Feature Research

**Domain:** Wine GUI bottle manager for macOS (Apple Silicon)
**Researched:** 2026-02-08
**Confidence:** MEDIUM-HIGH (competitive analysis well-sourced; macOS-specific audio constraints partially verified)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Per-bottle DXVK toggle + async + HUD** | Every competitor has this (CrossOver, Bottles, Lutris). Whisky already has it. | LOW | Already implemented in `BottleDXVKConfig`. Maintain and polish. |
| **Per-bottle graphics backend selection (D3DMetal vs DXVK vs wined3d)** | CrossOver 25 "Auto" mode selects backend per-game from database; users expect explicit override. Upstream issue #600 shows DXVK unusable when D3DMetal active via Steam. | MEDIUM | Whisky has no `WINED3DMETAL=0` toggle. CrossOver's `cxbottle.conf` handles this. Need env var `WINED3DMETAL` control per-bottle. |
| **Per-bottle Metal/DXR/Sequoia compat settings** | Already present in all macOS Wine wrappers. Whisky has this. | LOW | Already implemented in `BottleMetalConfig`. |
| **Performance presets (balanced/performance/quality)** | Bottles has Gaming/Software/Custom environments. CrossOver auto-selects via database. | LOW | Already implemented via `BottlePerformanceConfig` with balanced/performance/quality/unity presets. |
| **Process list with kill capability** | CrossOver has Task Manager per-bottle. Bottles has "Kill all processes" button. Lutris has stop/force-stop (buggy). Whisky has `RunningProcessesView` using `tasklist.exe`. | LOW | Already implemented. Need: refresh interval, graceful vs force kill UX, integration with `ProcessRegistry`. |
| **Wine version display + Windows version selector** | Universal across all competitors. | LOW | Already implemented in `WineConfigSection`. |
| **Winetricks/dependency installation** | CrossOver does this automatically via CrossTie profiles. Bottles has dependency manager. Lutris has install scripts. Whisky has `WinetricksView`. | LOW | Already exists. VC++ Redist one-click install already in `PerformanceConfigSection`. |
| **Locale/language per-program** | CrossOver, Bottles, Lutris all support this. | LOW | Already implemented in `ProgramSettings.locale`. |
| **Per-program environment variables and arguments** | Bottles supports per-program env vars. Lutris Game Options tab. CrossOver per-app profiles. | LOW | Already implemented in `ProgramSettings.environment` and `ProgramSettings.arguments`. |
| **Bottle export/import** | CrossOver, Bottles (with config export), Lutris (prefix backup). | LOW | Already exists in upstream Whisky. Changelog shows archive progress indicator added. |
| **Stability diagnostics / log export** | CrossOver has `cxdiag` and System Information. Bottles has logging. | LOW | Already implemented via `StabilityDiagnostics` and `WhiskyWineSetupDiagnostics`. |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Per-program graphics backend override** | CrossOver's C4 database does this server-side (per-app backend selection); no open-source competitor lets users override graphics backend per-program from a GUI. Bottles and Lutris only do per-bottle. | MEDIUM | Extend `ProgramSettings` with optional DXVK/D3DMetal/wined3d override that supersedes bottle default. This directly addresses upstream #600, #844 (DXVK vs D3DMetal per-game). |
| **Audio device diagnostics + driver selection UI** | No competitor provides in-app audio troubleshooting on macOS. CrossOver exposes winecfg Audio tab. Bottles relies on system PulseAudio. Upstream issues #1127, #445, #637, #761, #312, #1352 (7+ audio bugs) show this is a major pain point with zero in-app remediation today. | MEDIUM | Wine on macOS uses CoreAudio driver. Expose: (1) audio device detection status, (2) sample rate mismatch warning (common cause of static), (3) "restart CoreAudio" action, (4) Bluetooth device reconnection guidance. Do NOT build a full audio mixer -- just diagnostics and known-fix buttons. |
| **Game compatibility quick-reference with known fixes** | CrossOver has proprietary C4 database (paid). ProtonDB is Linux/Proton-only. AppleGamingWiki is a wiki, not in-app. No macOS Wine manager provides in-app compatibility guidance. | HIGH | Ship a bundled, version-controlled JSON of known game issues and recommended settings (DXVK on/off, D3D11 forced, launcher type, preset). NOT a full community database -- a curated set of fixes the fork has validated. Link out to AppleGamingWiki for full reports. |
| **Launcher auto-detection with one-click optimization** | Already partially built (frankea/Whisky#41). CrossOver does this via CrossTie profiles. Bottles has Eagle for dependency detection. Lutris has install scripts. None auto-detect and auto-apply launcher-specific env vars like Whisky's `LauncherPresets`. | LOW | Already implemented. Differentiator because it's automatic and macOS-specific. Polish: ensure detection covers GOG Galaxy (CrossOver 25 added GOG support). |
| **Bottle snapshots / configuration rollback** | Bottles has integrated snapshots with one-click restore since 2022. CrossOver and Lutris lack this. Extremely valuable for "I installed something and it broke my bottle." | HIGH | Requires snapshotting bottle directory or at minimum the plist + registry. Bottles' implementation warns about disk usage. Consider lightweight "config-only snapshot" first (plist + registry files, not full prefix). |
| **Guided troubleshooting for common issues** | CrossOver has knowledge base articles linked from app. No competitor has in-app step-by-step troubleshooters. Upstream Whisky had zero troubleshooting guidance. | MEDIUM | Build a troubleshooting flow: "Game won't launch" -> check prefix -> check DXVK -> check Windows version -> suggest fixes. Similar to the existing `StabilityDiagnostics` but interactive and user-facing rather than developer-facing. |
| **Process lifecycle integration with ProcessRegistry** | No competitor integrates process tracking at the framework level. Lutris has persistent bugs with orphaned Wine processes (issues #5841, #2539, #4046). Bottles has a known bug where navigating away kills processes (#3746). | LOW | `ProcessRegistry` already exists with SIGTERM/SIGKILL cascade. Differentiator: connect it to `RunningProcessesView` for live updates, show process duration, auto-cleanup on bottle close. |
| **DXVK configuration file management** | CrossOver allows DXVK HUD config via `cxbottle.conf`. Upstream issue #219 requested DXVK config in Whisky. Bottles exposes DXVK version selection. | MEDIUM | Allow editing `dxvk.conf` per-bottle for advanced users: frame rate limit, shader cache path, device filter. Expose common options (frame rate cap, async) in GUI; raw config for power users. |
| **macOS-native troubleshooting integration** | No competitor integrates with macOS system diagnostics. Unique to macOS platform. | MEDIUM | Surface Metal GPU errors from system log, detect Rosetta issues, check for macOS version-specific bugs (Sequoia already handled), detect conflicting virtual audio drivers (BlackHole, Loopback -- known to break Wine CoreAudio). |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Full community compatibility database (ProtonDB-style)** | Users want to know if their game works. ProtonDB is popular on Linux. | Requires server infrastructure, moderation, spam prevention, and ongoing maintenance. ProtonDB works because Valve/Steam provides telemetry. An independent macOS database would have tiny contributor base and stale data. | Ship curated JSON of validated fixes bundled with app. Link to AppleGamingWiki for community reports. |
| **In-app audio mixer / equalizer** | Upstream issues request audio control. | Wine's CoreAudio driver is a pass-through to macOS. Audio mixing should happen at the OS level (System Settings > Sound) or in the game itself. Building a mixer duplicates macOS functionality and adds fragile AudioUnit complexity. | Provide audio diagnostics (device detection, sample rate, Bluetooth status) and link to macOS Sound settings. |
| **Auto-download and install Wine/GPTK versions** | Users want latest Wine with one click. Bottles manages multiple runners. Lutris has runner management. | Wine on macOS requires specific build configurations (Gcenx builds, GPTK integration). Multiple Wine versions per-bottle increases complexity and disk usage significantly. WhiskyWine installer already handles this. | Keep single managed Wine version via `WhiskyWineInstaller`. Provide clear version display and update notifications. |
| **Full winetricks GUI with dependency browser** | Power users want to install arbitrary Windows components. | Winetricks is fragile, slow, and can corrupt prefixes. Exposing the full list encourages users to install incompatible combinations. Bottles' Eagle shows that auto-detection is better than manual browsing. | Keep targeted one-click installs (VC++ Redist, .NET, DirectX) in Performance section. Use winetricks under the hood but don't expose full catalog. |
| **Windows registry editor in-app** | Users want to tweak Wine registry. | Registry editing is error-prone and can corrupt bottles. Exposing it in-app normalizes dangerous operations. CrossOver deliberately makes regedit accessible but separate. | Keep the existing "Open Regedit" button in ConfigView bottom bar. Don't embed a registry editor in the main UI. |
| **Automatic GPU driver updates / MoltenVK management** | Users on AppleGamingWiki note that updating DXVK/MoltenVK improves performance. | MoltenVK and DXVK are bundled with WhiskyWine. Independent updates can cause version mismatches and break the translation layer stack. | Update MoltenVK/DXVK as part of WhiskyWine releases. Document which versions are bundled. |
| **Cloud sync for bottle settings** | Users want settings to sync across Macs. | Bottles are large (GBs), settings depend on local hardware (GPU family, macOS version). Syncing only config without the prefix is misleading. | Provide export/import for settings plist only (not full bottle). |

## Feature Dependencies

```
[Per-program graphics override]
    +--requires--> [Per-bottle graphics backend selection (D3DMetal/DXVK/wined3d toggle)]
                       +--requires--> [WINED3DMETAL env var support in BottleSettings.environmentVariables()]

[Game compatibility quick-reference]
    +--enhances--> [Per-program graphics override] (auto-apply known-good settings)
    +--enhances--> [Launcher auto-detection] (suggest launcher type for known games)
    +--enhances--> [Guided troubleshooting] (link troubleshooter to known issues)

[Audio diagnostics UI]
    +--requires--> [CoreAudio device detection utility]
    +--enhances--> [Guided troubleshooting] (audio branch of troubleshooter)

[Guided troubleshooting]
    +--requires--> [Stability diagnostics] (already exists)
    +--enhances--> [Game compatibility quick-reference] (troubleshooter suggests checking compat DB)

[DXVK config file management]
    +--requires--> [Per-bottle DXVK toggle] (already exists)
    +--enhances--> [Per-program graphics override] (program-level dxvk.conf)

[Process lifecycle integration]
    +--requires--> [ProcessRegistry] (already exists)
    +--enhances--> [RunningProcessesView] (live updates instead of manual refresh)

[Bottle snapshots]
    +--independent-- (no hard dependencies, but enhances safety of all config changes)
    +--enhances--> [Per-bottle graphics backend selection] (snapshot before changing backend)
```

### Dependency Notes

- **Per-program graphics override requires per-bottle backend selection:** You must be able to control the graphics backend at the bottle level before you can override it at the program level. The bottle-level `WINED3DMETAL` toggle is the foundation.
- **Game compatibility quick-reference enhances multiple features:** The compatibility database acts as a "suggested settings" engine that feeds into graphics overrides, launcher detection, and troubleshooting. Build it as a data layer, not a UI-first feature.
- **Audio diagnostics requires CoreAudio detection utility:** Before building UI, need a Swift utility that queries CoreAudio device status, sample rates, and Bluetooth connection state via `AVAudioSession` / `CoreAudio` framework.
- **Guided troubleshooting is an integration layer:** It connects stability diagnostics (exists), audio diagnostics (new), and compatibility data (new) into a user-facing flow. Build the components first, then the flow.

## MVP Definition

### Launch With (v1) -- Next Milestone Priorities

Minimum set to address the highest-impact upstream issues.

- [x] **Per-bottle DXVK toggle + async + HUD** -- Already implemented
- [x] **Performance presets** -- Already implemented
- [x] **Launcher auto-detection** -- Already implemented
- [x] **Process list with kill** -- Already implemented
- [x] **Stability diagnostics** -- Already implemented
- [ ] **Per-bottle graphics backend toggle (D3DMetal on/off)** -- Addresses #600, table stakes gap
- [ ] **Audio diagnostics panel** -- Addresses 7+ upstream audio bugs with zero current remediation
- [ ] **ProcessRegistry integration with RunningProcessesView** -- Connect existing backend to existing frontend

### Add After Validation (v1.x)

Features to add once core is working and tested.

- [ ] **Per-program graphics backend override** -- When users request finer control beyond bottle-level
- [ ] **Game compatibility quick-reference (bundled JSON)** -- When we have validated fixes for 20+ games
- [ ] **Guided troubleshooting flow** -- When audio diagnostics and graphics toggle are stable
- [ ] **DXVK config file management** -- When advanced users request frame rate caps and device filters

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Bottle snapshots / config rollback** -- High complexity, requires careful disk usage management
- [ ] **macOS-native system diagnostics integration** -- Depends on which macOS versions surface which issues
- [ ] **GOG Galaxy launcher preset** -- When GOG support demand materializes

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Per-bottle D3DMetal/DXVK backend toggle | HIGH | LOW | P1 |
| Audio diagnostics panel | HIGH | MEDIUM | P1 |
| ProcessRegistry + RunningProcessesView integration | MEDIUM | LOW | P1 |
| Per-program graphics backend override | HIGH | MEDIUM | P2 |
| Game compatibility quick-reference | HIGH | HIGH | P2 |
| Guided troubleshooting flow | MEDIUM | MEDIUM | P2 |
| DXVK config file management | MEDIUM | MEDIUM | P2 |
| Bottle snapshots | MEDIUM | HIGH | P3 |
| macOS system diagnostics integration | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for next milestone (directly addresses top upstream issues)
- P2: Should have, add when P1 features are stable
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | CrossOver | Bottles | Lutris | Whisky (current) | Our Approach |
|---------|-----------|---------|--------|-------------------|--------------|
| **Graphics backend selection** | Auto/DXVK/DXMT/D3DMetal/wined3d per-bottle; auto uses C4 database per-game | DXVK/VKD3D toggles per-bottle; no per-game | DXVK toggle per-game via runner options | DXVK toggle only; no D3DMetal control | Add WINED3DMETAL toggle per-bottle (P1), then per-program override (P2) |
| **DXVK HUD/config** | Via cxbottle.conf manual edit | Toggle in Graphics preferences | Via env vars in runner options | Toggle + picker (full/partial/fps/off) | Keep existing UI; add dxvk.conf editor for power users (P2) |
| **Audio configuration** | winecfg Audio tab; per-bottle driver selection via cxbottle.conf | Relies on system PulseAudio; no in-app config | Per-game audio device selection (buggy, resets) | None | Audio diagnostics panel with device detection + known-fix actions (P1) |
| **Game compatibility DB** | Proprietary C4 database with 15K+ apps; auto-configures per-game | Eagle binary analysis (new, v61); community installers | Community install scripts (YAML/JSON); lutris.net database | None | Curated bundled JSON of macOS-validated fixes (P2); link to AppleGamingWiki |
| **Process management** | Task Manager per-bottle; "Quit All" | "Kill all processes" button; known navigation bug | Stop button; persistent orphaned process bugs | tasklist.exe + manual refresh; ProcessRegistry backend | Integrate ProcessRegistry with live-updating RunningProcessesView (P1) |
| **Troubleshooting** | cxdiag tool; System Information; knowledge base links | Eagle analysis; logging | Log viewer; no guided troubleshooting | StabilityDiagnostics report; WhiskyWine setup diagnostics | Add guided troubleshooting flow connecting existing diagnostics (P2) |
| **Snapshots/rollback** | None | Integrated snapshots since 2022; auto-snapshot on dependency install | None | None | Config-only snapshots for safety (P3) |
| **Launcher compatibility** | CrossTie profiles; per-app install recipes | Eagle auto-detection; environment presets | Community install scripts per-launcher | Auto-detection + 7 launcher presets + env var optimization | Already differentiated; add GOG Galaxy preset when needed |
| **Per-program overrides** | Per-app profiles in C4 database | Per-program env vars (buggy); per-program arguments | Per-game runner options, env vars, arguments | Locale, env vars, arguments per-program | Add graphics backend override per-program (P2) |

## Sources

### CrossOver
- [Advanced Settings in CrossOver Mac 25 - CodeWeavers](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac) -- MEDIUM confidence (official docs)
- [How to Enable DXVK - CodeWeavers](https://support.codeweavers.com/2-enabling-dxvk) -- MEDIUM confidence
- [CrossOver - AppleGamingWiki](https://www.applegamingwiki.com/wiki/CrossOver) -- MEDIUM confidence (community wiki, well-maintained)
- [CrossOver 25 announcement - CodeWeavers Blog](https://www.codeweavers.com/blog/mjohnson/2025/3/11/experience-next-level-gaming-on-mac-with-crossover-25) -- HIGH confidence (official)
- [Working with CrossTie Installer Profiles - CodeWeavers](https://support.codeweavers.com/crosstie-data-startpage) -- MEDIUM confidence
- [Troubleshooting Sound Issues - CodeWeavers](https://support.codeweavers.com/troubleshooting-sound-issues) -- MEDIUM confidence

### Bottles
- [DXVK | Bottles Docs](https://docs.usebottles.com/components/dxvk) -- MEDIUM confidence (official docs)
- [Bottle preferences | Bottles Docs](https://docs.usebottles.com/bottles/preferences) -- MEDIUM confidence
- [Bottles 61 Eagle Feature - Linuxiac](https://linuxiac.com/bottles-61-turns-into-an-analysis-tool-with-the-new-eagle-feature/) -- MEDIUM confidence
- [Bottles Versioning Feature - GamingOnLinux](https://www.gamingonlinux.com/2022/07/wine-manager-app-bottles-makes-rolling-back-configs-real-easy/) -- MEDIUM confidence
- [Bottles Environment Variables Bug #3128](https://github.com/bottlesdevs/Bottles/issues/3128) -- HIGH confidence (primary source)
- [Bottles Process Kill Bug #3746](https://github.com/bottlesdevs/Bottles/issues/3746) -- HIGH confidence

### Lutris
- [Lutris Installer Documentation](https://github.com/lutris/lutris/blob/master/docs/installers.rst) -- HIGH confidence (primary source)
- [Lutris FAQ](https://lutris.net/faq) -- MEDIUM confidence (official)
- [Lutris Process Issues #5841, #2539, #4046](https://github.com/lutris/lutris/issues/5841) -- HIGH confidence (primary source)
- [Lutris Kill All Processes Feature Request #4266](https://github.com/lutris/lutris/issues/4266) -- HIGH confidence

### Whisky Upstream Issues (HIGH confidence -- primary source)
- [#600: DXVK unusable with D3DMetal via Steam](https://github.com/Whisky-App/Whisky/issues/600)
- [#844: Controllers broken with D3DMetal](https://github.com/Whisky-App/Whisky/issues/844)
- [#219: DXVK Config feature request](https://github.com/IsaacMarovitz/Whisky/issues/219)
- [#1127: Audio mutes on device switch](https://github.com/Whisky-App/Whisky/issues/1127)
- [#445: Distorted sound in Source games](https://github.com/Whisky-App/Whisky/issues/445)
- [#637: Staticky sound with Steam games](https://github.com/Whisky-App/Whisky/issues/637)
- [#761: Sound problems with older games](https://github.com/Whisky-App/Whisky/issues/761)
- [#312: Audio loss after Bluetooth disconnect](https://github.com/Whisky-App/Whisky/issues/312)
- [#1352: Sound bug in Touhou 6](https://github.com/Whisky-App/Whisky/issues/1352)
- [#233: NPC sounds missing (channel config)](https://github.com/IsaacMarovitz/Whisky/issues/233)

### ProtonDB / General
- [ProtonDB](https://www.protondb.com/) -- HIGH confidence (primary source)
- [AppleGamingWiki - Game Porting Toolkit](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit) -- MEDIUM confidence
- [Whisky Common Issues Documentation](https://docs.getwhisky.app/common-issues.html) -- MEDIUM confidence

---
*Feature research for: Wine GUI bottle manager (macOS Apple Silicon)*
*Researched: 2026-02-08*
