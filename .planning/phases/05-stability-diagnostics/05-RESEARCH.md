# Phase 5: Stability & Diagnostics - Research

**Researched:** 2026-02-09
**Domain:** Wine error output classification, crash diagnostics, log analysis, export packaging
**Confidence:** HIGH

## Summary

Phase 5 transforms Whisky from a "launch and hope" experience into one where users receive structured, actionable crash guidance. The core technical challenge is building a regex-based classifier that scans Wine's stderr/stdout output (which follows a well-documented `TTTT:class:channel:function message` format) against a versioned pattern database, produces a confidence-scored diagnosis, and presents remediation cards with direct action buttons.

The codebase already has the infrastructure this phase needs: `ProcessOutput` delivers line-by-line stdout/stderr via `AsyncStream`, `Wine.makeFileHandle()` writes complete logs to `~/Library/Logs/`, `StabilityDiagnostics` and `WinePrefixDiagnostics` provide diagnostic report generation patterns, `EnvironmentBuilder` with `EnvironmentProvenance` gives full environment introspection, and `ProgramSettings`/`ProgramOverrides` show the established pattern for per-program sidecar data. The classifier pipeline, pattern storage, diagnosis persistence, remediation action system, WINEDEBUG presets, and diagnostic ZIP export are all net-new code that builds cleanly atop these foundations.

**Primary recommendation:** Build the classifier as a pure-logic pipeline in WhiskyKit (`Diagnostics/` module) with no UI dependencies, loaded from a versioned `patterns.json` resource. Keep the UI layer in the Whisky app target. Use Swift's native `Regex` type with compiled patterns cached at load time for performance. Use `FileWrapper`-based ZIP creation to avoid adding external dependencies.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Crash guidance presentation
- Summary-first layout: diagnosis summary at top, then remediation cards, then collapsible raw log (collapsed by default)
- Split view on desktop if space allows: suggestions (left, fixed) + log output (right, scrollable)
- Remediation cards are actionable with guardrails:
  - Low-risk reversible changes get direct action buttons (e.g., "Enable DXVK", "Force D3D11")
  - Higher-risk/stateful actions get guided paths with confirmation (e.g., "Install vcrun2019" opens Winetricks with verb selected)
- Every remediation card includes: "What will change" (one sentence), "Undo" path, "Applies next launch" note when relevant
- Auto-trigger classification when Wine process exits non-zero, Whisky force-stops a process, or end-of-log scan finds crash signatures
- On-demand "Analyze latest log" / "Analyze last run" buttons for everything else
- 3-tier confidence model: High (signature match), Medium (multiple signals), Low (heuristic/single weak signal)
- Show confidence label + expandable "Why" line per diagnosis
- Sort remediation cards by confidence and impact; hide low-confidence behind "Other things to try"
- Internal numeric score (0-1) mapped to tiers; raw numbers never shown to users

#### Error classification display
- Minimal inline log tagging: background tint + left gutter marker for strong matches only (Error, Warning, Crash signature, Graphics)
- Don't color every Wine "fixme" — keep raw log readable
- Filter buttons above log: Show all / Only tagged / Crash-related, plus search box
- Summary shows primary headline diagnosis (highest severity + confidence) at top
- Compact category counts below headline, each clickable to filter log (e.g., "DLL load failures: 3")
- Persist last diagnosis summary per program (small sidecar JSON/plist, last 5 per program/bottle):
  - Fields: timestamp, bottle/program ID, log file ref, primary category, confidence tier, top 1-3 signatures, remediation card IDs
  - UI: "Last crash diagnosis" panel in Program settings with "View details" and "Re-analyze"
  - "Clear diagnostics history" action for privacy

#### Diagnostic report export
- ZIP export: `Whisky-Diagnostics-<bottle>-<program>-<YYYYMMDD-HHMMSS>.zip` containing:
  - `report.md` — human-readable summary (what happened, classification, confidence, suggested fixes, steps tried)
  - `crash.json` — categories, matched signatures, confidence scores
  - `env.json` — resolved environment with provenance, sensitive values redacted
  - `bottle-settings.plist` and `program-settings.plist` (or JSON equivalents)
  - `wine.log` (full) and/or `wine.tail.log` (last N lines)
  - `system.json` — macOS version, model, CPU/GPU, Whisky/Wine versions
