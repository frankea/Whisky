# Phase 8: Remaining Platform Issues - Context

**Gathered:** 2026-02-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Resolve launcher, controller, and installation/dependency issues from upstream tracking categories through code fixes and in-app guidance. All 7 existing LauncherType entries (Steam, EA, Rockstar, Epic, Ubisoft Connect, Battle.net, Paradox) get first-class support. Controller work focuses on "make them work" (not remapping). Dependency tracking leverages existing Winetricks infrastructure. Detection integrates with Phase 5 diagnostics pipeline.

</domain>

<decisions>
## Implementation Decisions

### Launcher guidance — discovery and surfacing
- Three-tier discovery model: (1) launch-time banner/toast showing fixes applied with "View details" link, (2) Bottle Config Launcher section as source of truth with toggles and EnvironmentBuilder provenance, (3) Diagnostics remediation cards that deep-link to config sections
- No separate "launcher fixes screen" — workarounds surface at launch time, in Config, or in Diagnostics
- All 7 existing LauncherType entries are first-class; everything else gets generic Chromium/CEF/macOS-compat fixes

### Launcher guidance — fix application style
- Mostly automatic for env/settings that are reversible and low-risk (locale overrides, CEF sandbox flags, network timeouts, GPU spoofing, managed DLL overrides)
- User-confirmed for anything that changes the prefix/files or stops running processes (graphics backend switch, clipboard clearing, winetricks installs)
- Rule: if it's just configuration/env and "next launch", do it automatically and surface what changed

### Launcher guidance — macOS version compatibility
- Managed version-gated fixes in MacOSCompatibility layer, keyed by MacOSVersion ranges, auto-applied on every Wine/launcher run
- Launcher-specific workarounds in LauncherType.environmentOverrides() can also branch on MacOSVersion.current
- Treated as managed settings (not user-editable by default); shown via EnvironmentBuilder provenance ("Applied because macOS = 15.4+")
- New macOS regressions ship as targeted, version-scoped fixes with env snapshot tests

### Controller mapping UX — location and detection
- Bottle-level Controllers section in ConfigView (InputConfigSection) as primary location
- Per-program overrides via existing inherit/override pattern in ProgramOverrides
- Connected Controllers subpanel (collapsed by default) showing: name + type badge (PlayStation/Xbox/Generic), connection badge (USB/Bluetooth), battery if available, status
- Actions: Test Input (live button/stick viewer), Copy Controller Info (for diagnostics), Refresh
- Bluetooth inline warning: "Bluetooth dropouts can break input; USB is more reliable"
- Empty state: "No controllers detected" + troubleshooting hint

### Controller mapping UX — mapping depth
- Minimal in Phase 8: existing compatibility toggles only (HIDAPI off, background events, native labels)
- Simple "Treat as XInput" vs "Native labels" choice via SDL hints if cleanly implementable
- No per-button remapping, deadzone curves, trigger thresholds, or controller profiles — future phase if needed
- Point users to in-game settings or Steam Input for custom mapping

### Controller mapping UX — persistence
- Persist settings only, not device identity (controller IDs change with re-pairing)
- Lightweight recent history (controller names + connection type + timestamps) for diagnostics/export only
- No controller-to-bottle binding by default; explicit Advanced option if added later

### Dependency tracking — status display
- Dependencies section in bottle Config showing 3-5 named components (Visual C++ Runtime, .NET 4.8, DirectX runtime, optionally DirectX audio, etc.)
- Each row: status (Installed/Not installed/Unknown), last-checked timestamp + Refresh, Install action, Details
- Contextual surfaces in program settings and crash diagnostics: "Missing dependency: X" badges that deep-link to bottle Dependencies section
- "Installed" = high confidence only when Winetricks reports it

### Dependency tracking — detection model
- Tiered: (1) winetricks list-installed headlessly (authoritative), (2) WinetricksCache.plist with log mtime gating (fast path), (3) winetricks.log parse (fallback), (4) DLL/registry probes labeled "Detected (heuristic)" not "Installed" (optional)
- Leverages existing WinetricksVerbCache and Winetricks+InstalledVerbs infrastructure from Phase 2

