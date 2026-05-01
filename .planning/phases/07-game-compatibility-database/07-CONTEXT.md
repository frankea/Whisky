# Phase 7: Game Compatibility Database - Context

**Gathered:** 2026-02-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Bundled database of known-good game configurations with search, auto-detection, and one-click apply. Users can look up verified configs for common games, view per-game troubleshooting notes, and apply recommended settings (env vars, DLL overrides, winetricks verbs) to a bottle or program. Compatibility entries display version/staleness info. Community submission infrastructure and remote DB refresh are out of scope for v1 (designed for but deferred).

</domain>

<decisions>
## Implementation Decisions

### Discovery & matching
- **Primary entry point:** Global "Game Configurations" view with prominent search box (title + aliases), filters (store, backend, anti-cheat, rating), and "Apply to..." action
- **Contextual suggestions (secondary):** Auto-detect when adding/opening an exe or creating a bottle; show "Config available: Apply" banner. In program settings: "Recommended configs for this program" if matched. In crash diagnostics: remediation cards can link to "Apply known-good config"
- **Matching strategy:** Tiered confidence scoring with explainability:
  - Hard identifiers (auto-apply eligible): Steam App ID from appmanifest/steam_appid.txt, exe fingerprint (sha256 or size+PE timestamp)
  - Strong heuristic (auto-suggest, require confirmation): Exact exe filename, PE metadata (ProductName, CompanyName), install path patterns
  - Fuzzy (search results only): Tokenized name matching against exe name, folder names, DB title + aliases with similarity scoring and minimum threshold
- **Negative handling:** Penalize generic executables (launcher.exe, setup.exe, etc.). If top-2 scores are close, show "Possible matches" instead of auto-suggesting. Always show "Why this match?" explanation and allow "Not this" suppression
- **Search scope:** DB entries only by default. Empty state shows "No configuration found" with actions for requesting/submitting a config. Optional toggle "Include installed programs" for secondary flow

### Apply experience
- **Preview:** Always show before/after diff by default, grouped by area (Graphics, Performance, Input, DLL overrides, Winetricks, env vars). High-impact changes called out explicitly. "Don't show again" option available
- **Apply target:** Context-aware default — program-level when triggered from program context, user chooses (bottle vs program) from global view. Config can include both scopes; show both in preview with optional parts uncheckable
- **Undo/revert:** Snapshot current settings (Metadata.plist, program plists) before apply. Toast with one-click Undo after apply. "Revert config changes" available from game config page or bottle Config screen. Revert restores settings exactly; winetricks/prefix mutations noted as non-reversible ("Settings reverted; installed components remain")
- **Winetricks handling:** Preflight check in preview lists required verbs and which are missing. Explicit "Install Required Components..." action (never silent). Allow "Apply settings only" if user declines installs; mark config as "Incomplete (missing dependencies)"
- **Restart behavior:** If changes require restart, show "Apply and restart (next launch)" option; never silently stop running processes

### Entry content & presentation
- **List view rows:** Title + subtitle (edition/store), rating badge (Works/Playable/Unverified/Broken/Not Supported), recommended backend tag (DXVK/D3DMetal/WineD3D), key constraint tags (Apple Silicon, Intel, Wine 10+), one-line note (most important caveat). Primary click opens detail; secondary quick action "Apply..."
- **Rating tiers (fixed set):**
  - Works — no major issues
  - Playable — workarounds required or minor issues
  - Unverified — config exists but not recently validated
  - Broken — should work in principle but currently doesn't
  - Not Supported — fundamentally blocked (anti-cheat/kernel driver)
- **Detail view sections:**
  1. At a glance: status, platform constraints, known blockers
  2. Recommended configuration: primary variant card with "Apply" and 2-3 bullet rationale
  3. Variants: alternate configs labeled by constraints/intent with "when to use"
  4. What it changes: concise grouped summary
  5. Notes / Known issues: bullet list of common problems and workarounds
  6. Provenance: source/author, last updated, reference link (detail-level only; elevated for unverified/community entries)
- **Variants:** One game entry with multiple variants. Auto-select "Recommended for this machine" using CPU arch, macOS version, Wine version, backend capabilities. If multiple fit, show top 2-3 with one-line diff summary. Wine version changes require explicit confirmation
- **Data sourcing (initial 20-50 entries):**
  1. Maintainer-verified configs (tested end-to-end with full provenance)
  2. Existing Whisky knowledge from launcher presets + issue threads
  3. Community submissions via PR with evidence bundle requirement
  4. External databases (WineHQ/ProtonDB) as reference only — re-derive Whisky-specific settings, cite source
  - Selection criteria: high user demand, no anti-cheat hard blockers, configs that actually change settings, span common engines/launchers

### Staleness & trust signals
- **Staleness detection:** Store lastTestedAt + tested macOS/Wine/Whisky versions + CPU arch per entry. Show "Stale" warning when: >90 days since last tested, OR user's macOS newer by >1 minor release, OR Wine major version differs (unless compatible range declared)
- **Stale apply:** Warning banner in preview ("This config hasn't been verified recently on your macOS/Wine version") with "Apply anyway" — no hard block, staleness is a signal not a stop
- **DB updates:** Bundled-only for v1 (GameDB.json ships with app, works offline, reviewable via PRs). Remote signed overlay designed but deferred — opt-in toggle, signature verification, additive-only, falls back to bundled on failure
- **Provenance display:** In detail view "About this config" section near bottom. Exception: unverified/community entries surface trust cue higher ("Community config, not maintainer-verified")

### Claude's Discretion
- JSON schema design for GameDB entries
- Matching algorithm implementation (similarity scoring, threshold tuning)
- List/detail view layout specifics (spacing, typography)
- Snapshot storage format for undo/revert
- How "Don't show again" preference is persisted
- Raw settings display in "Show advanced details" expandable

</decisions>

<specifics>
## Specific Ideas

- Search should feel like Command-K style — fast, prominent, not buried in navigation
- "Why this match?" explainability on auto-detected configs (e.g., "Matched Steam appid 12345" or "Matched exe name + product name")
- Variant selection feels like choosing a configuration profile — one recommended, alternatives clearly labeled
- Apply preview grouped by area mirrors existing settings UI structure (Graphics/Performance/Input/DLL overrides/Winetricks/env vars)
- Avoid making users browse long lists; they should either search by name or be offered a config when Whisky already knows what they're running
- Remote overlay design: signed + versioned JSON, ETag caching, public key baked in app, restricted to non-destructive setting changes

</specifics>

<deferred>
## Deferred Ideas

- Remote DB refresh / community config updates — designed schema and safety model but deferred to post-v1
- Community submission workflow (in-app "Submit config" with evidence bundle) — future enhancement
- "Re-test + submit results" flow for stale entries — future enhancement

</deferred>

---

*Phase: 07-game-compatibility-database*
*Context gathered: 2026-02-10*