- Also offer "Copy report" as single Markdown/plain-text block for pasting into GitHub issues
- Auto-track Whisky-initiated remediation actions as a timeline (last 10 per bottle/program) with timestamps and before/after values
- Export dialog checkbox: "Don't include remediation history" for privacy
- Redact by default: home paths (`/Users/<name>` -> `/Users/<redacted>`), env vars matching `*TOKEN*`, `*KEY*`, `*SECRET*`, `PASSWORD`, `AUTH`
- Export dialog checkbox: "Include sensitive details (recommended only when sharing privately)"
- Don't dump full registry by default; include only targeted keys relevant to detected issue, still redacted
- Entry points: Diagnostics view (primary), Log viewer toolbar, Program settings ("Diagnostics" section), Bottle settings, Help menu (asks user to pick bottle/program)

#### Pattern coverage priorities
- First wave: DLL load failures + access violations/unhandled exceptions (high-frequency, high-signal, concrete remediation)
- Second wave: GPU/device-lost heuristics (noisier, backend-specific, better after classifier pipeline is solid)
- Full taxonomy (7 category groups):
  - **Core crash/fatal:** Access violation / unhandled exception (page fault, c0000005); Process termination / non-zero exit
  - **Graphics:** GPU timeout / device removed / hung (D3DMetal/DXVK device lost, Metal validation); Backend incompatibility (DX12 path issues, swapchain failures)
  - **Dependencies/loading:** DLL load failure (vcruntime, msvcp, d3dcompiler, api-ms-win-*); .NET/CLR issues (mscoree, mscorlib, fusion); DirectX redistributable missing (d3dx9, xinput, xaudio2)
  - **Prefix/filesystem:** Prefix corruption / missing user dirs; Path / permission errors
  - **Networking/launchers:** TLS/SSL / HTTP timeouts (WinHTTP, cert failures)
  - **Anti-cheat/unsupported:** EAC/BattlEye signatures -> definitive "not supported on macOS" message with helpful next steps (offline mode, compatibility notes, export diagnostics), no fix buttons, high-confidence signature match only
  - **Other/Unknown:** Low-confidence suggestions (open logs, try different backend)
- Pattern storage: versioned JSON resource (`patterns.json`) with thin Swift loader
  - Schema per pattern: id (stable), category, severity, confidence, regex (or substring prefilter), tags, captureGroups (optional), remediationActionIds (optional)
  - Load/validate at startup (fail fast in debug, soft-fail in release)
  - Remediation action definitions separate from pattern definitions
  - Unit test fixtures with sample log lines for every rule (positive match test required per pattern)
- WINEDEBUG management: opt-in "Re-run with enhanced logging" per-program action, not a new default
  - Current default (`WINEDEBUG=fixme-all`) preserved for normal runs
  - Curated presets: Crash (`+seh,+tid,+pid,+timestamp`), DLL/load (`+loaddll,+module,+tid,+pid`), Verbose (advanced, labeled as noisy)
  - Record active WINEDEBUG preset in crash diagnosis + exported report

