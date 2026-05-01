# Project Research Summary

**Project:** Whisky (Wine bottle management macOS app)
**Domain:** Wine compatibility layer GUI for macOS with focus on game compatibility, troubleshooting automation, and configuration management
**Researched:** 2026-02-08
**Confidence:** MEDIUM-HIGH

## Executive Summary

Whisky is a macOS Wine bottle manager addressing 435+ upstream issues through enhanced configuration controls, automated troubleshooting, and game-specific optimization. The research reveals that most existing features are correctly implemented (DXVK toggling, launcher detection, performance presets, process tracking), but critical gaps remain in graphics backend control (no D3DMetal toggle), audio troubleshooting (7+ open issues with zero in-app remediation), and systematic game compatibility guidance (no curated database).

The recommended approach builds on the existing architecture rather than replacing it. The configuration cascade pattern (Wine defaults → macOS fixes → bottle settings → program overrides) is sound but needs explicit precedence documentation and an additional "game profile" layer for per-game recommendations. The existing `ProcessRegistry` tracks individual Wine processes but must be enhanced with wineserver-level monitoring to prevent orphan process accumulation. New features should leverage zero-dependency Apple frameworks (MetricKit for crash diagnostics, OSLogStore for log retrieval, native SwiftUI patterns) rather than adding third-party dependencies.

The primary risk is scope creep through settings proliferation. Each upstream issue suggests environment variable fixes, but exposing every Wine/DXVK/Metal variable as a toggle creates overwhelming UIs. Research from competitor analysis (Bottles, CrossOver, Lutris) shows the "powerful but incomprehensible" trap. The mitigation strategy is tiered UIs (Simple/Advanced modes), symptom-driven troubleshooting guides instead of raw settings, and curated local game compatibility data instead of attempting a ProtonDB-scale community database.

## Key Findings

### Recommended Stack

The existing stack (Swift 6, SwiftUI, WhiskyKit package structure, Sparkle for updates) is appropriate and should not change. Recommended additions focus on leveraging built-in macOS capabilities rather than external dependencies.

**Core technologies to add:**
- **WINEDEBUG parsing** (Wine 11.0 built-in): Parse `err:`, `warn:`, `fixme:` output and `c0000005` crash patterns from Wine logs to auto-classify failures
- **MetricKit** (macOS 12+): System-level crash diagnostics via `MXCrashDiagnostic` instead of third-party crash reporters (Sentry, Firebase)
- **OSLogStore** (macOS 15+): Programmatic log retrieval for diagnostic reports using `.currentProcessIdentifier` scope
- **Local JSON compatibility database** (custom): Bundled game profiles mapping executables to known-good configurations, versioned and updated with app releases
- **Logger categories** (macOS 15+): Expand existing `os.log` usage with per-module categories (Wine, Launcher, DXVK, Bottle, GPU)

**What NOT to use:**
- ProtonDB API (Linux/Proton-specific, not transferable to macOS+Wine+D3DMetal)
- Sentry/PLCrashReporter (privacy concerns, unnecessary dependencies when MetricKit covers it)
- sindresorhus/Settings package (designed for app-level prefs, not per-bottle config)

### Expected Features

**Must have (table stakes) — mostly implemented:**
- Per-bottle DXVK toggle with HUD (✓ implemented)
- Performance presets (✓ implemented via `BottlePerformanceConfig`)
- Launcher auto-detection (✓ implemented via `LauncherPresets`)
- Process list with kill capability (✓ implemented via `RunningProcessesView`)
- Stability diagnostics (✓ implemented via `StabilityDiagnostics`)