### Dependency tracking — installation guide
- Guided install sheet with sections: What you're installing (name + purpose + scope), Preflight checks (prefix health, estimated time), Plan (diff-style verb list + ordering + irreversibility warning), Run (progress states + collapsible live log), Verify (re-check via list-installed + cache refresh)
- Entry points: remediation card, bottle Dependencies section, game config apply preflight
- Never silently install; always require explicit Install click
- Multiple verbs run as queued plan with partial success display
- Run winetricks headlessly via Process (not Terminal) so macOS attributes volume access to Whisky
- Persist attempt history for diagnostics export

### Dependency tracking — recommendations
- Recommend only with high-confidence signals: game config preflight (missing required verbs), crash classifier (DLL-not-found patterns), known app types (ClickOnce → dotnet48)
- Small banner in Program view / launch failure toast: "Missing dependency detected: X" with Install and Dismiss
- Track dismiss per program/bottle; don't reappear until new evidence
- Never recommend "common deps" without evidence; never auto-install

### Detection & alerting — Steam download stalls
- Gate: only when detected launcher is Steam and Steam is running in the bottle
- Signal: presence of steamapps/downloading/* subdirs
- Heuristic: sample every 30-60s, mark "likely stalled" if no mtime/size change for 3-5 minutes
- Corroborate with WinHTTP/WinINet timeout/TLS errors or Steam content log stall lines for high confidence
- Surface: non-blocking banner with quick links to Network Timeout slider and known fixes (WINE_FORCE_HTTP11, WINE_MAX_CONNECTIONS_PER_SERVER)

### Detection & alerting — alert stance
- Default passive: show "Download health" status inside bottle's Launcher/Diagnostics area
- Push alert only on high confidence (downloads in progress + sustained no-progress + optional log corroboration)
- Single non-blocking banner/toast with Fixes deep-link and Dismiss
- Rate-limited: once per bottle per session, with per-bottle "Don't warn again" choice
- No background notifications when app isn't frontmost; record findings for when user returns

### Detection & alerting — volume access permissions
- Default bottles stay in Application Support (no Removable/Network volume access needed)
- External/network volumes: require user-selected folder/file picker the first time
- Run winetricks/dependency installs headlessly via Process (not Terminal) to reduce prompt sources
- Copy installers into prefix or Whisky-managed temp dir before running
- Clear usage description strings in Info.plist for when prompts do occur

### Detection & alerting — diagnostics integration
- Steam stall detection emits diagnostic finding in Phase 5 pipeline (category: networkingLaunchers, confidence tier, evidence)
- UI alert is thin surface over the diagnostic finding (toast + deep-link to Launcher settings + diagnostics report)
- Include stall findings and relevant env vars in exported diagnostics for reproducibility

### Claude's Discretion
- Exact sampling intervals and stall thresholds for download detection
- Controller subpanel layout and collapse behavior
- Dependency section ordering and component grouping
- Banner/toast animation and positioning details
- Preflight check implementation for dependency installer
- SDL hint mapping for XInput vs Native labels

</decisions>

<specifics>
## Specific Ideas

- Launch-time banner should feel like a status notification, not a blocking dialog — "Launcher fixes applied: Steam (locale, DXVK, network timeout)" with View Details link
- Blocking sheet only for fixes requiring user action (clipboard clear, backend restart)
- Controller Test Input should be a small live viewer for buttons/sticks (not a full-screen affair)
- Dependency install sheet should own the UX end-to-end even if winetricks is the underlying implementation — "we started the install" + "verify status" rather than dumping user into Terminal
- Connected Controllers panel should feel like a system info panel (similar to macOS System Settings > Bluetooth device list)
- EnvironmentBuilder provenance should make managed fixes transparent: "Applied because macOS = 15.4+" rather than hiding them

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-remaining-platform-issues*
*Context gathered: 2026-02-10*
