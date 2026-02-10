---
phase: 05-stability-diagnostics
plan: 02
subsystem: diagnostics
tags: [persistence, export, privacy, redaction, zip, markdown, plist, fifo]

# Dependency graph
requires:
  - phase: 05-01
    provides: CrashDiagnosis, CrashCategory, ConfidenceTier, CrashPattern, PatternLoader, WineDebugPreset types
  - phase: 02-configuration-foundation
    provides: EnvironmentBuilder for environment resolution, Wine.constructWineEnvironment
provides:
  - DiagnosisHistory with bounded FIFO persistence (max 5 entries per program)
  - RemediationTimeline with bounded FIFO persistence (max 10 entries per bottle/program)
  - Redactor composable redaction pipeline (home paths, sensitive env keys)
  - DiagnosticExporter ZIP export via /usr/bin/ditto
  - DiagnosticExporter Markdown report for GitHub issue pasting
  - ExportOptions for controlling privacy and content inclusion
  - CrashDiagnosisCodableWrapper for JSON serialization of diagnosis results
affects: [05-03 process integration, 05-04 UI, 05-05 export views]

# Tech tracking
tech-stack:
  added: [PropertyListEncoder/Decoder for diagnosis persistence, /usr/bin/ditto for ZIP creation]
  patterns: [caseless enum for stateless utilities (Redactor, DiagnosticExporter), CodableWrapper for non-Codable type serialization, FIFO eviction with bounded collections]

key-files:
  created:
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosisHistory.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/RemediationTimeline.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/Redactor.swift
    - WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosticExporter.swift
    - WhiskyKit/Tests/WhiskyKitTests/DiagnosticExporterTests.swift
  modified: []

key-decisions:
  - "CrashDiagnosisCodableWrapper encodes only serializable portions of CrashDiagnosis for JSON export"
  - "Redactor uses FileManager.default.homeDirectoryForCurrentUser for runtime home path detection"
  - "DiagnosticExporter captures MainActor-isolated values before Task.detached for file I/O"
  - "ExportOptions at module scope (not nested) for easier import and configuration"

patterns-established:
  - "FIFO bounded collection: append + while count > max removeFirst()"
  - "CodableWrapper pattern: wrap non-Codable types for JSON serialization"
  - "Markdown report generation as static method returning String"
  - "Privacy-by-default: all content passes through Redactor unless explicitly opted out"

# Metrics
duration: 6min
completed: 2026-02-10
---

# Phase 05 Plan 02: Diagnostic Export Infrastructure Summary

**DiagnosisHistory and RemediationTimeline with FIFO persistence, Redactor for home path and sensitive key scrubbing, DiagnosticExporter for ZIP (via ditto) and Markdown report generation with 23 unit tests**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-10T04:41:52Z
- **Completed:** 2026-02-10T04:48:16Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- DiagnosisHistory and RemediationTimeline with bounded FIFO eviction and PropertyListEncoder/Decoder round-trip persistence
- Redactor composable pipeline: home path replacement, sensitive env key filtering (TOKEN, KEY, SECRET, PASSWORD, AUTH), case-insensitive matching
- DiagnosticExporter.exportZIP() creates ZIP with report.md, crash.json, env.json, bottle-settings.json, program-settings.json, wine.log, wine.tail.log, system.json, remediation-history.json
- DiagnosticExporter.generateMarkdownReport() produces paste-ready Markdown with system info, bottle config, diagnosis summary, matched patterns, suggested remediations, environment keys
- 23 unit tests covering redaction correctness, FIFO bounds, plist round-trips, report content, and helper utilities

## Task Commits

Each task was committed atomically:

1. **Task 1: DiagnosisHistory, RemediationTimeline, and Redactor** - `845e4fc2` (feat)
2. **Task 2: DiagnosticExporter with ZIP and Markdown output** - `50c0bacd` (feat)

## Files Created/Modified
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosisHistory.swift` - Per-program diagnosis persistence with bounded FIFO (max 5)
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/RemediationTimeline.swift` - Remediation action tracking with bounded FIFO (max 10)
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/Redactor.swift` - Composable redaction for home paths and sensitive env keys
- `WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosticExporter.swift` - ZIP and Markdown export with redaction and privacy controls
- `WhiskyKit/Tests/WhiskyKitTests/DiagnosticExporterTests.swift` - 23 tests for redaction, history, timeline, and export

## Decisions Made
- **CrashDiagnosisCodableWrapper**: CrashDiagnosis contains non-Codable DiagnosisMatch entries (due to CrashPattern with nonisolated(unsafe) Regex), so a lightweight wrapper encodes only serializable fields.
- **Runtime home path detection**: Redactor uses FileManager.default.homeDirectoryForCurrentUser at call time rather than compile-time constants, ensuring correctness across user accounts.
- **MainActor value capture before Task.detached**: DiagnosticExporter captures all Bottle/Program-derived values on MainActor, then passes them to a detached task for file I/O to avoid data races.
- **ExportOptions at module scope**: Placed outside DiagnosticExporter enum for cleaner public API surface and easier import.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- DiagnosisHistory ready for consumption by Plan 05-03 (process integration) to persist diagnoses after crash classification
- RemediationTimeline ready for consumption by Plan 05-04 (UI) to display action history
- DiagnosticExporter ready for consumption by Plan 05-05 (export views) to wire into UI buttons
- Redactor available as a composable utility for any future privacy-sensitive export

## Self-Check: PASSED

All 5 files found. Both task commits verified (845e4fc2, 50c0bacd).

---
*Phase: 05-stability-diagnostics*
*Completed: 2026-02-10*
