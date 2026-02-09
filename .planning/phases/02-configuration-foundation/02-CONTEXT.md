# Phase 2: Configuration Foundation - Context

**Gathered:** 2026-02-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Unify the environment variable cascade into a single EnvironmentBuilder with explicit layer ordering, composable WINEDLLOVERRIDES, per-program setting overrides, and winetricks verb tracking. This is the foundation that graphics, audio, game profiles, and troubleshooting phases build on. No new user-facing features beyond the configuration editors described here.

</domain>

<decisions>
## Implementation Decisions

### DLL Override Editing
- First-class structured DLL override editor: table with DLL name (no `.dll` suffix) + Mode dropdown (`Builtin (b)`, `Native (n)`, `Native then Builtin (n,b)`, `Builtin then Native (b,n)`, `Disabled`)
- Add / Remove / Reset actions in the editor
- Show "Inherited (from bottle)" vs "Overridden (this program)" indicators
- Store overrides as structured data (dictionary) in ProgramSettings; EnvironmentBuilder renders the final `WINEDLLOVERRIDES` string
- Optional "Advanced" reveal for raw `WINEDLLOVERRIDES` editing as escape hatch; normal path is the structured editor
- Lightweight presets via a `Presets...` button: at minimum `DXVK (recommended)` applying `dxgi,d3d9,d3d10core,d3d11=n,b`. Presets write explicit entries (transparent, editable), not magic modes
- Per-DLL conflict resolution: `effective[dll] = programOverride[dll] ?? bottleCustom[dll] ?? bottleManaged[dll]`
- If user overrides a DXVK-managed DLL away from `n,b`, show a small warning ("This override disables DXVK for this program")

### DLL Override — Bottle Level
- Keep existing implicit behavior: DXVK toggle + launcher presets generate "Managed" overrides (read-only in UI, lock icon, note like "Set by DXVK" or "Set by Launcher fixes")
- Add an "Advanced: Custom DLL Overrides" table at bottle level (same structured editor as per-program)
- Effective DLL override order: managed (DXVK/launcher) → bottle custom → program custom (most specific wins per-DLL)
- Warning if user's custom entries override a managed DXVK DLL

