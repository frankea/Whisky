---
phase: 04-graphics-configuration
plan: 01
subsystem: graphics
tags: [graphicsbackend, d3dmetal, dxvk, wined3d, codable, wine-environment]

# Dependency graph
requires:
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder, DLLOverrideResolver, ProgramOverrides structure
provides:
  - GraphicsBackend enum with 4 cases and Codable round-trip
  - BottleGraphicsConfig struct for per-bottle backend persistence
  - GraphicsBackendResolver for .recommended resolution
  - graphicsBackend proxy on BottleSettings with dxvk backward compatibility
  - Backend-conditional env var emission in populateBottleManagedLayer
  - Per-program graphicsBackend override in WineEnvironment
affects: [04-02, 04-03, 05-environment-inspector]

# Tech tracking
tech-stack:
  added: []
  patterns: [caseless-enum-resolver, backend-conditional-env-emission, migration-on-decode]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleGraphicsConfig.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/GraphicsBackendResolver.swift
  modified:
    - WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift
    - WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift
    - WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift

key-decisions:
  - "GraphicsBackend at module scope (not nested) following ClipboardPolicy pattern"
  - "GraphicsBackendResolver as caseless enum with static methods (GPUDetection pattern)"
  - "dxvk proxy derives from graphicsConfig.backend, not dxvkConfig.dxvk"
  - "Migration: old bottles without graphicsConfig key but dxvk=true get backend=.dxvk on decode"
  - "DXVK_ASYNC moved inside .dxvk case so it only emits when DXVK is active backend"
  - "graphicsBackend override in applyProgramOverrides placed before existing dxvk block"

patterns-established:
  - "Backend-conditional env emission: resolve .recommended first, then switch on concrete backend"
  - "Decode-time migration: check container.contains() to detect missing keys and migrate"

# Metrics
duration: 4min
completed: 2026-02-09
---

# Phase 4 Plan 1: Graphics Backend Data Model Summary

**GraphicsBackend enum with 4-case backend selection, auto-resolver defaulting to D3DMetal, and backend-conditional env var emission replacing flat dxvk Bool**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-09T19:22:04Z
- **Completed:** 2026-02-09T19:26:39Z
- **Tasks:** 2
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- GraphicsBackend enum (.recommended, .d3dMetal, .dxvk, .wined3d) with Codable, CaseIterable, Sendable
- GraphicsBackendResolver.resolve() returns .d3dMetal as the default recommended backend
- BottleSettings migration: old bottles with dxvk=true automatically get backend=.dxvk on decode
- populateBottleManagedLayer switches on resolved backend -- DXVK env vars only for .dxvk, WINED3DMETAL=0 for .wined3d
- ProgramOverrides.graphicsBackend allows per-program backend override with full DLL and env var composition

## Task Commits

Each task was committed atomically:

1. **Task 1: Create GraphicsBackend enum, BottleGraphicsConfig, GraphicsBackendResolver, and refactor BottleSettings** - `32125040` (feat)
2. **Task 2: Add graphicsBackend to ProgramOverrides and update WineEnvironment** - `0cabadeb` (feat)

## Files Created/Modified

- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleGraphicsConfig.swift` - GraphicsBackend enum and BottleGraphicsConfig struct with defensive decoding
- `WhiskyKit/Sources/WhiskyKit/Wine/GraphicsBackendResolver.swift` - Static resolver returning .d3dMetal as recommended default
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` - graphicsConfig stored property, graphicsBackend proxy, dxvk proxy derived from backend, populateBottleManagedLayer refactored
- `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift` - graphicsBackend optional field, isEmpty check, Codable decoding
- `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift` - graphicsBackend override in applyProgramOverrides, WINED3DMETAL in logLaunchSummary

## Decisions Made

- GraphicsBackend defined at module scope (not nested in a struct) following ClipboardPolicy pattern from Phase 1
- GraphicsBackendResolver uses caseless enum (static methods only) following GPUDetection pattern
- dxvk proxy now derives from graphicsConfig.backend instead of dxvkConfig.dxvk -- dxvkConfig.dxvk remains serialized for backward compat
- Migration uses container.contains(.graphicsConfig) to detect old bottles and auto-migrate dxvk=true to backend=.dxvk
- DXVK_ASYNC moved inside .dxvk switch case so it only emits when DXVK is the active backend
- graphicsBackend override placed before existing dxvk block in applyProgramOverrides for higher semantic authority

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- GraphicsBackend data model ready for UI integration in Plan 04-02 (Graphics Config section in BottleConfigView)
- Resolver architecture supports future heuristic sophistication without data model changes
- All existing tests pass, app builds cleanly

## Self-Check: PASSED

- All 2 created files exist on disk
- Both task commits (32125040, 0cabadeb) present in git log
- GraphicsBackend enum has `case recommended`
- BottleSettings references graphicsConfig (11 occurrences)
- ProgramOverrides references graphicsBackend (4 occurrences)
- WineEnvironment references overrides.graphicsBackend (1 occurrence)

---
*Phase: 04-graphics-configuration*
*Completed: 2026-02-09*