### Claude's Discretion
- Exact split view breakpoint threshold
- Loading/parsing performance optimization approach
- Internal data structures for the classifier pipeline
- Log viewer scrolling and virtualization implementation
- Exact gutter marker icon choices

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation `Regex` | Swift 5.7+ (macOS 15+) | Pattern matching for log lines | Native, type-safe, compile-time checked; already targeting macOS 15 |
| Foundation `JSONDecoder` | Built-in | Parse `patterns.json` and diagnosis persistence | No external dependency needed for JSON |
| Foundation `PropertyListEncoder` | Built-in | Per-program diagnosis sidecar persistence | Matches existing `ProgramSettings` pattern |
| `FileWrapper` | Built-in | Create ZIP archive for diagnostic export | Avoids adding third-party ZIP dependency |
| SwiftUI | macOS 15+ | Diagnostics views, log viewer, remediation cards | Existing UI framework for the project |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.log` Logger | Built-in | Internal diagnostics logging | For classifier pipeline debug output |
| `NSTextView` via `NSViewRepresentable` | AppKit | Log viewer with large text performance | Only if SwiftUI `Text`/`ScrollView` proves too slow for log rendering |
| ZIPFoundation | 0.9.19+ | ZIP archive creation | Only if `FileWrapper`-based approach proves insufficient |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift `Regex` | `NSRegularExpression` | `NSRegularExpression` is faster for some patterns but lacks type safety and compile-time checking. Swift `Regex` is native, safer, and sufficient at macOS 15 |
| `FileWrapper` ZIP | ZIPFoundation | ZIPFoundation is more featureful, but `FileWrapper` avoids adding a dependency to WhiskyKit's Package.swift. If `FileWrapper` ZIP proves flaky, ZIPFoundation is the fallback |
| JSON for patterns | Swift code/enum | JSON is updatable without recompiling; Swift enums would be faster but patterns need to be iterable and extensible by users in future |

**Installation:** No new dependencies required. The entire phase can be built with Foundation and SwiftUI.

## Architecture Patterns

### Recommended Project Structure
```
WhiskyKit/Sources/WhiskyKit/
├── Diagnostics/                    # NEW: Core classifier and data types
│   ├── CrashPattern.swift          # Pattern model decoded from JSON
│   ├── CrashCategory.swift         # 7-group category enum
│   ├── ConfidenceTier.swift        # High/Medium/Low with numeric score
│   ├── CrashDiagnosis.swift        # Result of classification
│   ├── DiagnosisMatch.swift        # Single matched pattern with line refs
│   ├── RemediationAction.swift     # Action definition (id, type, params)
│   ├── CrashClassifier.swift       # Pipeline: load patterns, scan log, score
│   ├── PatternLoader.swift         # JSON loader with validation
│   ├── DiagnosisHistory.swift      # Per-program persistence (last 5)
│   ├── WineDebugPreset.swift       # WINEDEBUG preset enum
│   ├── RemediationTimeline.swift   # Tracks remediation actions taken
│   └── DiagnosticExporter.swift    # ZIP and Markdown export
├── Diagnostics/Resources/          # NEW: Pattern data
│   ├── patterns.json               # Versioned pattern database
│   └── remediations.json           # Remediation action definitions
└── (existing modules unchanged)

Whisky/Views/
├── Diagnostics/                    # NEW: UI for diagnostics
│   ├── DiagnosticsView.swift       # Main diagnostics view (summary-first)
│   ├── RemediationCardView.swift   # Single remediation card
│   ├── LogViewerView.swift         # Log viewer with tagging/filtering
│   ├── DiagnosticExportSheet.swift # Export dialog with privacy controls
│   └── DiagnosisHistoryView.swift  # Per-program diagnosis history
└── (existing views unchanged)
```

### Pattern 1: Classifier Pipeline (Pure Logic in WhiskyKit)
**What:** A stateless function that takes log text (or lines) and pattern definitions, returns a scored `CrashDiagnosis`.
**When to use:** Every time a Wine process exits non-zero, is force-stopped, or user clicks "Analyze".
**Example:**
```swift
// CrashClassifier.swift
public struct CrashClassifier: Sendable {
    private let patterns: [CrashPattern]
    private let remediations: [String: RemediationAction]

    public init(patterns: [CrashPattern], remediations: [String: RemediationAction]) {
        self.patterns = patterns
        self.remediations = remediations
    }

    public func classify(log: String, exitCode: Int32?) -> CrashDiagnosis {
        var matches: [DiagnosisMatch] = []

        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        for (lineIndex, line) in lines.enumerated() {
            for pattern in patterns {
                if let match = pattern.match(line: String(line)) {
                    matches.append(DiagnosisMatch(
                        pattern: pattern,
                        lineIndex: lineIndex,
                        captures: match.captures
                    ))
                }
            }
        }

        return CrashDiagnosis(
            matches: matches,
            exitCode: exitCode,
            remediations: remediations
        )
    }
}
```

### Pattern 2: Pattern Definition with Prefilter (Performance)
**What:** Each pattern has an optional substring prefilter checked before the regex. Skip regex for lines that cannot possibly match.
**When to use:** For patterns where a fast `String.contains()` check avoids expensive regex evaluation.
**Example:**
```swift
// CrashPattern.swift
public struct CrashPattern: Codable, Sendable, Identifiable {
    public let id: String
    public let category: CrashCategory
    public let severity: PatternSeverity
    public let confidence: Double  // 0.0-1.0
    public let substringPrefilter: String?  // Fast check before regex
    public let regex: String
    public let tags: [String]
    public let captureGroups: [String]?
    public let remediationActionIds: [String]?

