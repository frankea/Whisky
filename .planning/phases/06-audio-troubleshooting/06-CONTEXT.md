# Phase 6: Audio Troubleshooting - Context

**Gathered:** 2026-02-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Diagnostics-first audio remediation for macOS Wine audio problems. Users can view CoreAudio device status, run a guided troubleshooting flow for common issues (crackling, missing sound, stuttering, wrong device), and configure up to 3-4 effective audio settings per bottle. Does NOT include per-program audio overrides, automatic system audio changes, or microphone/input handling beyond basic detection.

</domain>

<decisions>
## Implementation Decisions

### Diagnostics panel location and structure
- First-class "Audio" section in ConfigView (same level as Graphics/Performance)
- Deep-links from program settings ("Troubleshooting: Audio...") and any crash/remediation card flagging audio issues
- Layout order: Status line → Test buttons → Settings (Simple/Advanced)
- Status line shows: OK / Degraded / Broken with primary detected issue and confidence tier

### Diagnostics detail level
- Baseline (always visible): default output device name, transport type (Built-in/USB/Bluetooth/AirPlay), current sample rate and channel count, "Last device change" timestamp
- Advanced (collapsible): full device list with defaults, per-device supported sample rates, Wine audio driver status, dependency checks (XAudio2/OpenAL presence)
- No raw low-level properties unless behind "Export diagnostics"

### Diagnostics refresh behavior
- Hybrid: auto-refresh on CoreAudio device-route change notifications + slow timer (5-10s) for "audio engine alive" checks while panel is visible
- Manual Refresh button for deterministic user control
- No continuous tight polling

### Issue presentation pattern
- Matches Phase 5 crash remediation pattern, scoped to audio
- Status line at top (OK/Degraded/Broken)
- Findings list (1-5 items max) with detection description, confidence (High/Medium/Low), and "Details" disclosure for evidence
- Fix cards with direct actions (toggle setting, sample rate guidance, open Winetricks, restart bottle)
- "Technical details" collapsed by default

### Troubleshooting guide: symptom-driven wizard
- Flow: Pick Symptom → Snapshot → Quick Tests → Wine Stack Checks → Dependency Checks → Targeted Fix Paths → Escalation
- Symptom categories: No sound, Crackling/pops, Audio stutter/desync, Wrong output device, Sound in menus only
- Every step ends with "Did this fix it?" — flow stops as soon as audio is OK
- Bounded to ~3 fix paths before escalation (no infinite loops)
- Record each attempted fix (action id, timestamp, before/after values) to avoid repeating

### Troubleshooting data format
- Data-driven JSON for guide structure (steps, branching, copy, probe IDs, remediation action IDs)
- Probe execution in Swift (strongly typed, testable)
- If time-constrained: start hardcoded but design for JSON migration without changing probe/result model

### Audio test probe: two-stage
- Stage 1 (automatic): bundled WhiskyAudioTest.exe initializes WASAPI/mmdevapi (fallback to WinMM/waveOut), writes short buffer, exits with structured JSON result line
- Stage 2 (optional): "Play test tone" button runs same helper with --beep flag, UI asks "Did you hear the tone?" Yes/No
- Probe runs with curated WINEDEBUG preset (eg +mmdevapi,+dsound,+winmm), captures stdout/stderr
- Ship helper with Whisky — no dependency on PowerShell/.NET

### Escalation after failed fixes
- Re-run probes to update status based on what actually changed
- Branch to next-most-likely cause using updated evidence
- Offer enhanced audio logging after 1-2 failed fix paths (not immediately)
- Final step: "Export Diagnostics" or "Open advanced audio settings"

