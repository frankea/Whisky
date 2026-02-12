---
phase: 10-guided-troubleshooting
plan: 03
subsystem: troubleshooting
tags: [json-loader, graph-validation, state-machine, observable-object, spm-resources, cycle-protection]

# Dependency graph
requires:
  - phase: 10-guided-troubleshooting
    provides: FlowDefinition, FlowStepNode, FlowIndex, SymptomCategory, CheckResult, TroubleshootingCheck, CheckContext, FixAttempt, PreflightData, TroubleshootingSession types
  - phase: 05-stability-diagnostics
    provides: ConfidenceTier enum for check result confidence scoring
  - phase: 06-audio-troubleshooting
    provides: AudioDeviceMonitor for preflight audio device detection
provides:
  - FlowLoader for JSON flow loading from SPM bundle resources
  - FlowValidator for structural flow graph validation (dangling refs, cycles, unreachable nodes)
  - CheckRegistry for mapping checkId strings to TroubleshootingCheck implementations
  - PreflightCollector for cheap eager preflight data collection
  - TroubleshootingFlowEngine JSON-driven state machine with full navigation API
  - TroubleshootingSessionStoring protocol for session persistence
affects: [10-04, 10-05, 10-06, 10-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TroubleshootingFlowEngine: @MainActor ObservableObject with no SwiftUI imports, using Combine for @Published"
    - "CheckRegistry: @unchecked Sendable with NSLock.withLock for thread-safe check lookup"
    - "FlowValidator: BFS reachability and iterative DFS for max automated depth detection"
    - "PreflightCollector: best-effort data collection with nil fallbacks for cross-target types"

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowLoader.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowValidator.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckRegistry.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/PreflightCollector.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingFlowEngine.swift
  modified: []

key-decisions:
  - "FlowLoader uses hardcoded fragment names rather than directory enumeration due to SPM .process() flattening"
  - "CheckRegistry init is empty; registerDefaults is a placeholder for Plan 04 check implementations"
  - "PreflightCollector sets launcherType to nil since LauncherDetection is in the app target, not WhiskyKit"
  - "TroubleshootingFlowEngine uses Combine import (not SwiftUI) for @Published property wrappers"
  - "PreflightCollector uses RunLogStore for recent log/exit code lookup rather than scanning arbitrary directories"

patterns-established:
  - "Flow engine import pattern: Combine (not SwiftUI) for @MainActor ObservableObject in WhiskyKit"
  - "Session store protocol: TroubleshootingSessionStoring defined in engine file, concrete implementation deferred to Plan 05"
  - "Cycle protection: automatedStepCount counter reset on user-interaction nodes (fix/verify), escalate at 50"

# Metrics
duration: 22min
completed: 2026-02-12
---

# Phase 10 Plan 03: Core Flow Engine Infrastructure Summary

**JSON-driven TroubleshootingFlowEngine state machine with FlowLoader, FlowValidator, CheckRegistry, PreflightCollector, and TroubleshootingSessionStoring protocol for data-driven troubleshooting flow traversal**

## Performance

- **Duration:** 22 min
- **Started:** 2026-02-12T03:31:34Z
- **Completed:** 2026-02-12T03:53:46Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Built the complete engine infrastructure: FlowLoader loads index, flows, and fragments from SPM bundle; FlowValidator detects dangling references, missing fragments, cycles, and unreachable nodes; CheckRegistry maps checkId strings to TroubleshootingCheck implementations with thread-safe access; PreflightCollector gathers cheap bottle/program state for session startup
- TroubleshootingFlowEngine generalizes AudioTroubleshootingEngine into a JSON-driven state machine with full navigation (selectCategory, navigateToNode, applyFix, confirmFixApplied, userReportsFixed, userReportsNotFixed, skipStep, goBack, escalate, startOver, undoLastFix)
- All 5 files compile under Swift 6 with zero new warnings; engine has no SwiftUI imports

## Task Commits

Each task was committed atomically:

1. **Task 1: FlowLoader, FlowValidator, CheckRegistry, and PreflightCollector** - `7255fc44` (feat)
2. **Task 2: TroubleshootingFlowEngine state machine** - `3fdc3f75` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowLoader.swift` - Caseless enum loading index.json, per-category flows, and fragments from Bundle.module
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowValidator.swift` - Caseless enum validating flow graphs: entry node existence, dangling on-map targets, missing fragment refs, unreachable nodes, and automated step depth limits
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckRegistry.swift` - Thread-safe registry mapping checkId strings to TroubleshootingCheck implementations, with error result for unknown IDs
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/PreflightCollector.swift` - Caseless enum collecting cheap bottle/program state: wineserver running, process count, recent log URL, exit code, audio device, graphics backend
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingFlowEngine.swift` - @MainActor ObservableObject state machine with TroubleshootingSessionStoring protocol, cycle protection, and complete navigation API

## Decisions Made
- FlowLoader uses hardcoded fragment names ("dependency-install", "export-escalation") rather than runtime directory enumeration because SPM `.process()` flattens directories and there is no reliable way to discover resource names programmatically
- CheckRegistry starts empty with a placeholder `registerDefaults()` method; Plan 04 will populate it with concrete check implementations
- PreflightCollector cannot access LauncherDetection (lives in app target Whisky/Utils/), so launcherType is set to nil and can be populated by the app layer if needed
- TroubleshootingFlowEngine imports Combine (not SwiftUI) for @Published support, keeping it in WhiskyKit without UI framework dependency
- PreflightCollector uses RunLogStore to find the most recent log file and exit code, providing accurate per-program data

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- FlowLoader, FlowValidator, CheckRegistry, and PreflightCollector ready for check implementations (Plan 04)
- TroubleshootingFlowEngine ready for session persistence connection (Plan 05)
- TroubleshootingSessionStoring protocol ready for concrete store implementation (Plan 05)
- Engine ready for wizard UI integration (Plan 06)
- CheckRegistry.registerDefaults() placeholder ready for Plan 04 to fill in

## Self-Check: PASSED

All 5 Swift files verified present. Both commits (7255fc44, 3fdc3f75) verified in git log. swift build --package-path WhiskyKit succeeds. TroubleshootingFlowEngine has no SwiftUI imports. FlowLoader uses Bundle.module for resource loading. CheckRegistry.run returns error result for unknown checkIds. FlowValidator detects dangling node references.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
