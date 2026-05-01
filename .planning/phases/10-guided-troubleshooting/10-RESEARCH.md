# Phase 10: Guided Troubleshooting - Research

**Researched:** 2026-02-11
**Domain:** Data-driven troubleshooting engine, JSON decision trees, wizard state machine, diagnostic probe orchestration, session persistence
**Confidence:** HIGH

## Summary

Phase 10 builds a unified, data-driven troubleshooting engine that wraps all previous diagnostic infrastructure (Phases 4-7) into interactive, multi-category guided flows. The core technical challenge is designing a generalized JSON-driven decision tree engine that orchestrates existing diagnostic primitives (CrashClassifier, AudioProbes, GPUDetection, GameMatcher, environment/settings introspection) through a single-page wizard UI with a 5-phase progress rail, session persistence, fix application with undo, and escalation/export.

The codebase already provides every diagnostic building block. Phase 5 contributed `CrashClassifier`, `CrashPattern`, `PatternLoader`, `RemediationAction`, `RemediationCardView`, `DiagnosticExporter`, `Redactor`, `RemediationTimeline`, `ConfidenceTier`, `DiagnosisHistory`, and `WineDebugPreset`. Phase 6 added `AudioTroubleshootingEngine` (a working wizard state machine with probe injection), `AudioProbe` protocol, `CoreAudioDeviceProbe`, `WineRegistryAudioProbe`, `WineAudioTestProbe`, `AudioFinding`, `AudioProbeResult`, `ProbeStatus`, `AudioDeviceMonitor`, and `TroubleshootingFixAttempt`. Phase 4 provided `GraphicsBackendResolver`, `GPUDetection`, `BottleGraphicsConfig`, and `BackendPickerView`. Phase 7 added `GameMatcher`, `GameDBEntry`, `GameConfigApplicator`, and `StalenessChecker`. The settings infrastructure (`BottleSettings`, `ProgramOverrides`, `EnvironmentBuilder`, `DLLOverrideResolver`) and UI patterns (`StatusToast`, `ToastModifier`, `NavigationStack`, sheet presentations) are mature and battle-tested.

The new work is: (1) a `TroubleshootingFlowEngine` that generalizes `AudioTroubleshootingEngine` into a category-agnostic JSON-driven state machine; (2) a `CheckRegistry` that maps stable check IDs to implementations wrapping existing diagnostic primitives; (3) JSON flow definitions split per symptom category with a shared index; (4) session persistence with bounded storage and staleness detection; (5) a single-page wizard view with progress rail, step cards, branching explanation, and fix preview/apply/verify cycle; (6) entry point integration across ProgramView, ConfigView, toast/banner triggers, and Help menu; and (7) troubleshooting history per bottle/program.

**Primary recommendation:** Generalize the Phase 6 `AudioTroubleshootingEngine` pattern into a `TroubleshootingFlowEngine` driven by JSON step nodes. Map each `checkId` to a `TroubleshootingCheck` protocol implementation that wraps existing diagnostics. Bundle flow JSON as SPM resources in `WhiskyKit/TroubleshootingFlows/Resources/`. Build the wizard as a single SwiftUI sheet with a vertical progress rail and scrolling step card area.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Flow Navigation & Presentation
- Single-page wizard with step cards (not multi-screen navigation)
- Progress rail with 5 stable core phases: Symptom -> Checks -> Fix -> Verify -> Export
- Rail is state-based: branch-specific steps appear under the active phase
- Completed steps lock as completed; superseded future steps shown with subtle "superseded" style (not deleted)
- Inline "Why path changed" explanation when branching alters the path
- Step numbering relative to current path (e.g., "Step 3 of 6"), no confusing renumbering of past steps
- Back/forward navigation and "skip for now" supported, state persisted per run
- Deep links (to Config/Logs) open as sub-sheets and return to the same wizard step

#### Session Persistence
- Resumable draft sessions: auto-save state (symptom, probes run, findings, fixes attempted, branch decisions) per bottle/program
- Paused sessions show "Resume troubleshooting" in Program/Bottle Diagnostics
- On resume: restore exact step, re-run lightweight probes for staleness ("Since you left" check)
- Explicit actions: Resume, Start over, Discard session
- Bounded storage: last 1 active + recent completed history; stale paused sessions expire after 14 days

#### Fix Application
- Explicit gated "Apply and verify" per fix card -- no silent auto-apply
- Each fix step shows diff-style preview of what will change (scoped to bottle/program)
- Require explicit "Apply fix" click; high-impact changes (winetricks/install/restart/kill) get additional confirmation
- Apply atomically where possible: settings/env changes are immediate writes
- Record attempt entry per fix: fix ID, timestamp, before/after values, result
- Immediately run verification probe after each fix: "Did this fix it?"
- If no -> branch to next fix; if yes -> mark resolved, offer finish/export
- Support Undo for reversible settings changes; clearly label non-reversible actions

#### Automated Checks
- Thin orchestration layer over existing Phase 5/6 diagnostic primitives -- not a parallel diagnostics system
- Reuse: CrashClassifier, AudioProbes, GPUDetection, remediation catalog, environment/provenance snapshots, export pipeline
- Check IDs referenced in decision tree JSON with parameters; implementations live in code returning normalized result enum + evidence payload
- Lazy execution with cheap eager preflight: startup collects bottle/program identity, launcher type, running state, recent log pointer, audio device route
- Heavier checks (classification, dependency probes, audio tests, process scans) run lazily per step
- Re-run checks after each applied fix for verification
- Pre-satisfied checks: mark as "Already configured" with one-line note, auto-advance to next step, record outcome in session timeline
- Consistent language: same categories/severity/confidence as diagnostics views everywhere

#### Check Binding in JSON
- Each step node references a stable `checkId` + `params` object
- Branching keyed by normalized outcomes: `pass`, `fail`, `already_configured`, `unknown`, `error`
- Optional `evidenceMap` for surfacing specific finding fields in UI
- Check IDs are versioned/stable so flows and analytics don't break when internals change

#### Entry Points & Discovery
- Primary: "Troubleshoot..." action in Program view (gives full program + bottle + recent runs/logs context)
- Secondary deep links:
  - Launch failure toast/banner -> "Troubleshoot" (starts at Findings with prefilled evidence)
  - Bottle Config Diagnostics section -> "Start Guided Troubleshooting" (starts at Checks summary)
  - Global Help menu -> opens target picker (bottle/program) then starts wizard from Symptom selection
- Context-aware start: entry context sets initial node and preloaded data (one wizard system, multiple entry depths)
- Proactive suggestions on strong failure signals only: launch failure, high-confidence crash match, repeated stall/timeout
- Show toast/banner (not auto-open); rate-limited per bottle/program/session
- Low-confidence heuristics: passive button in Program/Bottle Diagnostics only

#### Troubleshooting History
- Completed sessions stored per bottle/program: timestamp, symptom, primary findings, fixes attempted, final outcome
- Viewable from Program/Bottle Diagnostics as "Troubleshooting History"
- Bounded: last 20 sessions or 30 days; sensitive payloads redacted by default
- "Reopen as template" (reuse flow with fresh checks) and "Export session report" available

