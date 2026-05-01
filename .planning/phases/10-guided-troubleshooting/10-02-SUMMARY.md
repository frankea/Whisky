---
phase: 10-guided-troubleshooting
plan: 02
subsystem: troubleshooting
tags: [json, decision-tree, troubleshooting-flows, wine, diagnostics]

# Dependency graph
requires:
  - phase: 05-stability-diagnostics
    provides: CrashClassifier patterns and remediation action IDs referenced by flow check nodes
  - phase: 06-audio-troubleshooting
    provides: Audio probe check IDs and driver/device check patterns
  - phase: 07-game-compatibility-database
    provides: Game config available check pattern
  - phase: 08-remaining-platform-issues
    provides: Launcher fix categories, controller compatibility, dependency management patterns
provides:
  - 11 JSON flow definition files covering all 8 symptom categories plus 2 shared fragments
  - Stable checkId references for Plan 04 check implementations
  - Flow node schema with on-map branching, evidenceMap, fixPreview, fragmentRef
  - Export-escalation and dependency-install reusable subflows
affects: [10-03, 10-04, 10-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [JSON decision tree flows, fragment-based subflow reuse, tiered flow depth]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/index.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/fragments/export-escalation.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/fragments/dependency-install.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/launch-crash.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/graphics.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/audio.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/launcher-issues.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/install-dependencies.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/network-download.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/controller-input.json
    - WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/performance-stability.json
  modified: []

key-decisions:
  - "Shared verify_fix node per flow: single verify node reused by multiple fix branches to stay within node count limits"
  - "Launcher-issues flow consolidates EA/Epic/Rockstar into shared check_launcher_env path (branch at detection, converge at env check)"
  - "Controller-input and performance-stability omit resolved node or merge check nodes to meet 4-5 node shallow flow requirement"
  - "Fragment node IDs usable as cross-file targets via on-map (escalation_summary, resolved in fragments)"

patterns-established:
  - "Flow JSON schema: version, categoryId, entryNodeId, nodes map with id/type/phase/title/description/checkId/params/on/evidenceMap/fixId/fixPreview/isReversible/requiresConfirmation/fragmentRef"
  - "Fragment reuse: fragmentRef field on terminal nodes references shared subflows (export-escalation, dependency-install)"
  - "Tiered depth: deep flows 8-12 nodes with multiple check/fix/verify cycles; shallow flows 4-5 nodes with early escalation"

# Metrics
duration: 8min
completed: 2026-02-12
---

# Phase 10 Plan 02: Flow JSON Definitions Summary

**11 JSON troubleshooting flow files covering 8 symptom categories with tiered depth, shared fragments for escalation and dependency install, and stable checkId references**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-12T03:16:10Z
- **Completed:** 2026-02-12T03:24:39Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- Created complete JSON flow definition library for all 8 troubleshooting symptom categories
- Built 2 shared fragment subflows (export-escalation with 7 nodes, dependency-install with 5 nodes)
- Deep flows (launch-crash, graphics, audio, launcher-issues, install-dependencies, network-download) each have 8-12 nodes with multi-branch diagnostic paths
- Shallow flows (controller-input, performance-stability) each have 4-5 nodes with early escalation per locked tiered flow decisions
- All node cross-references validate: every on-map target resolves within the same file or to a fragment node
- Index.json lists all 8 categories with SF Symbols, depth metadata, and flowFile references

## Task Commits

Each task was committed atomically:

1. **Task 1: Index, fragments, and deep flows** - `3f3c5436` (feat)
2. **Task 2: Remaining deep flows and shallow flows** - `4983c5d1` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/index.json` - Category metadata with 8 entries, SF Symbols, depth indicators, and flow file references
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/fragments/export-escalation.json` - Shared escalation subflow: enhanced diagnostics -> reclassify -> export bundle -> support draft
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/fragments/dependency-install.json` - Shared dependency install subflow: check -> install -> verify
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/launch-crash.json` - 12-node deep flow: crash classify -> GPU/DLL/winetricks branches -> env check
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/graphics.json` - 11-node deep flow: backend check -> crash log -> DXVK async -> game config
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/audio.json` - 11-node deep flow: device check -> driver -> buffer size -> sample rate
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/launcher-issues.json` - 12-node deep flow: type detect -> Steam process/download, EA/Epic/Rockstar env
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/install-dependencies.json` - 10-node deep flow: verb check -> DLL scan -> game config
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/network-download.json` - 12-node deep flow: launcher detect -> Steam download/restart -> DNS check
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/controller-input.json` - 5-node shallow flow: compat mode check -> fix -> verify
- `WhiskyKit/Sources/WhiskyKit/Troubleshooting/Resources/flows/performance-stability.json` - 5-node shallow flow: esync check -> fix -> verify

## Decisions Made
- Shared verify_fix node per flow reduces duplication and keeps node counts within limits
- Launcher-issues flow branches at type detection but converges EA/Epic/Rockstar into a shared env check path
- Shallow flows use combined escalate nodes with Bluetooth/HUD guidance embedded in description text rather than separate info nodes
- Fragment node IDs are valid cross-file targets allowing flows to reference export-escalation nodes via on-map

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 11 JSON flow files ready for consumption by FlowLoader (Plan 03) and TroubleshootingFlowEngine (Plan 03)
- Stable checkId references ready for CheckRegistry implementation (Plan 04)
- Fragment files ready for cross-flow subflow resolution

## Self-Check: PASSED

All 11 JSON files exist. Both task commits (3f3c5436, 4983c5d1) verified. SUMMARY.md exists.

---
*Phase: 10-guided-troubleshooting*
*Completed: 2026-02-12*