    // Compiled regex, cached after first use
    @CodableIgnored
    var compiledRegex: Regex<AnyRegexOutput>?

    public func match(line: String) -> PatternMatch? {
        // Fast path: substring prefilter
        if let prefilter = substringPrefilter,
           !line.contains(prefilter) {
            return nil
        }
        // Lazy-compile regex on first use
        guard let regex = try? Regex(regex) else { return nil }
        guard let result = try? regex.firstMatch(in: line) else { return nil }
        return PatternMatch(captures: extractCaptures(from: result))
    }
}
```

### Pattern 3: Diagnosis Persistence as Sidecar (Existing Pattern)
**What:** Store diagnosis history alongside `ProgramSettings` as a small JSON/plist file with bounded size.
**When to use:** After every classification run, persist the summary so "Last crash diagnosis" UI can show it.
**Example:**
```swift
// DiagnosisHistory.swift
public struct DiagnosisHistoryEntry: Codable, Sendable {
    public let timestamp: Date
    public let logFileRef: String
    public let primaryCategory: CrashCategory
    public let confidenceTier: ConfidenceTier
    public let topSignatures: [String]  // max 3
    public let remediationCardIds: [String]
    public let wineDebugPreset: WineDebugPreset?
}

public struct DiagnosisHistory: Codable, Sendable {
    public static let maxEntries = 5
    public var entries: [DiagnosisHistoryEntry] = []

    public mutating func append(_ entry: DiagnosisHistoryEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }
}
```

### Pattern 4: WINEDEBUG Preset via EnvironmentBuilder
**What:** WINEDEBUG presets are injected through the existing `EnvironmentBuilder` layer system, using a new `featureRuntime` layer entry.
**When to use:** When user opts into "Re-run with enhanced logging" for a program.
**Example:**
```swift
// WineDebugPreset.swift
public enum WineDebugPreset: String, Codable, CaseIterable, Sendable {
    case normal      // "fixme-all" (current default)
    case crash       // "+seh,+tid,+pid,+timestamp"
    case dllLoad     // "+loaddll,+module,+tid,+pid"
    case verbose     // "+relay,+seh,+tid,+pid" (labeled as noisy)

    public var winedebugValue: String {
        switch self {
        case .normal:  "fixme-all"
        case .crash:   "+seh,+tid,+pid,+timestamp"
        case .dllLoad: "+loaddll,+module,+tid,+pid"
        case .verbose: "+relay,+seh,+tid,+pid"
        }
    }
}

// In WineEnvironment.swift, when preset is active:
// builder.set("WINEDEBUG", preset.winedebugValue, layer: .featureRuntime)
```

### Pattern 5: Redaction Pipeline for Export
**What:** A composable redaction pipeline that transforms strings/dicts before export.
**When to use:** Before writing any user data to the diagnostic ZIP or clipboard.
**Example:**
```swift
// In DiagnosticExporter.swift
public struct Redactor: Sendable {
    public static let sensitiveKeyPatterns = ["TOKEN", "KEY", "SECRET", "PASSWORD", "AUTH"]
    public static let homePathRegex = try! Regex("/Users/[^/\\s]+")

    public static func redactHomePaths(_ text: String) -> String {
        text.replacing(homePathRegex, with: { _ in "/Users/<redacted>" })
    }