#### Symptom Categories
- 8 user-language categories:
  1. Won't launch / crashes immediately
  2. Launcher issues (Steam/EA/Epic/Rockstar)
  3. Graphics problems (black screen, flicker, low FPS)
  4. Audio problems (no sound, crackle, wrong device)
  5. Controller/input problems (not detected, wrong mapping)
  6. Install/dependency problems (.NET, VC++, DirectX, Winetricks)
  7. Network/download problems (timeouts, Steam stalls)
  8. Performance/stability over time (stutter, hangs after minutes)
- "Other" as fallback only if needed

#### Flow Depth (Tiered)
- All categories get a shallow core flow (triage -> 1-2 safe fixes -> verify -> export), ~4-5 steps max
- Deep branches for high-frequency/high-confidence: launch/crash, launcher/network, graphics, dependencies -- up to 8-12 steps
- Lighter flows for lower-signal categories: controller, long-run performance/stability -- escalate earlier to diagnostics/export
- Stop early on success; cap retries (3 failed fix loops) then move to advanced diagnostics/report

#### Escalation Path
- Mark flow outcome as "Unresolved" with summary of everything tried
- Offer Enhanced Diagnostics Re-run (opt-in debug preset like targeted WINEDEBUG) and reclassify once
- If still unresolved: generate Export Diagnostics bundle with findings, confidence, attempted fixes/timestamps, env provenance, relevant logs
- One-click "Open Support Issue Draft" with exported bundle path and summary
- Keep session in history as "Unresolved"; allow "Retry from step X" later

#### Decision Tree File Structure
- Split per symptom category plus shared index:
  - `index.json`: category metadata, entry nodes, versioning
  - `flows/<category>.json`: one flow file per symptom category
  - `fragments/`: shared subflows (dependency install, export/escalation)
- Benefits: easier review, smaller diffs, safer iteration, cleaner ownership per domain

### Claude's Discretion
- Exact step card visual design and spacing
- Progress rail implementation details (vertical vs horizontal)
- Preflight probe set composition
- Session storage format and serialization
- Toast/banner visual treatment for proactive suggestions
- Specific normalized result enum cases beyond the 5 specified

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation `JSONDecoder` | Built-in | Parse flow definition JSON (index.json, category flows, fragments) | Same pattern as `PatternLoader` for `patterns.json` and `GameDBLoader` for `GameDB.json` |
| Foundation `PropertyListEncoder` | Built-in | Session persistence, troubleshooting history storage | Matches `DiagnosisHistory`, `RemediationTimeline`, `GameConfigSnapshot` patterns |
| Foundation `FileManager` | Built-in | Session file management, expiry cleanup, flow resource discovery | Already used throughout for bottle/program file operations |
| SwiftUI | macOS 15+ | Wizard view, progress rail, step cards, fix preview, deep link sheets | Existing UI framework; all views follow established patterns |
| `os.log` Logger | Built-in | Engine lifecycle logging, check execution tracing | Already used via `Logger` in `AudioTroubleshootingEngine` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Phase 5 Diagnostics types | In-tree | `CrashClassifier`, `ConfidenceTier`, `RemediationAction`, `DiagnosticExporter`, `Redactor`, `WineDebugPreset` | Reuse directly for crash/graphics check implementations and escalation export |
| Phase 6 Audio types | In-tree | `AudioProbe`, `AudioProbeResult`, `AudioFinding`, `AudioDeviceMonitor`, `ProbeStatus` | Reuse for audio check implementations |
| Phase 4 Graphics types | In-tree | `GraphicsBackendResolver`, `GPUDetection`, `BottleGraphicsConfig` | Reuse for graphics check implementations |
| Phase 7 Game DB types | In-tree | `GameMatcher`, `GameDBEntry`, `MatchResult` | Reuse for "known config available" checks |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom JSON flow engine | Hardcoded Swift state machine per category | JSON enables flow updates without recompilation; hardcoded would be faster to build but doesn't meet the "data-driven" requirement |
| Per-category flow files | Single monolithic flows.json | Split files give smaller diffs, cleaner ownership, easier review -- matches locked decision |
| Plist for session storage | JSON for session storage | Plist matches all existing WhiskyKit persistence patterns (`DiagnosisHistory`, `RemediationTimeline`); JSON would work but breaks consistency |

**Installation:** No new dependencies required. All flow JSON ships as SPM resources. Everything builds with Foundation and SwiftUI.

## Architecture Patterns

### Recommended Project Structure
```
WhiskyKit/Sources/WhiskyKit/
  Troubleshooting/                          # NEW: Core engine and models
    TroubleshootingFlowEngine.swift         # JSON-driven state machine (generalizes AudioTroubleshootingEngine)
    TroubleshootingSession.swift            # Session state: current step, findings, fixes, branch decisions
    TroubleshootingSessionStore.swift       # Persistence: save/load/expire sessions per bottle/program
    TroubleshootingHistory.swift            # Completed session history (bounded, per bottle/program)
    TroubleshootingHistoryEntry.swift       # Single completed session summary
    FlowDefinition.swift                    # Codable models for JSON flow nodes (step, check, fix, branch)
    FlowLoader.swift                        # JSON loader for index + category flows + fragments
    FlowIndex.swift                         # Category metadata, entry nodes, versioning
    SymptomCategory.swift                   # 8 symptom categories enum
    CheckRegistry.swift                     # Maps checkId strings to TroubleshootingCheck implementations
    TroubleshootingCheck.swift              # Protocol: run(params) -> CheckResult
    CheckResult.swift                       # Normalized result: pass/fail/already_configured/unknown/error + evidence
    FixApplicator.swift                     # Apply fix, snapshot before/after, record attempt
    FixAttempt.swift                        # Single fix attempt record (extends TroubleshootingFixAttempt pattern)
    PreflightCollector.swift                # Cheap eager preflight data collection
    PreflightData.swift                     # Preflight snapshot: bottle/program identity, launcher, running state, etc.
    EntryContext.swift                       # Entry point context: where user came from, preloaded evidence
    Resources/
      index.json                            # Category metadata, entry nodes, versioning
      flows/
        launch-crash.json                   # Won't launch / crashes immediately
        launcher-issues.json                # Steam/EA/Epic/Rockstar launcher issues
        graphics.json                       # Black screen, flicker, low FPS
        audio.json                          # No sound, crackle, wrong device
        controller-input.json               # Not detected, wrong mapping
        install-dependencies.json           # .NET, VC++, DirectX, Winetricks
        network-download.json               # Timeouts, Steam stalls
        performance-stability.json          # Stutter, hangs after minutes
      fragments/
        dependency-install.json             # Shared: dependency installation subflow
        export-escalation.json              # Shared: export diagnostics + escalation
  Troubleshooting/Checks/                   # NEW: Check implementations
    CrashLogCheck.swift                     # Wraps CrashClassifier for log pattern matching
    GraphicsBackendCheck.swift              # Wraps GraphicsBackendResolver / BottleGraphicsConfig
    DXVKSettingsCheck.swift                 # Checks DXVK async, HUD, conf presence
    AudioDriverCheck.swift                  # Wraps WineRegistryAudioProbe
    AudioDeviceCheck.swift                  # Wraps CoreAudioDeviceProbe
    AudioTestCheck.swift                    # Wraps WineAudioTestProbe
    DependencyCheck.swift                   # Checks DLL existence in prefix (vcrun, dotnet, d3dx, etc.)
    WinetricksVerbCheck.swift              # Wraps Winetricks.loadInstalledVerbs
    LauncherTypeCheck.swift                 # Checks launcher detection + launcher config
    ProcessRunningCheck.swift               # Wraps ProcessRegistry.getProcessCount + Wine.isWineserverRunning
    EnvironmentCheck.swift                  # Checks specific env var via EnvironmentBuilder.resolve
    RegistryValueCheck.swift                # Wraps Wine.queryRegistryKey for arbitrary keys
    GameConfigAvailableCheck.swift          # Wraps GameMatcher for "known config" suggestions
    SettingValueCheck.swift                 # Checks a BottleSettings/ProgramOverrides property value

Whisky/Views/
  Troubleshooting/                          # NEW: Wizard UI
    TroubleshootingWizardView.swift         # Main single-page wizard sheet
    ProgressRailView.swift                  # 5-phase vertical progress rail
    StepCardView.swift                      # Individual step card (check, fix, info, verify)
    FixPreviewView.swift                    # Diff-style preview of what a fix will change
    FixVerifyView.swift                     # "Did this fix it?" confirmation gate
    SymptomPickerView.swift                 # 8-category symptom selection
    BranchExplanationView.swift             # "Why path changed" inline explanation
    SessionResumeView.swift                 # "Resume / Start over / Discard" for paused sessions
    TroubleshootingHistoryView.swift        # History list per bottle/program
    TroubleshootingEntryBanner.swift        # "Troubleshoot..." banner/button for entry points
    EscalationView.swift                    # Unresolved outcome with export/retry options
    TroubleshootingTargetPicker.swift       # Bottle/program picker for Help menu entry
```

