# Phase 10: Guided Troubleshooting - Context

**Gathered:** 2026-02-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can navigate interactive, data-driven troubleshooting flows that diagnose and resolve common issues by integrating diagnostics, compatibility data, and configuration from all previous phases. The engine loads symptom/solution decision trees from bundled JSON. Flows cover graphics, audio, launcher, and additional symptom categories at tiered depths.

</domain>

<decisions>
## Implementation Decisions

### Flow Navigation & Presentation
- Single-page wizard with step cards (not multi-screen navigation)
- Progress rail with 5 stable core phases: Symptom → Checks → Fix → Verify → Export
- Rail is state-based: branch-specific steps appear under the active phase
- Completed steps lock as completed; superseded future steps shown with subtle "superseded" style (not deleted)
- Inline "Why path changed" explanation when branching alters the path
- Step numbering relative to current path (e.g., "Step 3 of 6"), no confusing renumbering of past steps
- Back/forward navigation and "skip for now" supported, state persisted per run
- Deep links (to Config/Logs) open as sub-sheets and return to the same wizard step

### Session Persistence
- Resumable draft sessions: auto-save state (symptom, probes run, findings, fixes attempted, branch decisions) per bottle/program
- Paused sessions show "Resume troubleshooting" in Program/Bottle Diagnostics
- On resume: restore exact step, re-run lightweight probes for staleness ("Since you left" check)
- Explicit actions: Resume, Start over, Discard session
- Bounded storage: last 1 active + recent completed history; stale paused sessions expire after 14 days

### Fix Application
- Explicit gated "Apply and verify" per fix card — no silent auto-apply
- Each fix step shows diff-style preview of what will change (scoped to bottle/program)
- Require explicit "Apply fix" click; high-impact changes (winetricks/install/restart/kill) get additional confirmation
- Apply atomically where possible: settings/env changes are immediate writes
- Record attempt entry per fix: fix ID, timestamp, before/after values, result
- Immediately run verification probe after each fix: "Did this fix it?"
- If no → branch to next fix; if yes → mark resolved, offer finish/export
- Support Undo for reversible settings changes; clearly label non-reversible actions

### Automated Checks
- Thin orchestration layer over existing Phase 5/6 diagnostic primitives — not a parallel diagnostics system
- Reuse: CrashClassifier, AudioProbes, GPUDetection, remediation catalog, environment/provenance snapshots, export pipeline
- Check IDs referenced in decision tree JSON with parameters; implementations live in code returning normalized result enum + evidence payload
- Lazy execution with cheap eager preflight: startup collects bottle/program identity, launcher type, running state, recent log pointer, audio device route
- Heavier checks (classification, dependency probes, audio tests, process scans) run lazily per step
- Re-run checks after each applied fix for verification
- Pre-satisfied checks: mark as "Already configured" with one-line note, auto-advance to next step, record outcome in session timeline
- Consistent language: same categories/severity/confidence as diagnostics views everywhere

### Check Binding in JSON
- Each step node references a stable `checkId` + `params` object
- Branching keyed by normalized outcomes: `pass`, `fail`, `already_configured`, `unknown`, `error`
- Optional `evidenceMap` for surfacing specific finding fields in UI
- Check IDs are versioned/stable so flows and analytics don't break when internals change

### Entry Points & Discovery
- Primary: "Troubleshoot…" action in Program view (gives full program + bottle + recent runs/logs context)
- Secondary deep links:
  - Launch failure toast/banner → "Troubleshoot" (starts at Findings with prefilled evidence)
  - Bottle Config Diagnostics section → "Start Guided Troubleshooting" (starts at Checks summary)
  - Global Help menu → opens target picker (bottle/program) then starts wizard from Symptom selection
- Context-aware start: entry context sets initial node and preloaded data (one wizard system, multiple entry depths)
- Proactive suggestions on strong failure signals only: launch failure, high-confidence crash match, repeated stall/timeout
- Show toast/banner (not auto-open); rate-limited per bottle/program/session
- Low-confidence heuristics: passive button in Program/Bottle Diagnostics only

### Troubleshooting History
- Completed sessions stored per bottle/program: timestamp, symptom, primary findings, fixes attempted, final outcome
- Viewable from Program/Bottle Diagnostics as "Troubleshooting History"
- Bounded: last 20 sessions or 30 days; sensitive payloads redacted by default
- "Reopen as template" (reuse flow with fresh checks) and "Export session report" available

### Symptom Categories
- 8 user-language categories:
  1. Won't launch / crashes immediately
  2. Launcher issues (Steam/EA/Epic/Rockstar)
  3. Graphics problems (black screen, flicker, low FPS)
  4. Audio problems (no sound, crackle, wrong device)
  5. Controller/input problems (not detected, wrong mapping)
  6. Install/dependency problems (.NET, VC++, DirectX, Winetricks)
  7. Network/download problems (timeouts, Steam stalls)
  8. Performance/stability over time (stutter, hangs after minutes)
- "Other" as fallback only if needed

### Flow Depth (Tiered)
- All categories get a shallow core flow (triage → 1-2 safe fixes → verify → export), ~4-5 steps max
- Deep branches for high-frequency/high-confidence: launch/crash, launcher/network, graphics, dependencies — up to 8-12 steps
- Lighter flows for lower-signal categories: controller, long-run performance/stability — escalate earlier to diagnostics/export
- Stop early on success; cap retries (3 failed fix loops) then move to advanced diagnostics/report

### Escalation Path
- Mark flow outcome as "Unresolved" with summary of everything tried
- Offer Enhanced Diagnostics Re-run (opt-in debug preset like targeted WINEDEBUG) and reclassify once
- If still unresolved: generate Export Diagnostics bundle with findings, confidence, attempted fixes/timestamps, env provenance, relevant logs
- One-click "Open Support Issue Draft" with exported bundle path and summary
- Keep session in history as "Unresolved"; allow "Retry from step X" later

### Decision Tree File Structure
- Split per symptom category plus shared index:
  - `index.json`: category metadata, entry nodes, versioning
  - `flows/<category>.json`: one flow file per symptom category
  - `fragments/`: shared subflows (dependency install, export/escalation)
- Benefits: easier review, smaller diffs, safer iteration, cleaner ownership per domain

### Claude's Discretion
- Exact step card visual design and spacing
- Progress rail implementation details (vertical vs horizontal)
- Preflight probe set composition
- Session storage format and serialization
- Toast/banner visual treatment for proactive suggestions
- Specific normalized result enum cases beyond the 5 specified

</decisions>

<specifics>
## Specific Ideas

- "One diagnostics engine, multiple UX surfaces" — diagnostics panel, alerts, and guided wizard all share the same probe/finding/remediation infrastructure
- Wizard should feel like stepping through a checklist with a knowledgeable friend, not like filling out a form
- "Since you left" check on session resume — re-run lightweight probes that may have changed
- "Why path changed" inline explanation prevents user confusion during branching
- Check JSON shape example provided:
  ```json
  {
    "id": "check_graphics_backend",
    "type": "check",
    "checkId": "graphics.backend_is",
    "params": { "expected": "dxvk", "scope": "program_or_bottle" },
    "on": {
      "pass": "next_step",
      "already_configured": "next_step",
      "fail": "fix_enable_dxvk",
      "unknown": "manual_review",
      "error": "collect_diagnostics"
    }
  }
  ```

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-guided-troubleshooting*
*Context gathered: 2026-02-11*