    public static func redactEnvironment(_ env: [String: String]) -> [String: String] {
        env.mapValues { value in
            redactHomePaths(value)
        }.filter { key, _ in
            !sensitiveKeyPatterns.contains(where: { key.uppercased().contains($0) })
        }
    }
}
```

### Anti-Patterns to Avoid
- **Coupling classifier to UI**: The classifier must be pure WhiskyKit logic with no SwiftUI imports. The UI consumes `CrashDiagnosis` as a value type.
- **Unbounded log scanning**: Always cap the number of lines scanned. Wine logs can be 20 MiB (per existing `maxLogFileBytes`). Process only last N lines or use the tail approach from `StabilityDiagnostics.tailOfLogFile()`.
- **Mutable shared pattern state**: Patterns should be loaded once at classifier init and treated as immutable. No global mutable state.
- **Inline regex strings**: All regex patterns live in `patterns.json`, not hardcoded in Swift. This enables future pattern updates without recompilation.
- **Showing raw confidence scores**: The user decisions explicitly state raw numbers are never shown. Always map to High/Medium/Low tiers.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ZIP creation | Custom ZIP binary format writer | `FileWrapper` directory + `NSFileCoordinator`-based compression, or ZIPFoundation if needed | ZIP format has edge cases (CRC32, compression levels, path encoding) |
| Wine log format parsing | Ad-hoc string splitting | Structured regex matching against documented Wine format (`TTTT:class:channel:function msg`) | Wine's format is stable and well-documented; structured parsing enables accurate channel/class extraction |
| Home path detection | Hardcoded `/Users/` prefix | `FileManager.default.homeDirectoryForCurrentUser` + regex | Works across different macOS configurations |
| System info collection | Manual `sysctl` calls | `ProcessInfo.processInfo.operatingSystemVersion`, `Host.current().localizedName`, existing `MacOSVersion.current` | Already have patterns in `StabilityDiagnostics` and `LauncherDiagnostics` |
| Plist serialization | Manual plist writing | `PropertyListEncoder`/`PropertyListDecoder` | Already used throughout the codebase for `BottleSettings`, `ProgramSettings` |
| Env provenance tracking | New tracking system | Existing `EnvironmentProvenance` from `EnvironmentBuilder.resolve()` | Already captures which layer set each env var |

**Key insight:** The codebase already has nearly every building block. The classifier pipeline and pattern database are the genuinely new work; everything else (logging, persistence, environment introspection, diagnostics generation, system info) already exists in usable form.

## Common Pitfalls

### Pitfall 1: Swift Regex Performance on Large Logs
**What goes wrong:** Swift's native `Regex` can be significantly slower than `NSRegularExpression` for simple patterns (up to 1000x slower has been reported for pathological inputs in early Swift 5.7).
**Why it happens:** Swift `Regex` uses a different engine internally. For simple substring-match patterns, the overhead is disproportionate.
**How to avoid:** Use the substring prefilter pattern: every `CrashPattern` has an optional `substringPrefilter` field. Check `line.contains(prefilter)` before invoking the regex. For the common case (DLL name check, hex code check), this skips 95%+ of lines. Compile each `Regex` once at load time, not per-line. Consider `NSRegularExpression` as a fallback if profiling shows issues.
**Warning signs:** Classification taking >100ms for a typical log. Profile with Instruments if this occurs.

### Pitfall 2: Unbounded Diagnosis History Growth
**What goes wrong:** Storing diagnosis history per-program without bounds leads to unbounded disk usage.
**Why it happens:** Users who frequently re-run crashing programs accumulate entries.
**How to avoid:** Hard cap of 5 entries per program/bottle (as specified in decisions). Use FIFO eviction. Store as a compact sidecar file alongside the existing program settings plist.
**Warning signs:** Diagnosis plist files growing beyond a few KB.

### Pitfall 3: Regex Patterns That Match Too Broadly
**What goes wrong:** A pattern intended for "DLL load failure" matches normal Wine "fixme" output, producing hundreds of false positives.
**Why it happens:** Wine's "fixme" output is extremely verbose and includes DLL names, function names, etc. that overlap with error patterns.
**How to avoid:** Every pattern must filter on the Wine message class prefix (`err:`, `warn:`). Never match against raw `fixme:` lines unless the pattern explicitly targets fixme. Require positive match test fixtures for every pattern.
**Warning signs:** Diagnosis showing >20 matches for "DLL load failure" when the program works fine.

### Pitfall 4: ZIP Export Including Sensitive Data
**What goes wrong:** Exported ZIP contains user home directory paths, API tokens from environment variables, or registry entries with license keys.
**Why it happens:** Wine environment includes paths with username, and users may have custom env vars with tokens.
**How to avoid:** Apply the redaction pipeline to ALL exported content. Redact home paths, filter env vars by sensitive key patterns, and never include full registry dumps. The export dialog's "Include sensitive details" checkbox should be OFF by default.
**Warning signs:** Exported `env.json` containing `/Users/realname/` or values for keys matching TOKEN/KEY/SECRET.

### Pitfall 5: Blocking the Main Thread During Classification
**What goes wrong:** Running the classifier synchronously on the main thread freezes the UI.
**Why it happens:** Log files can be 20 MiB. Even with prefilters, scanning takes time.
**How to avoid:** Run classification on a background task (`Task.detached(priority: .utility)`). The classifier is `Sendable` and stateless after init. Yield the `CrashDiagnosis` result back to `@MainActor` for UI update.
**Warning signs:** UI hang when Wine process exits.

### Pitfall 6: WINEDEBUG Presets Overriding User Custom Environment
**What goes wrong:** A diagnostic WINEDEBUG preset overwrites a user's custom WINEDEBUG setting from `ProgramSettings.environment`.
**Why it happens:** If the preset writes to the wrong `EnvironmentBuilder` layer, it conflicts with user settings.
**How to avoid:** Use the `featureRuntime` layer (priority 7) for diagnostic presets. This is above `programUser` (6), which is correct since it is a temporary diagnostic override. The preset is a transient, opt-in action, not a persistent setting.
**Warning signs:** User custom WINEDEBUG ignored when diagnostic preset is active.

## Code Examples

### Wine Log Line Format
Wine stderr output follows this format (verified from WineHQ documentation and codebase research):
```
TTTT:class:channel:function message text here
```
Where:
- `TTTT` = hex thread ID (e.g., `0024`)
- `class` = `err`, `warn`, `fixme`, or `trace`
- `channel` = debug channel name (e.g., `module`, `seh`, `d3d`, `winhttp`)
- `function` = the Wine function that emitted the message

Examples of real Wine error output:
```
0024:err:module:import_dll Library MSVCR100.dll (which is needed by L"game.exe") not found
0024:err:module:LdrInitializeThunk Main exe initialization for L"C:\\game.exe" failed, status c0000005
0080:err:seh:NtRaiseException Unhandled exception code c0000005 flags 0 addr 0x7b012345
wine: Unhandled page fault on read access to 0x00000000 at address 0x7b012345
```

Special non-channel messages (always from Wine core):
```
wine: Unhandled page fault on [read|write|execute] access to 0x... at address 0x...
wine: Call from 0x... to unimplemented function ...
```

### WINEDEBUG Environment Variable Syntax
```
WINEDEBUG=fixme-all              # Suppress all fixme messages (current Whisky default)
WINEDEBUG=+seh,+tid,+pid        # Enable seh channel with thread/process IDs
WINEDEBUG=+loaddll,+module       # Enable DLL loading and module channels
WINEDEBUG=+relay                 # API call tracing (extremely verbose)
```

Prefix meanings:
- `+channel` = enable trace messages for this channel
- `-channel` = disable messages for this channel
- `class-channel` = disable specific class for channel (e.g., `fixme-all`)
- `class+channel` = enable specific class for channel

### Existing ProcessOutput Stream Integration Point
```swift
// Source: Process+Extensions.swift
// ProcessOutput is how Wine output reaches the app:
public enum ProcessOutput: Hashable, Sendable {
    case started
    case message(String)   // stdout line
    case error(String)     // stderr line (Wine debug output lands here)
    case terminated(Int32) // exit code
}

