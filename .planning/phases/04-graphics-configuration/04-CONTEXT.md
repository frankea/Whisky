# Phase 4: Graphics Configuration - Context

**Gathered:** 2026-02-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Per-bottle and per-program control of Wine graphics backends (D3DMetal, DXVK, wined3d) with a tiered Simple/Advanced settings UI. Backend selection, DXVK toggle/settings, and dxvk.conf file management. No new diagnostics, no game profiles, no troubleshooting flows.

</domain>

<decisions>
## Implementation Decisions

### Simple/Advanced toggle
- Segmented control at the top of the Graphics section: `Simple` | `Advanced`
- Persisted as a **global (app-wide) user preference** in UserDefaults, not per-bottle
- Stable layout: same section header, Advanced controls appear below with disclosure animation
- Simple mode shows only: backend picker, Force DX11, Sequoia Compatibility Mode
- Advanced mode reveals: DXVK async, HUD, dxvk.conf management, per-program overrides, and other granular settings
- When a bottle has advanced-only settings configured, show subtle badge in Simple mode: "Advanced settings active" with one-click jump to Advanced

### Backend picker
- Selection card control (2x2 grid or 1x4 on wide): `Recommended` (Auto), `D3DMetal`, `DXVK`, `WineD3D`
- Each card shows: icon + name, 1-line summary, optional tags (`Fast`, `Compatible`, etc.)
- `Recommended` is a real **Auto enum case** (`backend = .recommended`) that resolves at launch via EnvironmentBuilder using GPU/OS heuristics
- Helper text below grid: "Currently: D3DMetal" for Recommended, "Takes effect next launch" for manual choices
- Optional "Why?" popover explaining the auto-selection rationale
- Resolved backend also shown subtly in bottle header/info bar when Auto is selected

### Backend switching behavior
- Setting changes immediately, takes effect on **next launch**
- No confirmation dialog for switching (not destructive)
- If bottle has running processes: warning banner with `Apply on next launch` (default) and `Stop Bottle Now…`
- Inline warning (not modal) if selecting a backend known to be incompatible with user's setup
- Never auto-relaunch programs

### DXVK settings
- First-class UI controls (curated, stable subset only):
  - `Enable DXVK` toggle
  - `DXVK Async` toggle
  - `DXVK HUD`: preset picker (Off / FPS / Partial / Full) mapping to standard DXVK_HUD strings
- DXVK controls visible only when DXVK is active backend:
  - Simple mode: show when backend is DXVK or Recommended→DXVK, otherwise hide
  - Advanced mode: show collapsed "DXVK" section with "Inactive" note when another backend is active
- No per-element HUD builder; presets only (custom DXVK_HUD string as future Advanced option)

### dxvk.conf file management (Advanced only)
- Show where config is loaded from (bottle or program level)
- Actions: `Open in Editor` (NSWorkspace default editor), `Reveal in Finder`, `Reset/Delete`
- Optional "Apply preset" that writes known-safe snippet (keep minimal)
- No inline text editor in Phase 4

### Per-program graphics overrides
- Follow the **exact same inherit/override pattern** from Phase 2 (02-04)
- Available in **Advanced mode only**
- In Simple mode: show note "Per-program overrides active" with one-click jump if overrides exist
- Override scope: full graphics settings (backend, dxvkEnabled, dxvkAsync, dxvkHud) — each as optional `nil = inherit`
- One "Override Graphics" toggle enables the group; sub-settings each have Inherit/Override state
- "Takes effect next launch" note always shown; running-process warning banner when applicable
- Programs with active graphics overrides show small badge/icon (sliders) in program list with "Graphics overridden" tooltip

### Claude's Discretion
- Exact selection card visual design and icon choices
- GPU detection heuristics for Recommended backend resolution
- Animation/transition details for Simple↔Advanced disclosure
- Specific summary text and tags on backend cards
- Layout of DXVK preset picker
- Badge design for "Advanced settings active" and program override indicators

</decisions>

<specifics>
## Specific Ideas

- Backend cards should feel like selection cards, not radio buttons — each with enough info to make an informed choice
- "Recommended (currently: D3DMetal)" pattern for showing resolved Auto backend
- Sequoia Compatibility Mode toggle should only appear when relevant (macOS 15+)
- DXVK settings surface should be "doable and maintainable" — avoid becoming a maintenance trap for version-dependent config
- External editor for dxvk.conf keeps Phase 4 scope manageable

</specifics>

<deferred>
## Deferred Ideas

- Custom per-element DXVK HUD builder — future enhancement to Advanced mode
- Inline text editor for dxvk.conf — future if demand warrants
- "Stop and relaunch last program" after backend switch — future convenience feature
- Per-program dxvk.conf management — consider in later phases if needed

</deferred>

---

*Phase: 04-graphics-configuration*
*Context gathered: 2026-02-09*