### Pattern 1: TroubleshootingFlowEngine (Generalized State Machine)
**What:** A JSON-driven state machine that generalizes the Phase 6 `AudioTroubleshootingEngine`. Instead of hardcoded symptom-to-fix mappings, it traverses a graph of step nodes loaded from JSON, running checks via the `CheckRegistry` and branching on normalized results.
**When to use:** Every troubleshooting session, regardless of symptom category.
**Example:**
```swift
// TroubleshootingFlowEngine.swift
@MainActor
public final class TroubleshootingFlowEngine: ObservableObject {
    // MARK: - Core Published State
    @Published public var session: TroubleshootingSession
    @Published public var isRunningCheck: Bool = false

    // MARK: - Dependencies
    private let flowDefinitions: [String: FlowDefinition]
    private let fragments: [String: FlowDefinition]
    private let checkRegistry: CheckRegistry
    private let sessionStore: TroubleshootingSessionStore
    private let logger = Logger(subsystem: "com.isaacmarovitz.Whisky", category: "TroubleshootingFlowEngine")

    public init(
        flowDefinitions: [String: FlowDefinition],
        fragments: [String: FlowDefinition],
        checkRegistry: CheckRegistry,
        sessionStore: TroubleshootingSessionStore,
        session: TroubleshootingSession = TroubleshootingSession()
    ) {
        self.flowDefinitions = flowDefinitions
        self.fragments = fragments
        self.checkRegistry = checkRegistry
        self.sessionStore = sessionStore
        self.session = session
    }

    /// Selects a symptom category and loads the corresponding flow.
    public func selectCategory(_ category: SymptomCategory) {
        guard let flow = flowDefinitions[category.flowFileName] else {
            session.phase = .escalation
            return
        }
        session.symptomCategory = category
        session.currentFlow = flow
        session.phase = .checks
        navigateToNode(flow.entryNodeId)
    }

    /// Navigates to a specific step node, runs its check if applicable.
    public func navigateToNode(_ nodeId: String) {
        guard let node = resolveNode(nodeId) else {
            session.phase = .escalation
            return
        }
        session.pushStep(node)
        autoSave()

        if let checkId = node.checkId {
            runCheck(checkId: checkId, params: node.params ?? [:], node: node)
        }
    }

    /// Runs a check and branches based on the normalized result.
    private func runCheck(checkId: String, params: [String: String], node: FlowStepNode) {
        isRunningCheck = true
        Task {
            let result = await checkRegistry.run(checkId: checkId, params: params, session: session)
            isRunningCheck = false
            session.recordCheckResult(nodeId: node.id, result: result)

            // Branch on normalized outcome
            let outcome = result.outcome.rawValue  // "pass", "fail", etc.
            if let nextNodeId = node.on?[outcome] {
                navigateToNode(nextNodeId)
            } else if let defaultNext = node.on?["default"] {
                navigateToNode(defaultNext)
            }
            autoSave()
        }
    }

    /// Records a fix application and runs verification.
    public func applyFix(fixId: String, beforeValue: String?, afterValue: String?) {
        let attempt = FixAttempt(
            fixId: fixId,
            timestamp: Date(),
            beforeValue: beforeValue,
            afterValue: afterValue,
            result: .pending
        )
        session.recordFixAttempt(attempt)
        session.phase = .verify
        autoSave()
    }

    public func userReportsFixed() {
        session.outcome = .resolved
        session.phase = .export
        autoSave()
        sessionStore.completeSession(session)
    }

    public func userReportsNotFixed() {
        if session.failedFixCount >= 3 {
            session.phase = .escalation
        } else {
            // Re-run current check for verification, then branch to next fix
            if let currentNode = session.currentNode, let checkId = currentNode.checkId {
                runCheck(checkId: checkId, params: currentNode.params ?? [:], node: currentNode)
            }
        }
        autoSave()
    }

    private func resolveNode(_ nodeId: String) -> FlowStepNode? {
        // Check current flow first, then fragments
        session.currentFlow?.nodes[nodeId] ?? fragments.values
            .compactMap { $0.nodes[nodeId] }.first
    }

    private func autoSave() {
        sessionStore.save(session)
    }
}
```

### Pattern 2: TroubleshootingCheck Protocol + CheckRegistry
**What:** A protocol for check implementations with a registry that maps stable string IDs to concrete implementations. Each check wraps an existing diagnostic primitive and returns a normalized `CheckResult`.
**When to use:** Every time a flow step node references a `checkId`.
**Example:**
```swift
// TroubleshootingCheck.swift
public protocol TroubleshootingCheck: Sendable {
    /// Stable identifier matching the JSON checkId.
    var checkId: String { get }

    /// Runs the check with the given parameters.
    func run(params: [String: String], context: CheckContext) async -> CheckResult
}

// CheckResult.swift
public struct CheckResult: Sendable {
    public let outcome: CheckOutcome
    public let evidence: [String: String]  // Key-value pairs for evidenceMap
    public let summary: String
    public let confidence: ConfidenceTier?

    public enum CheckOutcome: String, Sendable, Codable {
        case pass
        case fail
        case alreadyConfigured = "already_configured"
        case unknown
        case error
    }
}

// CheckContext.swift -- passed to every check
public struct CheckContext: Sendable {
    public let bottle: Bottle
    public let program: Program?
    public let preflight: PreflightData
    public let session: TroubleshootingSession
}

// CheckRegistry.swift
public final class CheckRegistry: @unchecked Sendable {
    private var checks: [String: any TroubleshootingCheck] = [:]

    public init() {
        registerDefaults()
    }

    public func register(_ check: any TroubleshootingCheck) {
        checks[check.checkId] = check
    }

    public func run(checkId: String, params: [String: String],
                    session: TroubleshootingSession) async -> CheckResult {
        guard let check = checks[checkId] else {
            return CheckResult(
                outcome: .error,
                evidence: ["error": "Unknown checkId: \(checkId)"],
                summary: "Check not found: \(checkId)",
                confidence: nil
            )
        }
        let context = CheckContext(
            bottle: session.bottle,
            program: session.program,
            preflight: session.preflight,
            session: session
        )
        return await check.run(params: params, context: context)
    }

    private func registerDefaults() {
        register(GraphicsBackendCheck())
        register(DXVKSettingsCheck())
        register(CrashLogCheck())
        register(AudioDriverCheck())
        register(AudioDeviceCheck())
        register(DependencyCheck())
        register(WinetricksVerbCheck())
        register(LauncherTypeCheck())
        register(ProcessRunningCheck())
        register(EnvironmentCheck())
        register(RegistryValueCheck())
        register(SettingValueCheck())
        register(GameConfigAvailableCheck())
    }
}
```