// Integration: After process termination, classifier runs on collected output:
// 1. Collect .error() messages during stream consumption
// 2. On .terminated(code) where code != 0, trigger classification
// 3. Or: read from the log file that makeFileHandle() already creates
```

### Existing Diagnostic Report Pattern
```swift
// Source: StabilityDiagnostics.swift
// Follow this established pattern for the new diagnostic exporter:
public enum StabilityDiagnostics {
    public struct Configuration: Sendable {
        public var bundle: Bundle
        public var logsFolder: URL
        public var now: @Sendable () -> Date
    }

    @MainActor
    public static func generateDiagnosticReport(
        for bottle: Bottle,
        config: Configuration = .init()
    ) async -> String { ... }

    static func tailOfLogFile(_ url: URL) -> String {
        // Bounded: max 64 KiB, last 200 lines
        // This approach should be reused for the wine.tail.log in ZIP export
    }
}
```

### Environment Provenance for Export
```swift
// Source: EnvironmentBuilder.swift
// Already captures which layer set each env var -- use for env.json export:
public struct EnvironmentProvenance: Sendable {
    public struct Entry: Sendable {
        public let key: String
        public let value: String
        public let layer: EnvironmentLayer
        public let overriddenBy: EnvironmentLayer?
    }
    public let entries: [String: Entry]
    public let activeLayers: Set<EnvironmentLayer>
}
// Access: let (resolved, provenance) = builder.resolve()
```

### ZIP Creation with FileWrapper
```swift
// FileWrapper-based ZIP creation (no external dependency):
func createDiagnosticZIP(contents: [(filename: String, data: Data)]) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    for item in contents {
        try item.data.write(to: tempDir.appendingPathComponent(item.filename))
    }

    let zipURL = tempDir.deletingLastPathComponent()
        .appendingPathComponent("diagnostics.zip")

    // Use NSFileCoordinator / Process to invoke ditto for ZIP creation
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc",
                         tempDir.path, zipURL.path]
    try process.run()
    process.waitUntilExit()

    try FileManager.default.removeItem(at: tempDir)
    return zipURL
}
```

**Note:** Using `/usr/bin/ditto` is the standard macOS approach for programmatic ZIP creation without third-party dependencies. It is available on all macOS versions. Alternative: `NSFileCoordinator` with `FileWrapper`.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSRegularExpression` for all regex | Swift native `Regex` type | Swift 5.7 (2022) | Type-safe, compile-time checked, but monitor performance |
| Manual string-based JSON | `Codable` with `JSONDecoder` | Swift 4 (2017) | Simpler pattern loading, automatic validation |
| Separate diagnostic text files | Structured ZIP with JSON + Markdown | This phase | Enables machine-readable crash data alongside human-readable reports |
| Raw log dumps for debugging | Classified, confidence-scored diagnosis | This phase | Users get actionable guidance instead of noise |
| Single WINEDEBUG setting | Curated presets with opt-in enhanced logging | This phase | Targeted diagnostics without impacting normal performance |