### Winetricks Verb Tracking
- Primary discovery: run bundled `winetricks list-installed` non-interactively with bottle env (`WINEPREFIX`, `WINE=wine64`, `PATH` including WhiskyWine + `cabextract`), parse stdout into `Set<String>`
- Fallback: parse `<WINEPREFIX>/winetricks.log` for "Executing/Installed" markers (best-effort)
- Only scan when opening Winetricks UI or on explicit refresh — not on every bottle open
- Persist a per-bottle cache of installed verbs; load instantly from cache on UI open
- Background refresh: after loading cache, kick off fresh check and update UI if changed
- Cheap staleness detection via `winetricks.log` mtime/size before spawning winetricks
- UI: In WinetricksView, add toggle/segmented control `All` / `Installed`; show "Installed" indicator (checkmark/tag) on verb rows; optionally sort installed to top
- Verb tracking is bottle/prefix-scoped (source of truth: `bottle.appliedWinetricksVerbs`)
- In program settings, show "This bottle has: vcrun2019, dotnet48..." as read-only info with optional "Used by this program" tags for user organization (metadata only, doesn't change the prefix)

### Layer Model (EnvironmentBuilder)
- 8 coarse, stable layers in merge order (later wins):
  1. `base` — WINEPREFIX, default WINEDEBUG, PATH-related defaults
  2. `platform` — macOS compatibility fixes (applyMacOSCompatibilityFixes)
  3. `bottle_managed` — toggles/presets Whisky owns (DXVK, Metal/D3DM flags, sync mode, performance preset, shader cache)
  4. `launcher_managed` — launcher compatibility mode + detected launcher overrides
  5. `bottle_user` — user-defined bottle env vars (custom key/value entries)
  6. `program_user` — program settings env vars + locale/args-derived env
  7. `feature_runtime` — launch-time feature injectors (ClickOnce env, one-off launch modes)
  8. `callsite_override` — explicit overrides passed to Wine.runProgram(environment:) (highest priority)
- Future additions (game profiles, audio settings) slot into `bottle_managed` or `feature_runtime`, not new top-level layers
- EnvironmentBuilder returns both final `[String: String]` and provenance data (`key → [Layer]` with `winningLayer` + `overriddenBy`)
- Provenance data captured in Phase 2; Environment Inspector UI deferred to Phase 5 (Diagnostics)

### Launch Logging
- Do NOT log full resolved environment by default (noisy, risk of leaking sensitive values)
- Log a small safe summary at launch: bottle name/id, program, whitelisted non-sensitive keys (DXVK/Metal/sync flags), which layers were active
- Provide opt-in diagnostics mode or "Copy environment report" action for full environment + provenance with redaction for sensitive keys

### Per-Program Override Scope
- Overrideable per program in Phase 2 (env-only / launch-time settings):
  - DXVK: on/off, async, HUD
  - Sync mode: enhancedSync (none/esync/msync)
  - D3D mode: forceD3D11
  - Performance: performancePreset, shaderCacheEnabled
  - Input/SDL fixes: controller compatibility toggles (disableHIDAPI, allowBackgroundEvents, disableControllerMapping)
  - DLL overrides (structured editor)
- Stays bottle-only (NOT per-program in Phase 2):
  - windowsVersion, wineVersion, pins/blocklist, vcRedistInstalled
  - Cleanup policies: clipboardPolicy, clipboardThreshold, killOnQuit
  - Diagnostics-style Metal toggles (metalTrace, metalValidation)

### Per-Program Override UX
- Each overrideable group (Graphics/DXVK, Sync, Performance, Input, DLL overrides) defaults to "Inherit from bottle"
- Single toggle/picker per group flips to "Override", revealing controls with current inherited value as starting value (copy-on-enable)
- Show "Currently inherited: ..." summary when in inherit mode
- "Reset Overrides" action clears `ProgramSettings.overrides` (all override fields to nil); leaves per-program arguments, environment, and locale untouched

### Per-Program Data Model
- Extend `ProgramSettings` with nested `ProgramOverrides?` where each field is optional (nil = inherit)
- Keep existing locale/environment/arguments as-is; don't bloat with bottle-level fields
- One plist per program; missing keys decode as inherit (backward-compatible)
- EnvironmentBuilder gets a clean "program override layer" to apply

### Claude's Discretion
- Exact EnvironmentBuilder API surface and internal architecture
- How to structure the provenance data types
- Preset definitions beyond DXVK (add .NET/ClickOnce only if exact DLLs can be justified)
- Winetricks log parsing implementation details
- Compression/optimization of cached verb state
- Exact UI layout of the DLL override editor and per-program settings sections
- Whether to include raw WINEDLLOVERRIDES escape hatch or defer it

</decisions>

<specifics>
## Specific Ideas

- DLL override presets should be "apply" (writes explicit entries) not magic modes — final config is always transparent and editable
- Managed DLL overrides (from DXVK toggle, launcher presets) should show lock icon and source label in the editor
- Winetricks verb caching should use `winetricks.log` mtime/size for cheap staleness detection
- Per-program override pattern: "Inherit from bottle" default with copy-on-enable when switching to "Override"
- Provenance should include `overriddenBy` so downstream inspector can show "X was overridden by Y"

</specifics>

<deferred>
## Deferred Ideas

- Environment Inspector UI — Phase 5 (Stability & Diagnostics), using provenance data from EnvironmentBuilder
- Game profile system — Phase 7, will use EnvironmentBuilder layers
- Audio-specific env settings — Phase 6, slots into bottle_managed layer
- Startup zombie process sweep — Phase 3 (ProcessRegistry is session-based)

</deferred>

---

*Phase: 02-configuration-foundation*
*Context gathered: 2026-02-09*
