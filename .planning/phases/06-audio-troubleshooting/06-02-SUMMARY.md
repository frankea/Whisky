---
phase: 06-audio-troubleshooting
plan: 02
subsystem: audio
tags: [wine-registry, audio-config, codable, bottle-settings, directsound]

# Dependency graph
requires:
  - phase: 04-graphics-configuration
    provides: BottleGraphicsConfig pattern (module-scope enums, defensive decoding, proxy properties)
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder cascade and layer populator pattern
provides:
  - BottleAudioConfig model with AudioDriverMode, AudioLatencyPreset, OutputDeviceMode enums
  - BottleSettings audio proxy properties (audioDriver, audioLatencyPreset, outputDeviceMode, pinnedDeviceName)
  - WineAudioRegistry typed read/write helpers for Wine audio registry keys
  - Promoted addRegistryKey/queryRegistryKey to public access for module-wide use
  - populateAudioLayer EnvironmentBuilder integration point
affects: [06-audio-troubleshooting, audio-ui, audio-diagnostics]

# Tech tracking
tech-stack:
  added: []
  patterns: [registry-backed-config, audio-config-group]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleAudioConfig.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/WineAudioRegistry.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/WineRegistry.swift

key-decisions:
  - "Audio config follows BottleGraphicsConfig pattern exactly: module-scope enums, defensive decoding, private stored property with proxy properties"
  - "Audio settings are registry-backed (not env vars): populateAudioLayer is a placeholder for future audio env var support"
  - "RegistryType promoted to public and addRegistryKey/queryRegistryKey promoted from private to public for module-wide access"

patterns-established:
  - "Registry-backed config: audio settings use Wine registry keys rather than environment variables, with WineAudioRegistry as the typed access layer"
  - "resetAudioState pattern: clear cached device state (MMDevices subtree) + kill wineserver for fresh enumeration"

# Metrics
duration: 5min
completed: 2026-02-10
---

# Phase 6 Plan 02: Audio Configuration Model Summary

**BottleAudioConfig with 3 enums (driver/latency/device mode), 4 proxy properties on BottleSettings, and WineAudioRegistry for typed Wine audio registry access**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-10T07:00:45Z
- **Completed:** 2026-02-10T07:06:02Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created BottleAudioConfig with AudioDriverMode, AudioLatencyPreset, and OutputDeviceMode enums matching the BottleGraphicsConfig pattern
- Integrated audio settings into BottleSettings with defensive decoding (old bottles decode gracefully)
- Created WineAudioRegistry extension with typed read/write methods for Wine audio driver and DirectSound keys
- Added resetAudioState to clear cached device mappings and force wineserver restart

## Task Commits

Each task was committed atomically:

1. **Task 1: BottleAudioConfig model and BottleSettings integration** - `bf0f47d5` (feat)
2. **Task 2: Wine audio registry helpers and EnvironmentBuilder audio layer** - `fbab0f85` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleAudioConfig.swift` - Audio config model with AudioDriverMode, AudioLatencyPreset, OutputDeviceMode enums and defensive decoding
- `WhiskyKit/Sources/WhiskyKit/Wine/WineAudioRegistry.swift` - Wine registry audio key read/write helpers and resetAudioState
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - Added audioConfig stored property, 4 proxy properties, and populateAudioLayer method
- `WhiskyKit/Sources/WhiskyKit/Wine/WineRegistry.swift` - Promoted RegistryType to public, addRegistryKey/queryRegistryKey from private to public

## Decisions Made
- Audio config follows BottleGraphicsConfig pattern exactly: module-scope enums with Codable/CaseIterable/Equatable/Sendable conformance, defensive decoding with decodeIfPresent
- Audio settings are registry-backed, not environment-variable-backed: populateAudioLayer exists as a placeholder for the EnvironmentBuilder cascade integration point
- RegistryType and addRegistryKey/queryRegistryKey promoted to public access so WineAudioRegistry (same module) can call them
- resetAudioState deletes the entire MMDevices registry subtree as a safe fallback, then kills wineserver for fresh device enumeration

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- BottleAudioConfig model ready for UI integration in audio configuration section
- WineAudioRegistry ready for use by audio diagnostics probes and troubleshooting wizard
- populateAudioLayer placeholder ready for future audio-related environment variables
- All 852 existing tests pass with no regressions

## Self-Check: PASSED

All created files verified present. All commit hashes verified in git log.

---
*Phase: 06-audio-troubleshooting*
*Completed: 2026-02-10*