**Deprecated/outdated:**
- `StabilityDiagnostics.generateDiagnosticReport()` will not be deprecated but will be complemented by the new, richer export system. The new system subsumes its functionality.
- The deprecated `BottleSettings.environmentVariables(wineEnv:)` method should not be used by any new code; use `EnvironmentBuilder` exclusively.

## Open Questions

1. **Process Registry dependency (Phase 3)**
   - What we know: Phase 5 depends on Phase 3 (process tracking provides context for which process generated errors). The codebase currently has no `ProcessRegistry` type.
   - What's unclear: Whether Phase 3 is fully implemented before Phase 5 starts. The `WineProcess` and `ProcessKind` types exist, but no registry that maps a process to its log file.
   - Recommendation: Design the classifier to accept a log file URL directly. The "which process generated this log" mapping can be added when Phase 3 lands. For now, use the most recent log file in `Wine.logsFolder` or let the user select from a list.

2. **patterns.json bundle resource path**
   - What we know: WhiskyKit is a Swift Package with no current JSON resources.
   - What's unclear: Whether SPM resource bundles work correctly when WhiskyKit is consumed by the Whisky Xcode project.
   - Recommendation: Add `resources: [.process("Diagnostics/Resources/")]` to the WhiskyKit target in Package.swift. Test that `Bundle.module.url(forResource: "patterns", withExtension: "json")` resolves correctly. If SPM resource bundles are problematic, fall back to embedding the JSON as a static string literal (less ideal but functional).

3. **Log file association with program**
   - What we know: `Wine.makeFileHandle()` creates log files with ISO 8601 timestamps but does not embed which program/bottle the log belongs to.
   - What's unclear: How to reliably associate a log file with a specific program run.
   - Recommendation: Extend the log header (already written by `writeInfo(for bottle:)` and `writeInfo(for process:)`) to include a structured header line with bottle URL and program path. The classifier can parse this header to determine context. Alternatively, add a lightweight metadata sidecar (`.meta.json`) alongside each `.log` file.