### Pattern 3: Check Implementation Wrapping Existing Primitives
**What:** Each check wraps an existing diagnostic primitive, translating its output to the normalized `CheckResult` format. This is the "thin orchestration layer" specified in the decisions.
**When to use:** Implementing each concrete check.
**Example:**
```swift
// GraphicsBackendCheck.swift
public struct GraphicsBackendCheck: TroubleshootingCheck {
    public let checkId = "graphics.backend_is"

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        guard let expected = params["expected"] else {
            return CheckResult(outcome: .error, evidence: [:],
                             summary: "Missing 'expected' parameter", confidence: nil)
        }

        let scope = params["scope"] ?? "bottle"
        let currentBackend: GraphicsBackend

        if scope == "program_or_bottle", let program = context.program,
           let overrideBackend = program.settings.overrides?.graphicsBackend {
            currentBackend = overrideBackend
        } else {
            currentBackend = context.bottle.settings.graphicsBackend
        }

        // Resolve .recommended to concrete backend
        let resolved = currentBackend == .recommended
            ? GraphicsBackendResolver.resolve()
            : currentBackend

        let evidence = [
            "current": resolved.rawValue,
            "expected": expected,
            "configured": currentBackend.rawValue
        ]

        if resolved.rawValue == expected {
            if currentBackend.rawValue == expected {
                return CheckResult(outcome: .alreadyConfigured, evidence: evidence,
                    summary: "Backend is already set to \(expected)", confidence: .high)
            }
            return CheckResult(outcome: .pass, evidence: evidence,
                summary: "Backend resolves to \(expected)", confidence: .high)
        }
        return CheckResult(outcome: .fail, evidence: evidence,
            summary: "Backend is \(resolved.rawValue), expected \(expected)", confidence: .high)
    }
}

// CrashLogCheck.swift
public struct CrashLogCheck: TroubleshootingCheck {
    public let checkId = "crash.log_classify"

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        let classifier = CrashClassifier()
        // Get most recent log for this program
        guard let logURL = context.preflight.recentLogURL,
              let logText = try? String(contentsOf: logURL, encoding: .utf8) else {
            return CheckResult(outcome: .unknown, evidence: [:],
                summary: "No recent log file available", confidence: .low)
        }

        let diagnosis = classifier.classify(log: logText, exitCode: context.preflight.lastExitCode)

        if diagnosis.isEmpty {
            return CheckResult(outcome: .pass, evidence: [:],
                summary: "No crash patterns detected in log", confidence: .medium)
        }

        var evidence: [String: String] = [:]
        if let category = diagnosis.primaryCategory {
            evidence["primaryCategory"] = category.rawValue
        }
        if let confidence = diagnosis.primaryConfidence {
            evidence["confidence"] = confidence.rawValue
        }
        if let headline = diagnosis.headline {
            evidence["headline"] = headline
        }
        evidence["matchCount"] = "\(diagnosis.matches.count)"

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: diagnosis.headline ?? "Crash patterns detected",
            confidence: diagnosis.primaryConfidence
        )
    }
}
```

### Pattern 4: Flow Step Node JSON Schema
**What:** The JSON schema for individual step nodes in flow definition files, matching the CONTEXT.md example shape.
**When to use:** Authoring flow JSON files.
**Example:**
```swift
// FlowDefinition.swift
public struct FlowDefinition: Codable, Sendable {
    public let version: Int
    public let categoryId: String
    public let nodes: [String: FlowStepNode]
    public let entryNodeId: String
}

public struct FlowStepNode: Codable, Sendable, Identifiable {
    public let id: String
    public let type: NodeType             // "check", "fix", "info", "verify", "branch"
    public let phase: FlowPhase           // symptom, checks, fix, verify, export
    public let title: String?
    public let description: String?
    public let checkId: String?           // For "check" type nodes
    public let params: [String: String]?  // Parameters for the check
    public let on: [String: String]?      // Outcome -> next node ID mapping
    public let evidenceMap: [String: String]?  // evidence key -> UI display label
    public let fixId: String?             // For "fix" type nodes
    public let fixPreview: FixPreviewData? // Diff-style preview data
    public let isReversible: Bool?
    public let requiresConfirmation: Bool? // Extra confirmation for high-impact fixes
    public let fragmentRef: String?       // Reference to shared fragment

    public enum NodeType: String, Codable, Sendable {
        case check, fix, info, verify, branch
    }

    public enum FlowPhase: String, Codable, Sendable {
        case symptom, checks, fix, verify, export
    }
}

public struct FixPreviewData: Codable, Sendable {
    public let settingName: String
    public let currentValueKey: String?   // Key in evidence to show current value
    public let newValue: String
    public let scope: String              // "bottle" or "program"
}
```

### Pattern 5: Session Persistence
**What:** Troubleshooting sessions auto-save to plist files in the bottle directory, following the `DiagnosisHistory` and `RemediationTimeline` persistence patterns. Includes staleness detection for resumed sessions.
**When to use:** Every state transition in the engine triggers `autoSave()`.
**Example:**
```swift
// TroubleshootingSession.swift
public struct TroubleshootingSession: Codable, Sendable {
    public var id: UUID = UUID()
    public var bottleURL: URL?
    public var programURL: URL?
    public var symptomCategory: SymptomCategory?
    public var phase: SessionPhase = .symptom
    public var stepHistory: [CompletedStep] = []    // Completed/superseded steps
    public var currentNodeId: String?
    public var checkResults: [String: CheckResult] = [:]
    public var fixAttempts: [FixAttempt] = []
    public var branchDecisions: [BranchDecision] = []
    public var outcome: SessionOutcome?
    public var createdAt: Date = Date()
    public var lastUpdatedAt: Date = Date()
    public var preflightSnapshot: PreflightData?

    public enum SessionPhase: String, Codable, Sendable {
        case symptom, checks, fix, verify, export, escalation
    }

    public enum SessionOutcome: String, Codable, Sendable {
        case resolved, unresolved, abandoned
    }
}

// TroubleshootingSessionStore.swift
public struct TroubleshootingSessionStore {
    private static let activeSessionFileName = "TroubleshootingSession.plist"
    private static let historyFileName = "TroubleshootingHistory.plist"
    private static let staleSessionDays = 14

    public func save(_ session: TroubleshootingSession) {
        guard let bottleURL = session.bottleURL else { return }
        let url = bottleURL.appending(path: Self.activeSessionFileName)
        var mutable = session
        mutable.lastUpdatedAt = Date()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        guard let data = try? encoder.encode(mutable) else { return }
        try? data.write(to: url)
    }

    public func loadActiveSession(for bottleURL: URL) -> TroubleshootingSession? {
        let url = bottleURL.appending(path: Self.activeSessionFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let session = try? PropertyListDecoder().decode(
            TroubleshootingSession.self, from: data
        ) else { return nil }
        // Check staleness
        let daysSinceUpdate = Calendar.current.dateComponents(
            [.day], from: session.lastUpdatedAt, to: Date()
        ).day ?? 0
        return daysSinceUpdate <= Self.staleSessionDays ? session : nil
    }

    public func deleteActiveSession(for bottleURL: URL) {
        let url = bottleURL.appending(path: Self.activeSessionFileName)
        try? FileManager.default.removeItem(at: url)
    }
}
```

