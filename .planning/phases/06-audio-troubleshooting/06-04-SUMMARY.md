---
phase: 06-audio-troubleshooting
plan: 04
subsystem: ui
tags: [audio-ui, swiftui, config-section, audio-diagnostics, simple-advanced-toggle]

# Dependency graph
requires:
  - phase: 06-audio-troubleshooting/01
    provides: AudioDeviceMonitor, AudioDeviceInfo, AudioTransportType for device status display
  - phase: 06-audio-troubleshooting/02
    provides: BottleAudioConfig (audioDriver, latencyPreset, outputDeviceMode), Wine audio registry methods
  - phase: 06-audio-troubleshooting/03
    provides: AudioProbe protocol with 3 implementations, AudioProbeResult, AudioFinding, AudioTroubleshootingEngine
  - phase: 04-graphics-configuration/02
    provides: GraphicsConfigSection pattern (Section, Simple/Advanced toggle, @AppStorage, advanced badge)
  - phase: 05-stability-diagnostics
    provides: ConfidenceTier enum, RemediationCardView pattern for findings display
provides:
  - AudioStatusView showing OK/Degraded/Broken with device baseline info
  - AudioTestButtonsView with Test Wine Audio, Play Test Tone, and Refresh controls
  - AudioSettingsView with Simple/Advanced mode and registry write integration
  - AudioFindingsView with confidence badges and fix action buttons
  - AudioConfigSection composing all sub-views into a ConfigView section
  - ConfigView integration with Audio section between Graphics and Performance
affects: [06-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [audio-section-ui, simple-advanced-audio-toggle, probe-driven-findings-display]

key-files:
  created:
    - Whisky/Views/Audio/AudioStatusView.swift
    - Whisky/Views/Audio/AudioTestButtonsView.swift
    - Whisky/Views/Audio/AudioSettingsView.swift
    - Whisky/Views/Audio/AudioFindingsView.swift
    - Whisky/Views/Bottle/AudioConfigSection.swift
  modified:
    - Whisky/Views/Bottle/ConfigView.swift
    - Whisky.xcodeproj/project.pbxproj

key-decisions:
  - "@State instead of @StateObject for AudioDeviceMonitor (not ObservableObject; used as query-only device API)"
  - "AudioDeviceMonitor listener callback accepted with Sendable warning since dispatch is guaranteed main-queue"
  - "Findings view reuses ConfidenceTier color scheme from Phase 5 (green/yellow/gray badges)"

patterns-established:
  - "Audio section UI: status + test buttons + segmented toggle + settings + badge + findings + troubleshooting link"
  - "Probe-driven findings display: run probes -> collect AudioProbeResult -> aggregate AudioFinding -> render cards"

# Metrics
duration: 7min
completed: 2026-02-10
---

# Phase 6 Plan 04: Audio Section UI Summary

**Audio ConfigView section with status line, test buttons, Simple/Advanced settings pickers, findings cards, and troubleshooting wizard placeholder**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-10T07:16:34Z
- **Completed:** 2026-02-10T07:23:12Z
- **Tasks:** 2
- **Files created:** 5
- **Files modified:** 2

## Accomplishments
- AudioStatusView shows OK/Degraded/Broken status with device name, transport type badge, sample rate, channel count, and relative last-tested timestamp
- AudioTestButtonsView runs all 3 probes (CoreAudio device, Wine registry, Wine audio test) with tone confirmation flow and refresh button
- AudioSettingsView provides Simple mode (2 controls: Audio Driver, Latency) and Advanced mode (adds Output Device Mode, Reset Audio State) with async Wine registry writes
- AudioFindingsView displays findings with confidence dots/badges, expandable details, fix buttons, and collapsible technical details section
- AudioConfigSection composes all sub-views with @AppStorage-persisted Simple/Advanced toggle and advanced overrides badge
- ConfigView now has Audio section between Graphics and Performance, establishing audio as a first-class configuration subsystem

## Task Commits

Each task was committed atomically:

1. **Task 1: Audio status, test buttons, settings, and findings views** - `5ac8b6ac` (feat)
2. **Task 2: AudioConfigSection and ConfigView integration** - `402bd374` (feat)

## Files Created/Modified
- `Whisky/Views/Audio/AudioStatusView.swift` - Status line view with OK/Degraded/Broken indicator and device baseline info
- `Whisky/Views/Audio/AudioTestButtonsView.swift` - Test Wine Audio, Play Test Tone, and Refresh button row with probe execution
- `Whisky/Views/Audio/AudioSettingsView.swift` - Simple/Advanced audio settings with async registry write integration
- `Whisky/Views/Audio/AudioFindingsView.swift` - Findings list with confidence badges and fix cards matching Phase 5 pattern
- `Whisky/Views/Bottle/AudioConfigSection.swift` - Audio section composing status, tests, settings, findings, and wizard link
- `Whisky/Views/Bottle/ConfigView.swift` - Added AudioConfigSection between Graphics and Performance
- `Whisky.xcodeproj/project.pbxproj` - Added 5 new files to Whisky target with Audio group under Views

## Decisions Made
- Used `@State` instead of `@StateObject` for AudioDeviceMonitor since it is not an ObservableObject (it is a plain final class used for querying CoreAudio device state)
- AudioDeviceMonitor listener callback accepted with `@Sendable` warning since the callback is dispatched on DispatchQueue.main (guaranteed main-thread mutation)
- Findings view reuses the ConfidenceTier badge color scheme from Phase 5 diagnostics (green for high, yellow for medium, gray for low)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Changed @StateObject to @State for AudioDeviceMonitor**
- **Found during:** Task 2 (AudioConfigSection)
- **Issue:** AudioDeviceMonitor is `final class: @unchecked Sendable` but does not conform to `ObservableObject`, causing a compile error with `@StateObject`
- **Fix:** Changed to `@State private var monitor = AudioDeviceMonitor()` since the monitor is used as a query-only API (device info lookup + listener registration), not for SwiftUI state observation
- **Files modified:** Whisky/Views/Bottle/AudioConfigSection.swift
- **Verification:** Build compiles successfully
- **Committed in:** 402bd374 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minimal; type annotation change only, no behavioral difference.

## Issues Encountered

Pre-existing SwiftLint violations in WhiskyKit files (AudioProbe.swift file_length, AudioStatus.swift identifier_name for `ok` enum case) cause the SwiftLint build phase to fail. These are not related to this plan's changes. Swift compilation succeeds cleanly for all new files.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Audio section UI is complete and integrated into ConfigView
- Troubleshooting wizard sheet placeholder in AudioConfigSection ready for Plan 06-05 to implement the full wizard flow
- Fix action handler in AudioConfigSection covers check-audio-driver, set-coreaudio-driver, set-stable-latency, and reset-audio-state actions
- All probe-driven findings display infrastructure is operational

## Self-Check: PASSED

All 5 created files verified. Both task commits (5ac8b6ac, 402bd374) verified. Summary file exists.

---
*Phase: 06-audio-troubleshooting*
*Completed: 2026-02-10*
