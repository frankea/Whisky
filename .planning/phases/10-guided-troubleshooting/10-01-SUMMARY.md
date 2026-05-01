---
phase: 10-guided-troubleshooting
plan: 01
subsystem: troubleshooting
tags: [codable, swift-concurrency, sendable, protocol, spm-resources, json-schema]

# Dependency graph
requires:
  - phase: 05-stability-diagnostics
    provides: ConfidenceTier enum for check result confidence scoring
provides:
  - FlowDefinition and FlowStepNode Codable types for JSON flow decoding
  - FlowIndex and FlowCategoryEntry for category metadata
  - SymptomCategory enum with 8+1 categories
  - CheckResult with normalized CheckOutcome for flow branching
  - TroubleshootingCheck protocol for check implementations
  - CheckContext with @MainActor factory for safe value capture
  - FixAttempt with FixResult lifecycle enum
  - PreflightData snapshot struct
  - EntryContext enum with context-aware initial phase
  - TroubleshootingSession with full wizard state persistence
  - SPM resource path for Troubleshooting/Resources/
affects: [10-02, 10-03, 10-04, 10-05, 10-06, 10-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Defensive Codable decoding with decodeIfPresent for all optional flow node fields"
    - "CheckContext @MainActor factory pattern for safe Bottle/Program value capture"
    - "SessionPhase initializer from FlowPhase for cross-type phase mapping"
    - "SymptomCategory computed properties for flow file name, display title, and SF symbol"

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowDefinition.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowIndex.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/SymptomCategory.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckResult.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingCheck.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckContext.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/FixAttempt.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/PreflightData.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/EntryContext.swift
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingSession.swift
  modified:
    - WhiskyKit/Package.swift

key-decisions:
  - "SymptomCategory includes 9th 'other' case as fallback per locked decision guidance"
  - "CheckContext stores URLs and names instead of @MainActor Bottle/Program references for Sendable compliance"
  - "SessionPhase includes 'escalation' beyond the 5 core FlowPhases for post-flow state"
  - "EntryContext uses URL-based associated values (not Bottle/Program references) for Sendable conformance"

patterns-established:
  - "Defensive Codable: all optional FlowStepNode fields use decodeIfPresent for forward-compatible JSON schema evolution"
  - "CheckContext factory: @MainActor static create() captures Bottle/Program values safely for cross-actor use"
  - "Computed flow file mapping: SymptomCategory.flowFileName returns the JSON file name for each category"

# Metrics
duration: 4min
completed: 2026-02-12
---

# Phase 10 Plan 01: Core Troubleshooting Data Models Summary

**10 Codable model types and protocols for the JSON-driven troubleshooting flow engine, with FlowDefinition graph schema, 9-category SymptomCategory, normalized CheckResult/CheckOutcome, TroubleshootingCheck protocol, and full TroubleshootingSession state**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-12T03:16:14Z
- **Completed:** 2026-02-12T03:20:09Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- Established the complete type foundation for the Phase 10 troubleshooting engine: FlowDefinition, FlowStepNode, FlowIndex, SymptomCategory, CheckResult, CheckOutcome, TroubleshootingCheck protocol, CheckContext, FixAttempt, PreflightData, EntryContext, and TroubleshootingSession
- All types compile under Swift 6 strict concurrency with Sendable and Codable conformance
- Package.swift updated with Troubleshooting/Resources/ SPM resource path for future flow JSON files

## Task Commits

Each task was committed atomically:

1. **Task 1: Flow definition models, symptom category, and check protocol** - `a683b182` (feat)
2. **Task 2: Session model, fix attempt, preflight data, entry context, and Package.swift update** - `5b333058` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowDefinition.swift` - FlowDefinition, FlowStepNode, NodeType, FlowPhase, FixPreviewData Codable types with defensive decoding
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FlowIndex.swift` - FlowIndex and FlowCategoryEntry for category metadata with FlowDepth enum
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/SymptomCategory.swift` - 9-case enum (8 categories + other) with flowFileName, displayTitle, sfSymbol computed properties
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckResult.swift` - Normalized check result with CheckOutcome enum matching JSON branching keys
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingCheck.swift` - Protocol with checkId and async run method returning CheckResult
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/CheckContext.swift` - Sendable context with @MainActor factory for safe Bottle/Program value capture
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/FixAttempt.swift` - Fix attempt record with FixResult lifecycle enum (pending/applied/verified/failed/undone)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/PreflightData.swift` - Snapshot struct for eager preflight collection (bottle, program, launcher, processes, audio, graphics)
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/EntryContext.swift` - 4-case entry point enum with context-aware initial phase selection
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/TroubleshootingSession.swift` - Full session state with CompletedStep, BranchDecision, SessionPhase, SessionOutcome nested types
- `WhiskyKit/Package.swift` - Added .process("Troubleshooting/Resources/") to SPM resources array

## Decisions Made
- SymptomCategory includes a 9th `other` case as fallback, per locked decision guidance ("Other as fallback only if needed")
- CheckContext stores URLs and names instead of @MainActor Bottle/Program references, enabling full Sendable compliance without @unchecked
- SessionPhase has 6 cases (adding `escalation` beyond the 5 core FlowPhases) to represent post-flow escalation state
- EntryContext uses URL-based associated values for Sendable conformance rather than referencing @MainActor types

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All core types ready for Plan 02 (FlowLoader, CheckRegistry) and Plan 03 (PreflightCollector implementation)
- FlowDefinition types ready for JSON flow authoring in Plan 04
- TroubleshootingSession ready for Plan 05 (SessionStore persistence)
- TroubleshootingCheck protocol ready for Plan 02 (check implementations)
- EntryContext ready for Plan 06 (entry point integration)

## Self-Check: PASSED

All 10 Swift files verified present. Both commits (a683b182, 5b333058) verified in git log. Package.swift contains Troubleshooting/Resources/ resource declaration. swift build --package-path WhiskyKit succeeds.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