### Pattern 6: Progress Rail (Vertical, State-Based)
**What:** A vertical progress rail showing the 5 stable phases with state-based step indicators. Completed steps show checkmarks; the active phase shows current step details; superseded future steps show a subtle dimmed style.
**When to use:** Left side of the wizard view.
**Recommended implementation:** Vertical rail with SF Symbols.
```swift
// ProgressRailView.swift
struct ProgressRailView: View {
    let session: TroubleshootingSession
    let phases: [RailPhase] = [
        RailPhase(phase: .symptom, title: "Symptom", sfSymbol: "questionmark.circle"),
        RailPhase(phase: .checks, title: "Checks", sfSymbol: "magnifyingglass.circle"),
        RailPhase(phase: .fix, title: "Fix", sfSymbol: "wrench.and.screwdriver"),
        RailPhase(phase: .verify, title: "Verify", sfSymbol: "checkmark.circle"),
        RailPhase(phase: .export, title: "Export", sfSymbol: "square.and.arrow.up.circle")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, railPhase in
                HStack(spacing: 8) {
                    phaseIcon(for: railPhase)
                    Text(railPhase.title)
                        .font(.caption)
                        .foregroundStyle(foregroundColor(for: railPhase))
                }
                .padding(.vertical, 6)
                if index < phases.count - 1 {
                    Rectangle()
                        .fill(connectorColor(for: railPhase))
                        .frame(width: 2, height: 16)
                        .padding(.leading, 10)
                }
            }
        }
        .padding()
    }
}
```

### Anti-Patterns to Avoid
- **Building a parallel diagnostics system:** The engine MUST delegate to existing `CrashClassifier`, `AudioProbe`, `GPUDetection`, etc. Check implementations are thin wrappers, not reimplementations.
- **Hardcoding flow logic in Swift:** Branching logic lives in JSON (`on` map per node). Swift code interprets the graph; it does not encode category-specific branching. Exception: check implementations themselves are Swift code.
- **Unbounded session files:** Auto-save writes one plist per bottle. Stale sessions expire after 14 days. History is capped at 20 entries or 30 days.
- **Modal navigation for deep links:** Config/Logs deep links open as sub-sheets (`.sheet`) that return to the same wizard step. Do not use NavigationLink pushing to a different NavigationStack.
- **Silent fix application:** Every fix requires explicit "Apply fix" click. High-impact actions (winetricks, restart, kill) get a confirmation alert before the sheet dismisses. No auto-apply.
- **Re-numbering past steps:** When branching changes future steps, past step numbers stay stable. Only future step counts change. Show "Why path changed" explanation.
- **Coupling engine to SwiftUI:** `TroubleshootingFlowEngine` lives in WhiskyKit with no SwiftUI imports. It publishes state via `@Published` properties. The view layer observes and renders.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Crash log analysis | New log scanner | Existing `CrashClassifier` + `PatternLoader` | Already handles pattern matching, prefilters, confidence scoring, category grouping |
| Audio device probing | New CoreAudio wrapper | Existing `AudioDeviceMonitor` + `CoreAudioDeviceProbe` | Already handles device enumeration, transport type, sample rate, change listeners |
| Audio registry probing | Direct registry file parsing | Existing `WineRegistryAudioProbe` + `Wine.readAudioDriver` | Already wraps `wine reg query` with proper error handling |
| Graphics config checking | Custom settings reader | Existing `GraphicsBackendResolver` + `BottleGraphicsConfig` | Already resolves `.recommended`, integrates with EnvironmentBuilder |
| Dependency detection | Manual DLL file scanning | Existing `Winetricks.loadInstalledVerbs` + `WinetricksVerbCache` | Cache-aware, handles both `list-installed` and log parsing fallback |
| Game config matching | Custom exe matching | Existing `GameMatcher` with tiered scoring | Already handles Steam App ID, PE fingerprint, fuzzy name matching |
| Fix application | Direct settings mutation | Existing `BottleSettings` didSet auto-save + `ProgramOverrides` | Settings persist automatically on property set; EnvironmentBuilder resolves at launch |
| Export/escalation | New export system | Existing `DiagnosticExporter` + `Redactor` | ZIP export with privacy controls, Markdown copy, system info collection all built |
| Session persistence | Custom file format | `PropertyListEncoder`/`PropertyListDecoder` | Matches `DiagnosisHistory`, `RemediationTimeline`, `GameConfigSnapshot` patterns exactly |
| Toast/banner UI | Custom notification view | Existing `StatusToast` + `ToastModifier` + `ToastData` | Already handles success/error/info/launcherFixes styles with auto-dismiss |
| Remediation display | New fix card UI | Existing `RemediationCardView` | Already has confidence badges, action buttons, confirmation alerts, undo path, "Why" section |

**Key insight:** Phase 10 is fundamentally an orchestration layer. The diagnostic intelligence already exists in Phases 5-7; the settings mutation infrastructure exists in Phases 2-4. Phase 10's genuinely new work is: (1) the JSON flow schema and loader, (2) the generalized state machine, (3) the check registry binding, (4) the wizard UI with progress rail, (5) session persistence, and (6) entry point integration. Every check implementation is a thin wrapper (5-30 lines) around an existing function call.

## Common Pitfalls

### Pitfall 1: Flow JSON Schema Breaking Changes
**What goes wrong:** A JSON schema update adds required fields or changes node semantics. Older bundled flows fail to decode, crashing the app.
**Why it happens:** JSON schema evolution without versioning or defensive decoding.
**How to avoid:** Include `version` field in every JSON file. Use `decodeIfPresent` for all optional fields (following `BottleSettings.init(from:)` pattern). Never remove or rename existing fields. New fields default to safe values. Validate flow JSON at load time with `PatternLoader`-style fail-fast-in-debug, soft-fail-in-release.
**Warning signs:** App crash on launch after updating flow JSON.