### Audio settings: 3 settings + 1 action
1. **Audio Driver / Enable Audio**: Picker — Auto (Recommended) / CoreAudio / Disabled. Backed by Wine registry `HKCU\Software\Wine\Drivers`
2. **Audio Buffer / Latency Preset**: Picker — Default / Low latency / Stable (larger buffer). Backed by `HKCU\Software\Wine\DirectSound\HelBuflen`
3. **Output Device Mode** (Advanced): Follow macOS default (Recommended) vs Pin to device
4. **Reset Audio State** (action button): Clears Wine stored device GUID/UID mappings + restarts bottle

### Settings tier: Simple/Advanced
- Simple: Audio driver (Auto/Disabled) + Latency preset (Default/Stable) + Test Wine Audio button — 2 controls max
- Advanced: full driver picker, buffer values, device pinning, Reset Audio State action
- Persist Simple/Advanced preference globally (same as graphics)
- Badge in Simple mode if advanced audio overrides are active

### Audio settings scope: bottle-level only
- No per-program audio overrides — Wine audio knobs are prefix-wide/registry-backed
- Per-program audio DLL overrides and winetricks tagging already fit Phase 2 override model
- Separate bottles as the supported workaround for radically different audio needs

### Test button placement
- Top of Audio section, before settings controls
- Row 1: Status (OK/Degraded/Broken) + "Last tested" timestamp
- Row 2: Test Wine Audio (primary) + Play Test Tone (secondary) + Refresh
- Then settings, so users can test → change → re-test without scrolling

### Bluetooth/device disconnect alerts
- Whisky focused: non-blocking `.info`/`.error` toast with guidance ("Switch macOS output device and retest")
- Whisky backgrounded: macOS notification (best-effort, fallback to logging)
- Update Audio section status to Degraded with device name and timestamp
- Rate-limit/debounce: one alert per device per few minutes
- Quiet "Reconnected" toast when device returns

### Sample rate mismatch detection
- Default: reactive only (during troubleshooting flow, audio panel open, or "Test Wine audio")
- Proactive exception: if active route switches to Bluetooth Hands-Free / very low sample rate while bottle has running processes, show one non-blocking warning linking to Audio panel
- Flag "unusual" rates (8/16/22.05 kHz) as likely cause during troubleshooting

### Device change history
- Bounded ring buffer per session, persist last ~20 events
- Track: timestamp, event type (default output changed, disconnected, reconnected, sample rate changed), device display name, transport type
- No unique hardware identifiers by default — name + transport only
- Include in diagnostics export (redacted if needed)

### Device change remediation
- Inform and offer guided actions, never automatic fixes
- One-click "Restart bottle audio" (stop/restart wineserver) with confirmation if running apps
- Offer "Open Audio Diagnostics" and "Test Wine audio" immediately
- For pinned device users: "Switch back to pinned device" button that instructs user or opens macOS Sound settings — no force-changing system audio

### Claude's Discretion
- Exact probe implementation details and error handling
- CoreAudio API usage patterns (AudioObjectPropertyAddress, listener registration)
- WhiskyAudioTest.exe implementation language and build approach
- Ring buffer data structure choice
- Toast/notification timing and animation details
- JSON schema design for troubleshooting guide data

</decisions>

<specifics>
## Specific Ideas

- Audio section layout mirrors Phase 5's diagnostics pattern: Status → Findings → Fix Cards → Technical Details
- "Did this fix it?" at every troubleshooting step to exit early when resolved
- WhiskyAudioTest.exe ships with Whisky and works in clean prefixes with no external dependencies
- Simple mode should be genuinely simple: 2 controls max, not a compressed version of Advanced
- Device change alerts should never fight the user's system audio choices
- "Sound in menus only" as a symptom category captures a very common game-specific audio issue

</specifics>

<deferred>
## Deferred Ideas

- Microphone/voice chat support (needs entitlements/permissions work — potential future phase)
- Per-program audio settings that mutate the prefix around launch
- "Launch with audio disabled" as a one-off per-program action
- Automatic system audio device switching

</deferred>

---

*Phase: 06-audio-troubleshooting*
*Context gathered: 2026-02-10*
