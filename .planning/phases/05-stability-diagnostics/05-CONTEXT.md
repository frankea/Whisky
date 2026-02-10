# Phase 5: Stability & Diagnostics - Context

**Gathered:** 2026-02-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Parse and classify Wine error output so users receive actionable crash guidance instead of raw logs. Includes error classification engine, remediation suggestions, diagnostic report export, and WINEDEBUG preset management. Does NOT include guided troubleshooting flows (Phase 10) or game compatibility data (Phase 7).

</domain>

<decisions>
## Implementation Decisions

### Crash guidance presentation
- Summary-first layout: diagnosis summary at top, then remediation cards, then collapsible raw log (collapsed by default)
- Split view on desktop if space allows: suggestions (left, fixed) + log output (right, scrollable)
- Remediation cards are actionable with guardrails:
  - Low-risk reversible changes get direct action buttons (e.g., "Enable DXVK", "Force D3D11")
  - Higher-risk/stateful actions get guided paths with confirmation (e.g., "Install vcrun2019" opens Winetricks with verb selected)
- Every remediation card includes: "What will change" (one sentence), "Undo" path, "Applies next launch" note when relevant
- Auto-trigger classification when Wine process exits non-zero, Whisky force-stops a process, or end-of-log scan finds crash signatures
- On-demand "Analyze latest log" / "Analyze last run" buttons for everything else
- 3-tier confidence model: High (signature match), Medium (multiple signals), Low (heuristic/single weak signal)
- Show confidence label + expandable "Why" line per diagnosis
- Sort remediation cards by confidence and impact; hide low-confidence behind "Other things to try"
- Internal numeric score (0-1) mapped to tiers; raw numbers never shown to users

### Error classification display
- Minimal inline log tagging: background tint + left gutter marker for strong matches only (Error, Warning, Crash signature, Graphics)
- Don't color every Wine "fixme" — keep raw log readable
- Filter buttons above log: Show all / Only tagged / Crash-related, plus search box
- Summary shows primary headline diagnosis (highest severity + confidence) at top
- Compact category counts below headline, each clickable to filter log (e.g., "DLL load failures: 3")
- Persist last diagnosis summary per program (small sidecar JSON/plist, last 5 per program/bottle):
  - Fields: timestamp, bottle/program ID, log file ref, primary category, confidence tier, top 1-3 signatures, remediation card IDs
  - UI: "Last crash diagnosis" panel in Program settings with "View details" and "Re-analyze"
  - "Clear diagnostics history" action for privacy

### Diagnostic report export
- ZIP export: `Whisky-Diagnostics-<bottle>-<program>-<YYYYMMDD-HHMMSS>.zip` containing:
  - `report.md` — human-readable summary (what happened, classification, confidence, suggested fixes, steps tried)
  - `crash.json` — categories, matched signatures, confidence scores
  - `env.json` — resolved environment with provenance, sensitive values redacted
  - `bottle-settings.plist` and `program-settings.plist` (or JSON equivalents)
  - `wine.log` (full) and/or `wine.tail.log` (last N lines)
  - `system.json` — macOS version, model, CPU/GPU, Whisky/Wine versions
- Also offer "Copy report" as single Markdown/plain-text block for pasting into GitHub issues
- Auto-track Whisky-initiated remediation actions as a timeline (last 10 per bottle/program) with timestamps and before/after values
- Export dialog checkbox: "Don't include remediation history" for privacy
- Redact by default: home paths (`/Users/<name>` -> `/Users/<redacted>`), env vars matching `*TOKEN*`, `*KEY*`, `*SECRET*`, `PASSWORD`, `AUTH`
- Export dialog checkbox: "Include sensitive details (recommended only when sharing privately)"
- Don't dump full registry by default; include only targeted keys relevant to detected issue, still redacted
- Entry points: Diagnostics view (primary), Log viewer toolbar, Program settings ("Diagnostics" section), Bottle settings, Help menu (asks user to pick bottle/program)

### Pattern coverage priorities
- First wave: DLL load failures + access violations/unhandled exceptions (high-frequency, high-signal, concrete remediation)
- Second wave: GPU/device-lost heuristics (noisier, backend-specific, better after classifier pipeline is solid)
- Full taxonomy (7 category groups):
  - **Core crash/fatal:** Access violation / unhandled exception (page fault, c0000005); Process termination / non-zero exit
  - **Graphics:** GPU timeout / device removed / hung (D3DMetal/DXVK device lost, Metal validation); Backend incompatibility (DX12 path issues, swapchain failures)
  - **Dependencies/loading:** DLL load failure (vcruntime, msvcp, d3dcompiler, api-ms-win-*); .NET/CLR issues (mscoree, mscorlib, fusion); DirectX redistributable missing (d3dx9, xinput, xaudio2)
  - **Prefix/filesystem:** Prefix corruption / missing user dirs; Path / permission errors
  - **Networking/launchers:** TLS/SSL / HTTP timeouts (WinHTTP, cert failures)
  - **Anti-cheat/unsupported:** EAC/BattlEye signatures → definitive "not supported on macOS" message with helpful next steps (offline mode, compatibility notes, export diagnostics), no fix buttons, high-confidence signature match only
  - **Other/Unknown:** Low-confidence suggestions (open logs, try different backend)
- Pattern storage: versioned JSON resource (`patterns.json`) with thin Swift loader
  - Schema per pattern: id (stable), category, severity, confidence, regex (or substring prefilter), tags, captureGroups (optional), remediationActionIds (optional)
  - Load/validate at startup (fail fast in debug, soft-fail in release)
  - Remediation action definitions separate from pattern definitions
  - Unit test fixtures with sample log lines for every rule (positive match test required per pattern)
- WINEDEBUG management: opt-in "Re-run with enhanced logging" per-program action, not a new default
  - Current default (`WINEDEBUG=fixme-all`) preserved for normal runs
  - Curated presets: Crash (`+seh,+tid,+pid,+timestamp`), DLL/load (`+loaddll,+module,+tid,+pid`), Verbose (advanced, labeled as noisy)
  - Record active WINEDEBUG preset in crash diagnosis + exported report

### Claude's Discretion
- Exact split view breakpoint threshold
- Loading/parsing performance optimization approach
- Internal data structures for the classifier pipeline
- Log viewer scrolling and virtualization implementation
- Exact gutter marker icon choices

</decisions>

<specifics>
## Specific Ideas

- Remediation cards should feel like actionable next steps, not a wall of text — "Try this" with clear buttons
- Anti-cheat detection should be definitive: only show "not supported" when signature match is high confidence
- Export format designed for GitHub issue filing — the "Copy report" feature should produce paste-ready Markdown
- Pattern test fixtures ensure every rule has at least one positive match — no untested patterns shipped
- Diagnosis persistence keeps only last 5 per program/bottle to avoid unbounded storage

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-stability-diagnostics*
*Context gathered: 2026-02-09*