### Pitfall 2: Check Implementation Blocking Main Thread
**What goes wrong:** A heavy check (CrashClassifier on a 20 MiB log, WineAudioTestProbe launching an exe) runs synchronously, freezing the wizard UI.
**Why it happens:** Checks that launch Wine processes or scan large files take 1-10 seconds.
**How to avoid:** All check execution happens via `Task` in the engine. The `isRunningCheck` published property drives a progress indicator in the UI. Individual checks that launch Wine processes (`Wine.runProgram`, `Wine.queryRegistryKey`) are already async. The `CrashClassifier` is `Sendable` and should run on `Task.detached(priority: .utility)` for large logs.
**Warning signs:** UI hang during "Running checks" phase.

### Pitfall 3: Session File Corruption on Crash
**What goes wrong:** The app crashes mid-autosave, leaving a corrupted plist. On next launch, session load fails silently and the user loses their troubleshooting progress.
**Why it happens:** `PropertyListEncoder.encode()` followed by `Data.write()` is not atomic.
**How to avoid:** Write to a temporary file first, then atomically rename. Use `data.write(to: url, options: .atomic)` which writes to a temp file and renames. If decode fails, log the error and return nil (start fresh) rather than crashing. This matches the existing `DiagnosisHistory.load(from:)` pattern which returns empty on failure.
**Warning signs:** "Resume troubleshooting" showing stale or missing state.

### Pitfall 4: Infinite Loop in Flow Graph
**What goes wrong:** A flow JSON has a circular reference: node A branches to node B, which branches back to A. The engine loops forever.
**Why it happens:** Manual JSON authoring error. No cycle detection.
**How to avoid:** Add a step counter to the engine. If the engine processes more than 50 nodes in a single session without user interaction, break and escalate. Log the cycle detection warning. In debug builds, add a flow validator that checks for cycles at load time.
**Warning signs:** Wizard spinning indefinitely on "Running checks" without advancing.

### Pitfall 5: Stale Preflight Data After Fix Application
**What goes wrong:** A fix changes a setting (e.g., graphics backend). The next check reads preflight data that was collected before the fix, seeing the old value. The check reports "already configured" incorrectly.
**Why it happens:** Preflight data is collected once at session start for performance, but fixes mutate the underlying state.
**How to avoid:** After each fix application, invalidate specific preflight fields that the fix could have changed. The engine should re-collect affected preflight data before running the verification check. Keep the "cheap" preflight (bottle identity, launcher type) stable, but mark "mutable" preflight fields (settings, registry values, running processes) as requiring refresh.
**Warning signs:** Verification check after fix reports success when the fix did not actually take effect.

### Pitfall 6: Fragment Reference Resolution Failure
**What goes wrong:** A flow node references `fragmentRef: "dependency-install"` but the fragment JSON file is missing or the node ID within the fragment does not exist. The engine hits a dead end.
**Why it happens:** Fragment files are separately authored and may have naming mismatches.
**How to avoid:** Validate all fragment references at flow load time. In debug builds, assert that every `fragmentRef` resolves to an existing fragment with a valid entry node. In release builds, fall back to escalation if a fragment cannot be resolved.
**Warning signs:** "Step not found" error during troubleshooting flow.

### Pitfall 7: Fix Undo Not Available for All Actions
**What goes wrong:** User expects to undo a winetricks installation or a Wine prefix restart, but these are non-reversible. User confusion leads to support requests.
**Why it happens:** Not all fix actions are reversible. Settings changes are; winetricks installs and process management are not.
**How to avoid:** Per the locked decisions: clearly label non-reversible actions in the fix preview. Show "This action cannot be undone" prominently for high-impact fixes. The `isReversible` field on `FlowStepNode` controls whether the undo button appears post-application. Undo for settings changes restores the `beforeValue` from the `FixAttempt` record.
**Warning signs:** User clicking "Undo" on a winetricks install and nothing happening.

## Code Examples

### Flow JSON Example (graphics.json)
```json
{
  "version": 1,
  "categoryId": "graphics",
  "entryNodeId": "check_backend",
  "nodes": {
    "check_backend": {
      "id": "check_backend",
      "type": "check",
      "phase": "checks",
      "title": "Check graphics backend",
      "description": "Verifying your current graphics translation layer",
      "checkId": "graphics.backend_is",
      "params": { "expected": "dxvk", "scope": "program_or_bottle" },
      "on": {
        "pass": "check_crash_log",
        "already_configured": "check_crash_log",
        "fail": "fix_enable_dxvk",
        "unknown": "manual_review",
        "error": "collect_diagnostics"
      },
      "evidenceMap": {
        "current": "Current backend",
        "expected": "Expected backend"
      }
    },
    "fix_enable_dxvk": {
      "id": "fix_enable_dxvk",
      "type": "fix",
      "phase": "fix",
      "title": "Switch to DXVK",
      "description": "DXVK may provide better compatibility for this type of issue",
      "fixId": "switch-backend",
      "fixPreview": {
        "settingName": "Graphics Backend",
        "currentValueKey": "current",
        "newValue": "dxvk",
        "scope": "bottle"
      },
      "isReversible": true,
      "requiresConfirmation": false,
      "on": {
        "applied": "verify_fix",
        "skipped": "check_crash_log"
      }
    },
    "verify_fix": {
      "id": "verify_fix",
      "type": "verify",
      "phase": "verify",
      "title": "Did this fix the problem?",
      "on": {
        "yes": "resolved",
        "no": "check_crash_log"
      }
    },
    "check_crash_log": {
      "id": "check_crash_log",
      "type": "check",
      "phase": "checks",
      "title": "Analyze crash log",
      "checkId": "crash.log_classify",
      "params": {},
      "on": {
        "pass": "check_dependencies",
        "fail": "show_crash_findings",
        "unknown": "check_dependencies",
        "error": "collect_diagnostics"
      }
    },
    "resolved": {
      "id": "resolved",
      "type": "info",
      "phase": "export",
      "title": "Problem resolved",
      "description": "The issue has been fixed. You can export a session report for your records."
    },
    "collect_diagnostics": {
      "id": "collect_diagnostics",
      "type": "info",
      "phase": "export",
      "title": "Export diagnostics",
      "description": "We could not resolve this automatically. Export a diagnostic report for further analysis.",
      "fragmentRef": "export-escalation"
    }
  }
}
```