4. **Split view breakpoint threshold (Claude's Discretion)**
   - What we know: The decision says "split view on desktop if space allows."
   - Recommendation: Use a minimum width of 700pt for split view. Below that, stack vertically (suggestions on top, log below). This matches typical SwiftUI `NavigationSplitView` breakpoints and works well on 13" MacBooks.

5. **Log viewer virtualization (Claude's Discretion)**
   - What we know: Wine logs can be 20 MiB. SwiftUI `Text` in `ScrollView` cannot handle this.
   - Recommendation: Wrap `NSTextView` via `NSViewRepresentable` for the raw log viewer. `NSTextView` handles large text natively with layout manager virtualization. Apply syntax coloring via `NSAttributedString` attributes on tagged lines only (not full syntax highlighting). Alternatively, use lazy line-by-line loading with a `LazyVStack` showing only visible lines, but `NSTextView` is simpler and more proven.

6. **Gutter marker icons (Claude's Discretion)**
   - Recommendation: Use SF Symbols for gutter markers: `exclamationmark.circle.fill` (red) for errors/crashes, `exclamationmark.triangle.fill` (yellow) for warnings, `circle.fill` (orange) for graphics issues. Keep it minimal -- only mark lines with strong pattern matches.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** - Direct reading of Wine.swift, Process+Extensions.swift, WineEnvironment.swift, EnvironmentBuilder.swift, StabilityDiagnostics.swift, WinePrefixDiagnostics.swift, ProgramSettings.swift, ProgramOverrides.swift, BottleSettings.swift, FileHandle+Extensions.swift, GPUDetection.swift, MacOSCompatibility.swift, GraphicsBackendResolver.swift, LauncherDiagnostics.swift, WineProcessTypes.swift, Wine+ProcessManagement.swift
- **WhiskyKit Package.swift** - Swift 6, macOS 15+, SemanticVersion dependency only
- [WineHQ Debug Channels wiki](https://wiki.winehq.org/Debug_Channels) - Wine debug output format documentation
- [CodeWeavers Debugging Wine blog](https://www.codeweavers.com/blog/aeikum/2019/1/15/working-on-wine-part-4-debugging-wine) - Wine stderr format, WINEDEBUG syntax, channel names, message classes

### Secondary (MEDIUM confidence)
- [WineHQ Forums: err:module patterns](https://forum.winehq.org/viewtopic.php?t=35296) - Common DLL load failure patterns verified across multiple forum threads
- [WineHQ Forums: c0000005 access violation](https://forum.winehq.org/viewtopic.php?t=6818) - Access violation error format verified
- [Swift Forum: Regex performance](https://forums.swift.org/t/performance-of-the-new-regex-in-swift-5-7-degrades-quadratically-without-need/58122) - Swift Regex performance concerns (motivated prefilter pattern)
- [ZIPFoundation GitHub](https://github.com/weichsel/ZIPFoundation) - ZIP creation alternative if needed
- [STTextView GitHub](https://github.com/krzyzanowskim/STTextView) - TextKit 2 alternative for log viewer if NSTextView proves insufficient

### Tertiary (LOW confidence)
- GPU/Metal-specific crash patterns (device lost, IOMFB) - could not find definitive pattern strings in public documentation. Recommend collecting real-world samples from Whisky users to populate the GPU category patterns.
- EasyAntiCheat/BattlEye specific error message signatures - confirmed as "not supported under Wine on macOS" but exact stderr signature strings need real-world log samples.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies needed; all Foundation/SwiftUI, verified against macOS 15+ target
- Architecture: HIGH - Classifier-as-pipeline pattern is well-established; codebase already has all integration points
- Pitfalls: HIGH - Identified from direct codebase analysis and verified Swift Regex performance reports
- Wine error format: HIGH - Documented by WineHQ and verified across multiple sources
- Pattern definitions: MEDIUM - First-wave patterns (DLL, access violation) are well-documented; GPU and anti-cheat patterns need real-world log samples
- ZIP export approach: MEDIUM - `ditto`-based approach is standard macOS but untested in this specific context

**Research date:** 2026-02-09
**Valid until:** 2026-03-11 (30 days -- stable domain, no fast-moving dependencies)
