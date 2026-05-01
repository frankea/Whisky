# Phase 9: UI/UX & Feature Requests - Context

**Gathered:** 2026-02-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Polish and feature enhancements that improve daily usability: streamline the GPTK update dialog, fix path handling for spaces, add App Nap toggle, bottle duplication, display resolution control (DPI + virtual desktop), console output persistence across runs, fix Build Version/Retina Mode display, and improve WhiskyCmd reliability and output. New capabilities (e.g., new troubleshooting flows, new configuration domains) belong in other phases.

</domain>

<decisions>
## Implementation Decisions

### Bottle duplication
- Full prefix clone: deep copy of entire Wine prefix directory (drive_c, registry, installed programs, game data/saves, winetricks components)
- Copy all bottle settings, program settings, custom overrides (graphics/input/DLL/env), launcher settings, controller settings
- After copy: assign new bottle name/UUID path, rewrite path-based references in metadata (pins/blocklist/program paths) to new bottle path, mark as independent bottle
- Do not carry over: running process state, temp files, transient runtime artifacts; optionally exclude old logs/diagnostic history for clean clone
- Naming: default to "<Original Name> Copy", incrementing to "Copy 2", "Copy 3" etc.; prefill suggested name in a confirmation dialog so user can edit before confirming
- Entry points: primary in bottle context menu ("Duplicate..."), secondary in bottle detail toolbar and Bottle menu bar item; all entry points open the same rename-confirm sheet
- Progress: non-blocking progress row/card tied to that bottle; determinate progress bar (x / y GB) if byte count available, otherwise indeterminate spinner with phase labels ("Copying files", "Updating metadata", "Finalizing")
- Disable conflicting actions on source/target during copy (delete/move/rename) but keep rest of UI usable
- On completion: toast with "Open Duplicate"; on failure: error toast with "Show Details" and cleanup partial clone

### Console persistence
- Per-run log files: each program launch creates a new log session with runId, start/end time, exit status
- Stream output live to UI and to disk; when process exits, keep transcript visible with "Exited (code X)" footer
- Run history in Program View: show "Last run" and "Previous runs" sections to reopen past console output
- Retain last 10 runs per program by default, with global size cap; older runs auto-pruned
- Content scope: default runs capture stdout/stderr only; diagnostic runs (Phase 5/6 enhanced logging presets) also capture WINEDEBUG
- UI separates channels (stdout, stderr, winedebug) with filter/toggle controls
- Do not auto-clear on exit; provide explicit "Clear Console" (current view only) and "Delete Old Logs" actions
- Include Copy, Export, and Open Logs Folder actions for sharing
- Access points: primary in Program View ("Console / Runs" section); secondary in Running/Process view ("Open console log") and bottle-level diagnostics with program + runId filter
- Exports include WINEDEBUG when captured, clearly labeled

### Resolution control
- Two-level model: bottle default (Retina Mode + DPI as baseline) with per-program override (inherit/override pattern)
- Virtual desktop mode as Advanced option (not in Simple mode): toggle "Use virtual desktop" with resolution picker
- Virtual desktop scope: bottle-level with optional per-program override
- Resolution presets: 1280x720, 1600x900, 1920x1080 (default), 2560x1440, 3840x2160, "Match Mac display" if reliably queryable, "Custom..." with validation bounds (min 640x480)
- All presets 16:9; custom handles ultrawide/odd cases
- Changes take effect on next launch; warn if processes are running
- Do not switch macOS display mode globally
- Retina Mode fix: configurable toggle (not read-only), tri-state UI (On / Off / Unknown for read failures), allow user to set On/Off even in Unknown state (write-through), re-read after write to confirm
- Build Version fix: display actual value instead of N/A

### WhiskyCmd improvements
- Default launch output: single deterministic line `Launched "<exe>" in bottle "<bottleName>".` with optional log path suffix; exit code 0 on success
- Keep `--command` behavior unchanged (print generated command only)
- Add `--follow` flag for opt-in real-time streaming of stdout/stderr to terminal
- Add `--tail-log` to follow Wine log file (since many apps launched via wine start don't emit useful direct stdout)
- Return proper non-zero exit code on launch failure; for followed runs, show final status line "Exited with code X"
- Path handling: treat executable path as single argument end-to-end, never split string; use `exec` + quoted args in scripts, `URL(fileURLWithPath:)` and argument arrays internally
- Generated commands: `whisky run "<bottle>" "<full path with spaces.exe>" -- <args...>`
- Add tests for paths with spaces, parentheses, apostrophes, and & to prevent regressions
- New `whisky shortcut <bottle> <exe-path>` subcommand for CLI shortcut creation
  - Options: `--name`, `--output` (default ~/Applications), `--overwrite`, `--icon`
  - Output: single success line with created .app path; non-zero on failure
  - Reuse existing shortcut creation logic from ProgramShortcut.swift for UI/CLI consistency

### Claude's Discretion
- GPTK update dialog simplification (clear requirement: single confirmation step)
- App Nap toggle implementation details (simple per-bottle toggle)
- Progress bar implementation for bottle duplication (byte counting vs file counting)
- Exact log file format and storage location for console persistence
- Internal architecture for virtual desktop registry keys

</decisions>

<specifics>
## Specific Ideas

- Bottle duplication should feel like Finder's "Duplicate" — familiar macOS pattern with inline rename
- Console persistence: "Exited (code X)" footer pattern for terminated runs
- WhiskyCmd output should not break scripts — minimal by default, opt-in verbosity
- Virtual desktop label: "Runs apps in a fixed Wine desktop window; useful for fullscreen/capture/focus issues"
- Resolution presets kept to 16:9 initially to avoid clutter
- Shortcut creation logic shared between app UI and CLI for behavioral consistency

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-ui-ux-feature-requests*
*Context gathered: 2026-02-11*