**Critical gaps:**
- Per-bottle graphics backend selection (D3DMetal vs DXVK vs wined3d) — upstream issue #600 shows DXVK unusable when D3DMetal active via Steam; need `WINED3DMETAL` env var control
- Audio device diagnostics — 7+ upstream audio issues (#1127, #445, #637, #761, #312, #1352, #233) with zero in-app troubleshooting

**Should have (competitive differentiators):**
- Per-program graphics backend override (CrossOver's C4 database does this server-side; no open-source competitor has GUI for per-program backend selection)
- Game compatibility quick-reference with bundled JSON (curated, not community-scale)
- Guided troubleshooting for common issues (symptom → diagnostic checks → suggested fixes)
- Process lifecycle integration connecting `ProcessRegistry` to `RunningProcessesView` for live updates
- DXVK configuration file management (frame rate caps, shader cache settings)

**Defer (v2+):**
- Bottle snapshots/configuration rollback (HIGH complexity, disk usage concerns)
- macOS-native system diagnostics integration (Metal GPU errors, Rosetta issues)
- Full community compatibility database with server sync

**Anti-features (commonly requested, problematic):**
- Full community database (requires server infrastructure, moderation, stale data issues)
- In-app audio mixer (duplicates macOS functionality, Wine CoreAudio is pass-through)
- Auto-download multiple Wine versions (increases complexity and disk usage; WhiskyWine installer already handles this)

### Architecture Approach

The architecture extends the existing configuration cascade with a new "game profile" layer and separates process lifecycle management from individual process tracking.

**Major components:**
1. **Extended Configuration Cascade** — Add game profile layer between bottle settings and program settings: Wine defaults → macOS compat → bottle → game profile → program → user overrides. Requires explicit `EnvironmentBuilder` with documented precedence.
2. **Compatibility Database** (new WhiskyKit module) — Bundled JSON game profiles mapping executables/Steam IDs to recommended settings. Separate from `ProgramSettings` (game profile = template, program settings = user's actual config).
3. **Troubleshooting Engine** (new WhiskyKit module) — Symptom-driven decision trees stored as JSON data. Maps "black screen on launch" → diagnostic checks → suggested resolutions. Data-driven, not hardcoded.
4. **Process Lifecycle Manager** (new WhiskyKit module) — Wraps `ProcessRegistry` with wineserver-level tracking per bottle. Uses `wineserver --wait` for completion detection, `wineserver -k` for cleanup.
5. **WinetricksRunner** (new) — Programmatic winetricks execution with prefix validation via `WinePrefixValidation` first.

**Build order dependencies:**
```
1. ProgramSettings extensions (DLL overrides, winetricks verbs)
   ↓
2a. GameProfile model    2b. ProcessLifecycleManager    2c. WinetricksRunner
   ↓
3. CompatibilityDatabase (bundled JSON)
   ↓
4a. Compat UI views     4b. Extended config cascade integration
   ↓
5. TroubleshootingEngine + UI (uses all above)
   ↓
6. Community features (optional, network)
```

### Critical Pitfalls

1. **Treating Wine-layer bugs as app-layer fixable** — Setting global environment variables (e.g., `WINEFSYNC=0` in `MacOSCompatibility.swift`) that appear to fix one issue but silently break other games. Mitigation: All env var overrides must be per-bottle or per-program, never global defaults. Document what each override breaks alongside what it fixes.

2. **Building a stale compatibility database** — Game compatibility data becomes misleading within weeks as Wine/macOS/game versions change. ProtonDB suffers this exact issue. Mitigation: Attach version tuples `(macOS, Wine, game, date)` to entries; display staleness warnings; keep database small and curated (top 20-50 games) rather than crowd-sourced.

3. **Orphan Wine processes and incomplete lifecycle tracking** — Wine's `wine start` returns immediately after queuing with wineserver; the actual game runs as a wineserver child. Current `ProcessRegistry` loses track when the launcher exits. Lutris has identical bug (GitHub #4046). Mitigation: Track wineserver PID per bottle, use `wineserver -k` for cleanup, implement periodic liveness checks for orphan detection.

4. **Configuration setting explosion overwhelming users** — Each upstream issue suggests a specific env var fix; exposing all creates incomprehensible UIs. `BottleSettings` already has 30+ properties across 7 config types. Mitigation: Tiered UI (Simple/Advanced modes), group by symptom not by technical subsystem, validate setting combinations, provide "reset to defaults" per section.

5. **Environment variable override conflicts** — Multiple cascade layers set the same env var with conflicting merge strategies (`{ _, new in new }` vs `{ current, new in current.isEmpty ? new : current }`). The `environmentVariables()` method already flagged with SwiftLint complexity warnings. Mitigation: Implement explicit `EnvironmentBuilder` with documented precedence layers and integration tests for conflict scenarios.

6. **Audio "fixes" requiring Wine-layer changes** — Most macOS Wine audio issues are in `winecoreaudio.drv`, not in configuration. Adding toggles that provide false control wastes user effort. Mitigation: Scope audio phase as guidance-first (max 3-4 settings: driver selection, GStreamer debug, specific DLL overrides). Include diagnostics that check device availability and registry keys.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Configuration Foundation
**Rationale:** Must address environment variable conflict pitfall (#5) before adding more settings. The graphics UI phase will add DXVK/D3DMetal/Metal controls; the cascade must have explicit precedence first.
**Delivers:**
- `EnvironmentBuilder` with documented 6-layer precedence
- Integration tests for cascade scenarios
- "Show effective environment" debug view
- ProgramSettings extensions (DLL overrides, winetricks verbs)
**Addresses:** Foundation for all subsequent configuration features
**Avoids:** Pitfall #5 (env var conflicts), prevents pitfall #1 (app-layer vs Wine-layer bugs) via documentation requirement

### Phase 2: Graphics Configuration UI
**Rationale:** Critical table stakes gap (#600 — DXVK vs D3DMetal conflict). CrossOver 25 has this; upstream Whisky does not. Second-highest issue category after audio.
**Delivers:**
- Per-bottle D3DMetal/DXVK/wined3d backend toggle (`WINED3DMETAL` control)
- Tiered UI design (Simple/Advanced modes)
- Setting validation (e.g., Force D3D11 disables D3D12 options)
- Reset to defaults per section
**Addresses:** FEATURES.md table stakes gap, upstream issue #600
**Uses:** Configuration cascade from Phase 1
**Avoids:** Pitfall #4 (settings explosion) via tiered UI from start

### Phase 3: Process Lifecycle Management
**Rationale:** Existing `ProcessRegistry` tracks wrong abstraction (individual PIDs instead of wineserver). Must fix before exposing auto-cleanup features. Independent of graphics/audio phases.
**Delivers:**
- `ProcessLifecycleManager` wrapping `ProcessRegistry`
- Wineserver PID tracking per bottle
- `wineserver --wait` integration
- Orphan process detection
- Live-updating `RunningProcessesView`
**Addresses:** FEATURES.md differentiator (ProcessRegistry integration)
**Avoids:** Pitfall #3 (orphan processes)

### Phase 4: Game Compatibility Database
**Rationale:** Requires Phase 1 complete (ProgramSettings extensions, cascade). Provides data layer for troubleshooting (Phase 6). Can run parallel to Phase 3 (no dependency).
**Delivers:**
- `GameProfile` model (executable patterns, recommended settings)
- Bundled `compatibility-db.json` (top 20-50 games from upstream issues)
- `CompatibilityDatabase` singleton with in-memory index
- `GameMatcher` for automatic profile application
**Addresses:** FEATURES.md differentiator
**Uses:** Configuration cascade to apply game profiles
**Avoids:** Pitfall #2 (stale data) by attaching version tuples and limiting scope

### Phase 5: Audio Troubleshooting
**Rationale:** 7+ upstream issues with zero current remediation. Scoped as diagnostics-first to avoid pitfall #6 (audio fixes requiring Wine changes).
**Delivers:**
- CoreAudio device detection utility
- Audio diagnostics panel (device status, sample rate, Bluetooth state)
- Wine audio driver registry verification
- Guidance linking to macOS Sound settings
- Maximum 3-4 configurable settings (driver selection, GStreamer debug, DLL overrides)
**Addresses:** Critical table stakes gap (7+ upstream audio issues)
**Avoids:** Pitfall #6 (false-fix settings) by limiting to diagnostics + guidance

### Phase 6: Per-Program Graphics Overrides
**Rationale:** Depends on Phase 2 (per-bottle backend toggle) and Phase 4 (game profiles for auto-application). Differentiator feature (CrossOver has this server-side, no OSS competitor has GUI).
**Delivers:**
- `ProgramSettings.graphicsBackend` override
- Per-program DXVK config (frame rate cap, async)
- Inspector-style UI for per-program settings
**Addresses:** FEATURES.md differentiator
**Uses:** Game profiles from Phase 4 for auto-suggestions

### Phase 7: Guided Troubleshooting
**Rationale:** Integration layer connecting all previous phases. Requires diagnostics (Phase 5), compatibility data (Phase 4), and process tracking (Phase 3). Should come last in v1.x cycle.
**Delivers:**
- `TroubleshootingEngine` with symptom-driven decision trees
- Bundled `troubleshooting-guide.json`
- Interactive troubleshooting flow UI
- `DiagnosticCollector` aggregating system/bottle/Wine state
**Addresses:** FEATURES.md differentiator
**Uses:** All components built in Phases 1-6
**Avoids:** Pitfall #2 (stale data) by structuring as "try these steps" not "this game is broken"

### Phase Ordering Rationale

- **Phase 1 must come first:** The configuration cascade is foundational. Adding graphics UI (Phase 2) or game profiles (Phase 4) on top of the current merge-strategy inconsistencies multiplies complexity.
- **Phases 2-3 are parallel-capable:** Graphics config and process lifecycle have no dependencies on each other. Both depend only on Phase 1.
- **Phase 4 depends on Phase 1:** GameProfile applies environment overrides via the cascade. Must have stable cascade first.
- **Phase 5 is independent:** Audio diagnostics don't depend on graphics or compatibility features. Can run parallel to Phases 3-4.
- **Phases 6-7 are integration layers:** They consume components from earlier phases and should come last.

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 4 (Game Compatibility):** Game selection criteria (which 20-50 games to include in initial DB) requires analysis of upstream issue frequency and GitHub Discussions data.
- **Phase 7 (Guided Troubleshooting):** Symptom-to-solution mappings require mining upstream issues for common patterns and validated fixes.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Configuration Foundation):** Environment variable precedence is well-understood; integration testing patterns are standard.
- **Phase 2 (Graphics Config UI):** SwiftUI Form patterns already researched in STACK.md; DXVK/D3DMetal env vars documented in Wine/DXVK wikis.
- **Phase 3 (Process Lifecycle):** Wineserver behavior documented in man pages and WineHQ forums; pattern established in competitor analysis.
- **Phase 5 (Audio Troubleshooting):** CoreAudio detection via `AVAudioSession` is standard macOS; Wine audio driver registry keys documented.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Existing stack well-analyzed; recommended additions are Apple frameworks (documented) or Wine built-ins (community-documented) |
| Features | MEDIUM-HIGH | Table stakes verified via competitor analysis (CrossOver, Bottles, Lutris); differentiators based on upstream issue frequency |
| Architecture | HIGH | Existing codebase thoroughly analyzed; extension patterns follow established WhiskyKit structure; build order validated via dependency graph |
| Pitfalls | MEDIUM-HIGH | Critical pitfalls verified via competitor bug trackers (Lutris #4046 orphan processes, Bottles #3128 env var bugs, ProtonDB staleness critiques); some macOS-specific areas (CoreAudio, Metal) are MEDIUM due to limited public debugging documentation |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Wine version compatibility matrix:** Research identified that settings depend on Wine 11.0 behavior, but didn't map which features work on older Wine versions. Handle during Phase 2-4 planning by testing on Wine 9.x/10.x if backward compatibility is needed.

- **macOS version-gated audio behavior:** Audio research identified sample rate mismatches and Bluetooth device issues but didn't quantify which macOS versions exhibit which bugs. Handle during Phase 5 planning by surveying upstream issues for macOS version tags.

- **Game selection criteria for compatibility database:** Research recommends "top 20-50 games" but didn't define selection algorithm. Handle during Phase 4 planning by analyzing upstream issue labels, GitHub Discussion #348 comments, and AppleGamingWiki page views.

- **Troubleshooting decision tree structure:** Research established symptom-driven approach but didn't map specific symptoms to solutions. Handle during Phase 7 planning by mining upstream issues for "tried X, then Y worked" patterns.

- **DXVK/MoltenVK version coupling:** Stack research noted MoltenVK/DXVK bundled with WhiskyWine but didn't identify which versions or update cadence. Validate during Phase 2 planning when implementing DXVK config features.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `WhiskyKit/Sources/WhiskyKit/` (all modules analyzed)
- [Wine Debug Channels Wiki](https://wiki.winehq.org/Debug_Channels)
- [Apple MetricKit Documentation](https://developer.apple.com/documentation/MetricKit)
- [Apple OSLogStore Documentation](https://developer.apple.com/documentation/os/oslogstore)
- [Apple SwiftUI Settings Documentation](https://developer.apple.com/documentation/swiftui/settings)
- [Apple Observable Migration Guide](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Whisky upstream issues](https://github.com/Whisky-App/Whisky/issues) (#600, #844, #219, #1127, #445, #637, #761, #312, #1352, #233)
- [Lutris process management bugs](https://github.com/lutris/lutris/issues) (#4046, #176, #4679, #5841, #2539, #4266)
- [wineserver man page](https://man.archlinux.org/man/wineserver.1.en)
- [Wine environment variables reference](https://simpler-website.pages.dev/html/2021/1/wine-environment-variables/)

### Secondary (MEDIUM confidence)
- [CrossOver Advanced Settings](https://support.codeweavers.com/miscellanous/advanced-settings-in-crossover-mac)
- [CrossOver 25 announcement](https://www.codeweavers.com/blog/mjohnson/2025/3/11/experience-next-level-gaming-on-mac-with-crossover-25)
- [Bottles Documentation](https://docs.usebottles.com/)
- [Bottles versioning feature](https://www.gamingonlinux.com/2022/07/wine-manager-app-bottles-makes-rolling-back-configs-real-easy/)
- [Bottles environment variables bug #3128](https://github.com/bottlesdevs/Bottles/issues/3128)
- [Bottles process kill bug #3746](https://github.com/bottlesdevs/Bottles/issues/3746)
- [AppleGamingWiki - CrossOver](https://www.applegamingwiki.com/wiki/CrossOver)
- [AppleGamingWiki - Game Porting Toolkit](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit)
- [Whisky Game List Discussion #348](https://github.com/orgs/Whisky-App/discussions/348)
- [DXVK Common Issues](https://github.com/doitsujin/dxvk/wiki/Common-issues)
- [ProtonDB reliability critiques](https://ps2bios.gitlab.io/home/we-need-to-stop-telling-folks-to-simply-rely-on-protondb-its-not-that-simple/)

### Tertiary (LOW confidence)
- [ProtonDB Community API](https://github.com/Trsnaqe/protondb-community-api) — Data model reference, but API not used
- [SwiftUI for Mac 2025](https://troz.net/post/2025/swiftui-mac-2025/) — Current patterns assessment
- [MoltenVK 1.4.0 release](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.0) — Version reference, exact bundled version needs validation

---
*Research completed: 2026-02-08*
*Ready for roadmap: yes*