### Index JSON Example (index.json)
```json
{
  "version": 1,
  "categories": [
    {
      "id": "launch-crash",
      "title": "Won't launch / crashes immediately",
      "sfSymbol": "xmark.app",
      "flowFile": "launch-crash.json",
      "depth": "deep",
      "description": "Program fails to start or crashes within seconds of launching"
    },
    {
      "id": "launcher-issues",
      "title": "Launcher issues",
      "sfSymbol": "app.badge.checkmark",
      "flowFile": "launcher-issues.json",
      "depth": "deep",
      "description": "Problems with Steam, EA App, Epic Games, or Rockstar launchers"
    },
    {
      "id": "graphics",
      "title": "Graphics problems",
      "sfSymbol": "display.trianglebadge.exclamationmark",
      "flowFile": "graphics.json",
      "depth": "deep",
      "description": "Black screen, flickering, visual artifacts, or low frame rate"
    },
    {
      "id": "audio",
      "title": "Audio problems",
      "sfSymbol": "speaker.slash",
      "flowFile": "audio.json",
      "depth": "deep",
      "description": "No sound, crackling, popping, or wrong output device"
    },
    {
      "id": "controller-input",
      "title": "Controller / input problems",
      "sfSymbol": "gamecontroller",
      "flowFile": "controller-input.json",
      "depth": "shallow",
      "description": "Controller not detected or buttons mapped incorrectly"
    },
    {
      "id": "install-dependencies",
      "title": "Install / dependency problems",
      "sfSymbol": "shippingbox",
      "flowFile": "install-dependencies.json",
      "depth": "deep",
      "description": "Missing .NET, VC++, DirectX, or Winetricks components"
    },
    {
      "id": "network-download",
      "title": "Network / download problems",
      "sfSymbol": "wifi.exclamationmark",
      "flowFile": "network-download.json",
      "depth": "deep",
      "description": "Download timeouts, Steam stalls, or connection failures"
    },
    {
      "id": "performance-stability",
      "title": "Performance / stability over time",
      "sfSymbol": "chart.line.downtrend.xyaxis",
      "flowFile": "performance-stability.json",
      "depth": "shallow",
      "description": "Stuttering, frame drops, or hangs after playing for a while"
    }
  ]
}
```

### PreflightCollector Example
```swift
// PreflightCollector.swift
public struct PreflightData: Codable, Sendable {
    public var bottleURL: URL
    public var bottleName: String
    public var programURL: URL?
    public var programName: String?
    public var launcherType: String?          // LauncherType raw value if detected
    public var isWineserverRunning: Bool
    public var processCount: Int
    public var recentLogURL: URL?
    public var lastExitCode: Int32?
    public var audioDeviceName: String?
    public var audioTransportType: String?
    public var graphicsBackend: String         // Resolved backend
    public var collectedAt: Date
}

public enum PreflightCollector {
    @MainActor
    public static func collect(bottle: Bottle, program: Program?) async -> PreflightData {
        let isRunning = await Wine.isWineserverRunning(for: bottle)
        let processCount = ProcessRegistry.shared.getProcessCount(for: bottle)
        let resolvedBackend = bottle.settings.graphicsBackend == .recommended
            ? GraphicsBackendResolver.resolve()
            : bottle.settings.graphicsBackend

        return PreflightData(
            bottleURL: bottle.url,
            bottleName: bottle.settings.name,
            programURL: program?.url,
            programName: program?.name,
            launcherType: program.flatMap { LauncherDetection.detectLauncher(for: $0)?.rawValue },
            isWineserverRunning: isRunning,
            processCount: processCount,
            recentLogURL: findRecentLog(for: bottle, program: program),
            lastExitCode: program?.settings.lastExitCode,
            audioDeviceName: AudioDeviceMonitor().defaultOutputDevice()?.name,
            audioTransportType: AudioDeviceMonitor().defaultOutputDevice()?.transportType.displayName,
            graphicsBackend: resolvedBackend.rawValue,
            collectedAt: Date()
        )
    }
}
```

