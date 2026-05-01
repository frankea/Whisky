---
phase: 06-audio-troubleshooting
plan: 03
subsystem: audio
tags: [audio-probes, troubleshooting-engine, state-machine, winmm, waveout, mingw]

# Dependency graph
requires:
  - phase: 06-audio-troubleshooting/01
    provides: AudioDeviceMonitor, AudioDeviceInfo, AudioFinding, AudioTransportType data models
  - phase: 06-audio-troubleshooting/02
    provides: WineAudioRegistry (readAudioDriver, readDirectSoundBuffer), BottleAudioConfig
  - phase: 05-stability-diagnostics
    provides: ConfidenceTier enum for audio finding confidence levels
provides:
  - AudioProbe protocol with 3 concrete implementations (CoreAudioDeviceProbe, WineRegistryAudioProbe, WineAudioTestProbe)
  - AudioProbeResult with ProbeStatus enum (ok/warning/error/skipped)
  - AudioSymptom enum with 5 symptom categories for wizard flow
  - TroubleshootingFixAttempt for recording applied fixes
  - AudioTroubleshootingEngine state machine with 7 WizardState cases
  - WhiskyAudioTest.exe C source and MinGW build script
affects: [06-04, 06-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [audio-probe-protocol, symptom-driven-wizard-state-machine, fix-recommendation-per-symptom]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Audio/AudioProbe.swift
    - WhiskyKit/Sources/WhiskyKit/Audio/AudioProbeResult.swift
    - WhiskyKit/Sources/WhiskyKit/Audio/AudioTroubleshootingEngine.swift
    - WhiskyKit/Sources/WhiskyKit/Audio/AudioTroubleshootingStep.swift
    - scripts/whisky_audio_test.c
    - scripts/build_audio_test.sh
  modified: []

key-decisions:
  - "WineRegistryAudioProbe uses @unchecked Sendable final class with @MainActor private method to bridge Sendable protocol requirement with MainActor registry access"
  - "WineAudioTestProbe uses Wine.runWineProcess (streaming API) to capture both stdout and stderr separately for JSON parsing and debug evidence"
  - "AudioTroubleshootingEngine fix order is hardcoded per symptom as static dictionary, designed for future JSON migration"
  - "MinGW not available on build machine; WhiskyAudioTest.exe not compiled (WineAudioTestProbe returns .skipped gracefully)"

patterns-established:
  - "AudioProbe protocol: never throws, always returns structured AudioProbeResult with evidence and findings"
  - "Wizard state machine: WizardState enum drives UI, public methods handle transitions, probe injection for testability"
  - "Fix recommendation: ordered action IDs per symptom with Set-based deduplication of attempted fixes"

# Metrics
duration: 5min
completed: 2026-02-10
---

# Phase 6 Plan 03: Audio Probes and Troubleshooting Engine Summary

**AudioProbe protocol with 3 implementations (CoreAudio device, Wine registry, Wine test exe), symptom-driven troubleshooting engine with 7-state wizard and bounded fix escalation**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-10T07:09:13Z
- **Completed:** 2026-02-10T07:13:45Z
- **Tasks:** 2
- **Files created:** 6

## Accomplishments
- AudioProbe protocol with 3 concrete implementations covering CoreAudio device state, Wine registry config, and Wine audio stack health via test exe
- AudioProbeResult with ProbeStatus enum and structured evidence/findings for each probe
- AudioTroubleshootingEngine state machine managing symptom selection through probe execution, fix offers, and bounded escalation (max 3 attempts)
- WhiskyAudioTest.exe C source using WinMM waveOut API for maximum Wine compatibility, with MinGW build script
- AudioSymptom enum with 5 categories and per-symptom fix recommendation order

## Task Commits

Each task was committed atomically:

1. **Task 1: Audio probe protocol, concrete probes, and WhiskyAudioTest.exe** - `0cdc67c7` (feat)
2. **Task 2: AudioTroubleshootingEngine state machine and wizard step models** - `8034da31` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Audio/AudioProbeResult.swift` - ProbeStatus enum (ok/warning/error/skipped) and AudioProbeResult struct with evidence and findings
- `WhiskyKit/Sources/WhiskyKit/Audio/AudioProbe.swift` - AudioProbe protocol and 3 implementations: CoreAudioDeviceProbe, WineRegistryAudioProbe, WineAudioTestProbe
- `WhiskyKit/Sources/WhiskyKit/Audio/AudioTroubleshootingStep.swift` - AudioSymptom enum (5 categories) and TroubleshootingFixAttempt record type
- `WhiskyKit/Sources/WhiskyKit/Audio/AudioTroubleshootingEngine.swift` - State machine with 7 WizardState cases, probe injection, fix tracking, bounded escalation
- `scripts/whisky_audio_test.c` - Minimal C source for WhiskyAudioTest.exe using WinMM waveOut API (100ms silence/440Hz tone)
- `scripts/build_audio_test.sh` - MinGW cross-compilation script targeting x86_64-w64-mingw32-gcc

## Decisions Made
- WineRegistryAudioProbe is a final class with @unchecked Sendable to satisfy the AudioProbe protocol's Sendable requirement while using @MainActor for Wine registry access
- WineAudioTestProbe uses the streaming Wine.runWineProcess API (not runWine) to capture stdout and stderr separately for JSON result parsing and debug evidence collection
- Fix recommendation order is hardcoded as a static [AudioSymptom: [String]] dictionary on the engine, following the locked decision to start hardcoded but design for JSON migration
- MinGW was not available on the build machine; WhiskyAudioTest.exe was not compiled -- the WineAudioTestProbe gracefully handles this by returning .skipped status

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

MinGW (x86_64-w64-mingw32-gcc) was not installed on the build machine, so WhiskyAudioTest.exe could not be compiled. This is expected per the plan: "If compilation fails (MinGW not available), the probes still work -- WineAudioTestProbe returns .skipped." The C source and build script are ready for compilation when MinGW is available.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- AudioProbe protocol and 3 implementations ready for use by audio diagnostics UI
- AudioTroubleshootingEngine ready to be connected to SwiftUI wizard views
- Fix action IDs defined and ready for the app layer to implement concrete fix application
- WhiskyAudioTest.exe source ready for compilation when MinGW is available (brew install mingw-w64)

## Self-Check: PASSED

All 6 created files verified. Both task commits (0cdc67c7, 8034da31) verified. Summary file exists.

---
*Phase: 06-audio-troubleshooting*
*Completed: 2026-02-10*