### Entry Point Integration
```swift
// In ProgramView.swift - Primary entry point
Button("Troubleshoot\u{2026}") {
    showTroubleshootingWizard = true
}
.sheet(isPresented: $showTroubleshootingWizard) {
    TroubleshootingWizardView(
        bottle: program.bottle,
        program: program,
        entryContext: .program(program)
    )
}

// In WhiskyApp.swift - Launch failure banner trigger
.onReceive(NotificationCenter.default.publisher(for: .crashDiagnosisAvailable)) { notification in
    if let diagnosis = notification.userInfo?["diagnosis"] as? CrashDiagnosis,
       diagnosis.primaryConfidence == .high {
        crashDiagnosisBanner = CrashDiagnosisBannerState(
            diagnosis: diagnosis,
            showTroubleshootAction: true  // "Troubleshoot" button in banner
        )
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Domain-specific hardcoded wizard (AudioTroubleshootingEngine) | JSON-driven generalized flow engine | Phase 10 (this work) | All categories share one engine; new flows added without Swift changes |
| Per-domain symptom enums (AudioSymptom) | Unified SymptomCategory with 8 categories + Other | Phase 10 (this work) | Single entry point, consistent UX across all issue types |
| Ad-hoc probe execution | CheckRegistry with stable IDs and normalized results | Phase 10 (this work) | Decouples check implementation from flow definition; enables JSON-driven branching |
| No session persistence | Auto-saved resumable sessions with staleness detection | Phase 10 (this work) | Users can pause and resume troubleshooting across app restarts |
| Scattered entry points (audio wizard in Audio panel, diagnostics in crash view) | Unified "Troubleshoot..." entry with context-aware start depth | Phase 10 (this work) | One wizard system with multiple entry depths |

**Deprecated/outdated:**
- `AudioTroubleshootingEngine` will NOT be deprecated. The audio-specific wizard continues to serve the Audio Config section for quick audio-only troubleshooting. The new `TroubleshootingFlowEngine` handles the unified cross-category flows. Audio flows in the new engine delegate to the same `AudioProbe` implementations.
- The Phase 6 `AudioTroubleshootingWizardView` continues to work for its current purpose. The new wizard is an additional, broader system.

## Open Questions

1. **Audio flow migration strategy**
   - What we know: Phase 6 built `AudioTroubleshootingEngine` with hardcoded fix orderings per `AudioSymptom`. Phase 10's audio flow JSON will replicate this logic. Both engines share the same probe implementations.
   - What's unclear: Whether the Phase 6 audio wizard should be replaced by the Phase 10 wizard for audio issues, or coexist as a quick-access shortcut from the Audio Config section.
   - Recommendation: Coexist initially. The Phase 6 audio wizard stays in the Audio Config section for quick access. The Phase 10 wizard's "Audio problems" category provides a deeper, more structured flow. Future work can unify if desired. The critical point is that both use the same `AudioProbe` implementations.

2. **Check ID stability and versioning**
   - What we know: Check IDs are referenced in JSON flow files. If a check ID changes, flows break.
   - What's unclear: Whether check IDs need explicit versioning (e.g., `graphics.backend_is.v1`) or if stable naming conventions suffice.
   - Recommendation: Use stable dot-namespaced IDs without version suffixes (e.g., `graphics.backend_is`, `crash.log_classify`). If a check's interface changes incompatibly, create a new ID (e.g., `graphics.backend_check_v2`) and update flow JSON. The old ID can remain in the registry as a compatibility shim. This matches the approach used for `patterns.json` pattern IDs and `remediations.json` action IDs.

3. **Concurrency model for check execution**
   - What we know: The engine is `@MainActor` (matching `AudioTroubleshootingEngine`). Checks that launch Wine processes are async and can take seconds.
   - What's unclear: Whether multiple checks should run in parallel (e.g., preflight collecting audio + graphics + process state simultaneously) or strictly sequentially.
   - Recommendation: Run preflight collection in parallel (all probes are independent). Run flow-step checks sequentially (the flow graph is inherently sequential -- each step's outcome determines the next). The engine dispatches each check as a `Task` and awaits its result before branching.

4. **Flow JSON validation tooling**
   - What we know: Flow JSON is hand-authored. Errors (dangling node references, missing fragment refs, cycles) would cause runtime failures.
   - What's unclear: Whether a separate validation tool or just debug-mode assertions are sufficient.
   - Recommendation: Add a `FlowValidator` in WhiskyKit that checks for: (a) all `on` target node IDs resolve, (b) all `fragmentRef` values resolve, (c) no unreachable nodes, (d) no cycles longer than 3 hops without a user interaction step. Run in debug builds at flow load time. This catches authoring errors early without requiring a separate tool.

5. **"Since you left" staleness check granularity**
   - What we know: On session resume, lightweight probes should re-run to detect changes since the session was paused.
   - What's unclear: Which probes qualify as "lightweight" and should re-run vs. which are too expensive.
   - Recommendation: Preflight data (running process count, audio device, graphics backend setting) is cheap to re-collect. CrashClassifier re-runs are expensive. On resume, re-collect preflight data and compare with the stored snapshot. If any preflight field changed, show "Since you left: [what changed]" banner. Do NOT re-run heavy checks unless the user explicitly requests it or the changed preflight field directly affects a previously-run check.

6. **Proactive suggestion rate limiting**
   - What we know: Strong failure signals (launch failure, high-confidence crash match) trigger a toast/banner suggesting troubleshooting. Must be rate-limited per bottle/program/session.
   - What's unclear: Exact rate limiting parameters.
   - Recommendation: Store a `lastTroubleshootingSuggestionAt` timestamp per program in `ProgramSettings`. Show the suggestion at most once per 30 minutes per program. If the user dismisses or completes a troubleshooting session, suppress suggestions for that program for 2 hours. Use the existing `ProgramSettings` persistence for this.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** -- Direct reading of all files listed below, verified against current branch `issue-50-miscellaneous-fixes`:
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/CrashClassifier.swift` -- Classification pipeline, pattern matching, confidence scoring
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/RemediationAction.swift` -- Fix card model with ActionType, RiskLevel
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/ConfidenceTier.swift` -- 3-tier confidence model
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosisHistory.swift` -- Bounded history with plist persistence
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/RemediationTimeline.swift` -- Fix attempt tracking with plist persistence
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/DiagnosticExporter.swift` -- ZIP and Markdown export pipeline
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/PatternLoader.swift` -- JSON resource loading pattern
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/Redactor.swift` -- Privacy redaction for export
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/WineDebugPreset.swift` -- WINEDEBUG preset enum
  - `WhiskyKit/Sources/WhiskyKit/Audio/AudioTroubleshootingEngine.swift` -- Existing wizard state machine (direct template)
  - `WhiskyKit/Sources/WhiskyKit/Audio/AudioProbe.swift` -- Probe protocol + CoreAudioDeviceProbe + WineRegistryAudioProbe
  - `WhiskyKit/Sources/WhiskyKit/Audio/AudioProbeResult.swift` -- ProbeStatus enum, structured result
  - `WhiskyKit/Sources/WhiskyKit/Audio/AudioFinding.swift` -- Finding model with confidence
  - `WhiskyKit/Sources/WhiskyKit/Audio/AudioTroubleshootingStep.swift` -- AudioSymptom, TroubleshootingFixAttempt
  - `WhiskyKit/Sources/WhiskyKit/Audio/AudioDeviceMonitor.swift` -- CoreAudio device monitoring
  - `WhiskyKit/Sources/WhiskyKit/Wine/GraphicsBackendResolver.swift` -- Backend resolution
  - `WhiskyKit/Sources/WhiskyKit/Wine/GPUDetection.swift` -- GPU capability detection
  - `WhiskyKit/Sources/WhiskyKit/Wine/WineAudioRegistry.swift` -- Audio registry helpers
  - `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameMatcher.swift` -- Game matching with tiered scoring
  - `WhiskyKit/Sources/WhiskyKit/GameDatabase/GameDBLoader.swift` -- JSON resource loading
  - `WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift` -- Process tracking
  - `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift` -- Settings model with auto-save
  - `WhiskyKit/Sources/WhiskyKit/Whisky/ProgramOverrides.swift` -- Per-program override model
  - `WhiskyKit/Sources/WhiskyKit/Wine/EnvironmentBuilder.swift` -- 8-layer env var cascade
  - `Whisky/Views/Audio/AudioTroubleshootingWizardView.swift` -- Existing wizard UI (direct template)
  - `Whisky/Views/Diagnostics/RemediationCardView.swift` -- Fix card UI with confidence badges
  - `Whisky/Views/Diagnostics/DiagnosticsView.swift` -- Split layout diagnostics view
  - `Whisky/Views/Common/StatusToast.swift` -- Toast/banner system
  - `Whisky/Views/Bottle/BottleView.swift` -- Navigation structure, BottleStage enum
  - `Whisky/Views/Programs/ProgramView.swift` -- Program view structure
  - `Whisky/Views/WhiskyApp.swift` -- App entry point, crash diagnosis banner, audio monitoring
  - `WhiskyKit/Package.swift` -- Swift 6, macOS 15+, SPM resources configuration
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/patterns.json` -- Crash pattern definitions
  - `WhiskyKit/Sources/WhiskyKit/Diagnostics/Resources/remediations.json` -- Remediation action definitions

### Secondary (MEDIUM confidence)
- Phase 5 research (`05-RESEARCH.md`) -- Wine log format, WINEDEBUG syntax, classifier pipeline design
- Phase 6 research (`06-RESEARCH.md`) -- CoreAudio API patterns, Wine audio architecture, troubleshooting wizard design
- Phase 4 research (`04-RESEARCH.md`) -- Graphics backend model, EnvironmentBuilder integration, backend-conditional env var emission
- Phase 7 research (`07-RESEARCH.md`) -- Game database schema, matching algorithm, settings application/undo

### Tertiary (LOW confidence)
- Specific flow JSON content for controller/input, network/download, and performance/stability categories -- these are lighter flows with fewer deep diagnostic primitives available. The exact check implementations and branching for these categories will need to be designed during planning, drawing on general Wine troubleshooting knowledge rather than specific codebase primitives.
- Proactive suggestion trigger heuristics -- the exact failure signal thresholds (what qualifies as "strong" vs "low-confidence") need empirical tuning.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- No new dependencies; entirely Foundation + SwiftUI, proven SPM resource pattern
- Architecture: HIGH -- Direct generalization of proven `AudioTroubleshootingEngine` pattern with `CheckRegistry` binding to existing diagnostics
- JSON schema design: HIGH -- Follows established `patterns.json` and `GameDB.json` patterns with defensive Codable decoding
- Check implementations: HIGH -- Every check wraps a function call that already exists and works (CrashClassifier, AudioProbes, GPUDetection, etc.)
- Wizard UI: HIGH -- Follows established `AudioTroubleshootingWizardView` pattern with additions (progress rail, step cards, session persistence)
- Flow content authoring: MEDIUM -- Deep flows (crash, graphics, audio, dependencies) have strong diagnostic primitive support; lighter flows (controller, performance) have fewer automated checks available
- Proactive suggestion triggers: LOW -- Exact heuristics need empirical tuning with real usage data
- Pitfalls: HIGH -- Identified from direct codebase analysis and architectural understanding of the engine-flow-check interaction

**Research date:** 2026-02-11
**Valid until:** 2026-03-13 (30 days -- stable domain, all underlying infrastructure already built and tested)
