# Phase 6: Audio Troubleshooting - Research

**Researched:** 2026-02-10
**Domain:** CoreAudio device monitoring, Wine audio driver configuration, audio diagnostics pipeline, troubleshooting wizard
**Confidence:** HIGH (codebase patterns) / MEDIUM (CoreAudio API specifics) / LOW (WhiskyAudioTest.exe build approach)

## Summary

Phase 6 builds an audio diagnostics and troubleshooting system within Whisky that mirrors the Phase 5 crash diagnostics pattern but targets audio-specific problems. The core technical challenge spans three domains: (1) macOS CoreAudio device monitoring via C-level AudioObject APIs wrapped in Swift, (2) Wine audio driver configuration through registry keys and environment variables flowing through the existing EnvironmentBuilder cascade, and (3) a two-stage audio test probe using a shipped Windows executable that exercises Wine's audio stack.

The codebase already provides nearly all integration points: `BottleSettings` with its config-group pattern (`BottleWineConfig`, `BottleGraphicsConfig`, etc.) shows exactly how to add a `BottleAudioConfig`; `ConfigView` with section components (`GraphicsConfigSection`) shows the UI pattern including Simple/Advanced mode toggle via `@AppStorage`; `WineRegistry` provides `addRegistryKey`/`queryRegistryKey` for reading and writing Wine registry values; `EnvironmentBuilder` with its 8-layer cascade handles all environment variable flow; Phase 5's `Diagnostics/` module (`CrashClassifier`, `CrashDiagnosis`, `RemediationAction`, `RemediationCardView`, `ConfidenceTier`) provides the exact pattern for status/findings/fix-cards/technical-details layout. The net-new work is: CoreAudio device monitoring service, audio-specific probes and findings model, the troubleshooting wizard engine, the audio config model and registry integration, and the bundled WhiskyAudioTest.exe.

**Primary recommendation:** Build the CoreAudio monitoring as a standalone `AudioDeviceMonitor` class in WhiskyKit using raw AudioObject APIs (no third-party dependency). Create `BottleAudioConfig` following the `BottleGraphicsConfig` pattern. Model the troubleshooting wizard as a data-driven state machine with Swift probe functions. Ship WhiskyAudioTest.exe as a minimal C program compiled with MinGW that uses the waveOut API (best Wine compatibility). Reuse Phase 5's `ConfidenceTier`, `RemediationAction`, and `RemediationCardView` directly.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Diagnostics panel location and structure
- First-class "Audio" section in ConfigView (same level as Graphics/Performance)
- Deep-links from program settings ("Troubleshooting: Audio...") and any crash/remediation card flagging audio issues
- Layout order: Status line -> Test buttons -> Settings (Simple/Advanced)
- Status line shows: OK / Degraded / Broken with primary detected issue and confidence tier

#### Diagnostics detail level
- Baseline (always visible): default output device name, transport type (Built-in/USB/Bluetooth/AirPlay), current sample rate and channel count, "Last device change" timestamp
- Advanced (collapsible): full device list with defaults, per-device supported sample rates, Wine audio driver status, dependency checks (XAudio2/OpenAL presence)
- No raw low-level properties unless behind "Export diagnostics"

#### Diagnostics refresh behavior
- Hybrid: auto-refresh on CoreAudio device-route change notifications + slow timer (5-10s) for "audio engine alive" checks while panel is visible
- Manual Refresh button for deterministic user control
- No continuous tight polling

#### Issue presentation pattern
- Matches Phase 5 crash remediation pattern, scoped to audio
- Status line at top (OK/Degraded/Broken)
- Findings list (1-5 items max) with detection description, confidence (High/Medium/Low), and "Details" disclosure for evidence
- Fix cards with direct actions (toggle setting, sample rate guidance, open Winetricks, restart bottle)
- "Technical details" collapsed by default

#### Troubleshooting guide: symptom-driven wizard
- Flow: Pick Symptom -> Snapshot -> Quick Tests -> Wine Stack Checks -> Dependency Checks -> Targeted Fix Paths -> Escalation
- Symptom categories: No sound, Crackling/pops, Audio stutter/desync, Wrong output device, Sound in menus only
- Every step ends with "Did this fix it?" -- flow stops as soon as audio is OK
- Bounded to ~3 fix paths before escalation (no infinite loops)
- Record each attempted fix (action id, timestamp, before/after values) to avoid repeating

#### Troubleshooting data format
- Data-driven JSON for guide structure (steps, branching, copy, probe IDs, remediation action IDs)
- Probe execution in Swift (strongly typed, testable)
- If time-constrained: start hardcoded but design for JSON migration without changing probe/result model

#### Audio test probe: two-stage
- Stage 1 (automatic): bundled WhiskyAudioTest.exe initializes WASAPI/mmdevapi (fallback to WinMM/waveOut), writes short buffer, exits with structured JSON result line
- Stage 2 (optional): "Play test tone" button runs same helper with --beep flag, UI asks "Did you hear the tone?" Yes/No
- Probe runs with curated WINEDEBUG preset (eg +mmdevapi,+dsound,+winmm), captures stdout/stderr
- Ship helper with Whisky -- no dependency on PowerShell/.NET

#### Escalation after failed fixes
- Re-run probes to update status based on what actually changed
- Branch to next-most-likely cause using updated evidence
- Offer enhanced audio logging after 1-2 failed fix paths (not immediately)
- Final step: "Export Diagnostics" or "Open advanced audio settings"

#### Audio settings: 3 settings + 1 action
1. **Audio Driver / Enable Audio**: Picker -- Auto (Recommended) / CoreAudio / Disabled. Backed by Wine registry `HKCU\Software\Wine\Drivers`
2. **Audio Buffer / Latency Preset**: Picker -- Default / Low latency / Stable (larger buffer). Backed by `HKCU\Software\Wine\DirectSound\HelBuflen`
3. **Output Device Mode** (Advanced): Follow macOS default (Recommended) vs Pin to device
4. **Reset Audio State** (action button): Clears Wine stored device GUID/UID mappings + restarts bottle

#### Settings tier: Simple/Advanced
- Simple: Audio driver (Auto/Disabled) + Latency preset (Default/Stable) + Test Wine Audio button -- 2 controls max
- Advanced: full driver picker, buffer values, device pinning, Reset Audio State action
- Persist Simple/Advanced preference globally (same as graphics)
- Badge in Simple mode if advanced audio overrides are active

#### Audio settings scope: bottle-level only
- No per-program audio overrides -- Wine audio knobs are prefix-wide/registry-backed
- Per-program audio DLL overrides and winetricks tagging already fit Phase 2 override model
- Separate bottles as the supported workaround for radically different audio needs

#### Test button placement
- Top of Audio section, before settings controls
- Row 1: Status (OK/Degraded/Broken) + "Last tested" timestamp
- Row 2: Test Wine Audio (primary) + Play Test Tone (secondary) + Refresh
- Then settings, so users can test -> change -> re-test without scrolling

#### Bluetooth/device disconnect alerts
- Whisky focused: non-blocking `.info`/`.error` toast with guidance ("Switch macOS output device and retest")
- Whisky backgrounded: macOS notification (best-effort, fallback to logging)
- Update Audio section status to Degraded with device name and timestamp
- Rate-limit/debounce: one alert per device per few minutes
- Quiet "Reconnected" toast when device returns

#### Sample rate mismatch detection
- Default: reactive only (during troubleshooting flow, audio panel open, or "Test Wine audio")
- Proactive exception: if active route switches to Bluetooth Hands-Free / very low sample rate while bottle has running processes, show one non-blocking warning linking to Audio panel
- Flag "unusual" rates (8/16/22.05 kHz) as likely cause during troubleshooting

#### Device change history
- Bounded ring buffer per session, persist last ~20 events
- Track: timestamp, event type (default output changed, disconnected, reconnected, sample rate changed), device display name, transport type
- No unique hardware identifiers by default -- name + transport only
- Include in diagnostics export (redacted if needed)

#### Device change remediation
- Inform and offer guided actions, never automatic fixes
- One-click "Restart bottle audio" (stop/restart wineserver) with confirmation if running apps
- Offer "Open Audio Diagnostics" and "Test Wine audio" immediately
- For pinned device users: "Switch back to pinned device" button that instructs user or opens macOS Sound settings -- no force-changing system audio

### Claude's Discretion
- Exact probe implementation details and error handling
- CoreAudio API usage patterns (AudioObjectPropertyAddress, listener registration)
- WhiskyAudioTest.exe implementation language and build approach
- Ring buffer data structure choice
- Toast/notification timing and animation details
- JSON schema design for troubleshooting guide data

### Deferred Ideas (OUT OF SCOPE)
- Microphone/voice chat support (needs entitlements/permissions work -- potential future phase)
- Per-program audio settings that mutate the prefix around launch
- "Launch with audio disabled" as a one-off per-program action
- Automatic system audio device switching
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreAudio.framework (AudioHardware.h) | macOS 15+ | Device enumeration, property queries, change listeners | Apple's native C API for audio hardware; no dependency needed |
| Foundation `JSONDecoder`/`JSONEncoder` | Built-in | Troubleshooting guide data, probe results, device history | Consistent with Phase 5 pattern data |
| Foundation `PropertyListEncoder` | Built-in | `BottleAudioConfig` persistence within `BottleSettings` | Matches existing config group pattern |
| SwiftUI | macOS 15+ | Audio section UI, wizard views, toast notifications | Existing UI framework |
| `UserNotifications` framework | macOS 15+ | Background device-change notifications | Apple's standard macOS notification API |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.log` Logger | Built-in | Audio subsystem logging | All audio monitoring, probe execution |
| MinGW-w64 (build tool) | 12+ | Cross-compile WhiskyAudioTest.exe | Build-time only; not a runtime dependency |
| Phase 5 Diagnostics types | In-tree | `ConfidenceTier`, `RemediationAction`, `RemediationCardView` | Reuse directly for audio findings/fix cards |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw CoreAudio C API | SimplyCoreAudio SPM package | SimplyCoreAudio was archived March 2024 and is no longer maintained. Raw API is stable and well-documented. Wrapping it ourselves avoids abandoned dependency. |
| MinGW-compiled C exe | Rust cross-compiled exe | Rust would be cleaner but adds significant build complexity. MinGW C is minimal (one .c file, `waveOutOpen` + `waveOutWrite`) and has the best Wine compatibility track record. |
| JSON troubleshooting guide | Hardcoded Swift steps | JSON enables future updates without recompilation. Start hardcoded per decision, but design probe/result model to be JSON-loadable. |

**Installation:** No new SPM dependencies. CoreAudio.framework is a system framework linked via Xcode. MinGW is a build-time tool installed via Homebrew (`brew install mingw-w64`) for compiling the test exe.

## Architecture Patterns

### Recommended Project Structure
```
WhiskyKit/Sources/WhiskyKit/
├── Audio/                              # NEW: Audio monitoring and probes
│   ├── AudioDeviceMonitor.swift        # CoreAudio device enumeration + listeners
│   ├── AudioDeviceInfo.swift           # Device model (name, transport, sample rate, channels)
│   ├── AudioDeviceChangeEvent.swift    # Change event type for ring buffer
│   ├── AudioDeviceHistory.swift        # Bounded ring buffer (~20 events)
│   ├── AudioStatus.swift              # OK/Degraded/Broken status with findings
│   ├── AudioFinding.swift             # Single diagnostic finding (matches Phase 5 DiagnosisMatch pattern)
│   ├── AudioProbe.swift               # Probe protocol + concrete probes (CoreAudio, Wine registry, test exe)
│   ├── AudioProbeResult.swift         # Structured probe result with evidence
│   ├── AudioTroubleshootingEngine.swift # State machine for wizard flow
│   └── AudioTroubleshootingStep.swift  # Step/branch model for wizard
├── Whisky/
│   └── BottleAudioConfig.swift         # NEW: Audio settings config group
├── Wine/
│   └── WineAudioRegistry.swift         # NEW: Wine registry audio key helpers
└── Diagnostics/                        # EXISTING: Reuse types
    ├── ConfidenceTier.swift            # Reuse directly
    ├── RemediationAction.swift         # Extend ActionType for audio actions
    └── RemediationTimeline.swift       # Reuse for recording attempted fixes

Whisky/Views/
├── Bottle/
│   └── AudioConfigSection.swift        # NEW: Audio section in ConfigView
├── Audio/                              # NEW: Audio-specific views
│   ├── AudioStatusView.swift           # Status line (OK/Degraded/Broken)
│   ├── AudioTestButtonsView.swift      # Test Wine Audio + Play Test Tone + Refresh
│   ├── AudioFindingsView.swift         # Findings list with fix cards
│   ├── AudioSettingsView.swift         # Simple/Advanced settings controls
│   ├── AudioTroubleshootingWizardView.swift  # Symptom-driven wizard
│   ├── AudioDeviceListView.swift       # Advanced: full device list
│   └── AudioDeviceHistoryView.swift    # Device change log
└── Diagnostics/                        # EXISTING: Reuse views
    └── RemediationCardView.swift       # Reuse directly for audio fix cards

Resources/
└── WhiskyAudioTest.exe                 # Shipped with Whisky app bundle
```

### Pattern 1: CoreAudio Device Monitoring (AudioDeviceMonitor)
**What:** A class that wraps CoreAudio's C API to enumerate devices, query properties, and register change listeners. Publishes device state changes via Combine or async callbacks.
**When to use:** Audio panel is visible, or a bottle has running processes (for proactive Bluetooth alerts).
**Example:**
```swift
// AudioDeviceMonitor.swift
import CoreAudio
import Foundation
import os.log

public final class AudioDeviceMonitor: @unchecked Sendable {
    public typealias DeviceChangeHandler = @Sendable (AudioDeviceChangeEvent) -> Void

    private var listenerRegistered = false
    private var onChange: DeviceChangeHandler?
    private let logger = Logger(subsystem: "com.whisky", category: "AudioDeviceMonitor")

    public init() {}

    /// Queries the default output device info.
    public func defaultOutputDevice() -> AudioDeviceInfo? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return nil }
        return queryDeviceInfo(deviceID)
    }

    /// Queries all output devices.
    public func allOutputDevices() -> [AudioDeviceInfo] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        )
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceIDs
        )
        return deviceIDs.compactMap { queryDeviceInfo($0) }
            .filter { $0.outputChannelCount > 0 }
    }

    /// Registers for default output device change notifications.
    public func startListening(onChange: @escaping DeviceChangeHandler) {
        self.onChange = onChange
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Use AudioObjectAddPropertyListenerBlock for Swift-friendly callback
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self else { return }
            let event = AudioDeviceChangeEvent(
                timestamp: Date(),
                eventType: .defaultOutputChanged,
                deviceName: self.defaultOutputDevice()?.name ?? "Unknown",
                transportType: self.defaultOutputDevice()?.transportType ?? .unknown
            )
            self.onChange?(event)
        }
        listenerRegistered = true
    }

    private func queryDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        // Query name, transport type, sample rate, channel count
        // using AudioObjectGetPropertyData with appropriate selectors
        // (kAudioObjectPropertyName, kAudioDevicePropertyTransportType,
        //  kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyStreamConfiguration)
        // ... implementation details ...
        nil // placeholder
    }
}
```

### Pattern 2: BottleAudioConfig (Following BottleGraphicsConfig)
**What:** A Codable config group stored within `BottleSettings`, with proxy properties on `BottleSettings` for clean access.
**When to use:** Storing audio settings per bottle in the existing plist persistence.
**Example:**
```swift
// BottleAudioConfig.swift
public enum AudioDriverMode: String, Codable, CaseIterable, Sendable {
    case auto        // Let Wine choose (recommended)
    case coreaudio   // Force CoreAudio driver
    case disabled    // Disable audio entirely

    public var displayName: String {
        switch self {
        case .auto: String(localized: "config.audio.driver.auto")
        case .coreaudio: "CoreAudio"
        case .disabled: String(localized: "config.audio.driver.disabled")
        }
    }

    /// Wine registry value for HKCU\Software\Wine\Drivers Audio key
    public var registryValue: String? {
        switch self {
        case .auto: nil       // Remove key to let Wine auto-detect
        case .coreaudio: "coreaudio"
        case .disabled: ""    // Empty string disables audio
        }
    }
}

public enum AudioLatencyPreset: String, Codable, CaseIterable, Sendable {
    case defaultPreset   // Wine default (HelBuflen = 65536)
    case lowLatency      // HelBuflen = 512, SndQueueMax = 3
    case stable          // HelBuflen = 131072 (larger buffer for Bluetooth)

    public var helBuflenValue: Int {
        switch self {
        case .defaultPreset: 65_536
        case .lowLatency: 512
        case .stable: 131_072
        }
    }
}

public enum OutputDeviceMode: String, Codable, CaseIterable, Sendable {
    case followSystem   // Follow macOS default (recommended)
    case pinned         // Pin to specific device
}

public struct BottleAudioConfig: Codable, Equatable {
    var audioDriver: AudioDriverMode = .auto
    var latencyPreset: AudioLatencyPreset = .defaultPreset
    var outputDeviceMode: OutputDeviceMode = .followSystem
    var pinnedDeviceName: String? = nil

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.audioDriver = try container.decodeIfPresent(
            AudioDriverMode.self, forKey: .audioDriver
        ) ?? .auto
        self.latencyPreset = try container.decodeIfPresent(
            AudioLatencyPreset.self, forKey: .latencyPreset
        ) ?? .defaultPreset
        self.outputDeviceMode = try container.decodeIfPresent(
            OutputDeviceMode.self, forKey: .outputDeviceMode
        ) ?? .followSystem
        self.pinnedDeviceName = try container.decodeIfPresent(
            String.self, forKey: .pinnedDeviceName
        )
    }
}
```

### Pattern 3: Wine Registry Audio Helpers
**What:** Extension on `Wine` providing typed audio-specific registry read/write methods.
**When to use:** When audio settings change and need to be written to the Wine registry, or when probing current Wine audio state.
**Example:**
```swift
// WineAudioRegistry.swift
public extension Wine {
    private enum AudioRegistryKey: String {
        case drivers = #"HKCU\Software\Wine\Drivers"#
        case directSound = #"HKCU\Software\Wine\DirectSound"#
    }

    @MainActor
    static func readAudioDriver(bottle: Bottle) async throws -> String? {
        try await queryRegistryKey(
            bottle: bottle,
            key: AudioRegistryKey.drivers.rawValue,
            name: "Audio",
            type: .string
        )
    }

    @MainActor
    static func setAudioDriver(bottle: Bottle, driver: AudioDriverMode) async throws {
        if let value = driver.registryValue {
            try await addRegistryKey(
                bottle: bottle,
                key: AudioRegistryKey.drivers.rawValue,
                name: "Audio",
                data: value,
                type: .string
            )
        }
        // For .auto: could delete the key to let Wine auto-detect
    }

    @MainActor
    static func setDirectSoundBuffer(
        bottle: Bottle, helBuflen: Int
    ) async throws {
        try await addRegistryKey(
            bottle: bottle,
            key: AudioRegistryKey.directSound.rawValue,
            name: "HelBuflen",
            data: String(helBuflen),
            type: .string
        )
    }
}
```

### Pattern 4: Audio Troubleshooting Engine (State Machine)
**What:** A state machine that drives the symptom-driven wizard, tracking current step, attempted fixes, and probe results.
**When to use:** When user starts the troubleshooting flow from the Audio panel.
**Example:**
```swift
// AudioTroubleshootingEngine.swift
public final class AudioTroubleshootingEngine: ObservableObject {
    public enum WizardState: Equatable {
        case pickSymptom
        case runningProbe(String)        // probe description
        case showingFinding(AudioFinding)
        case offeringFix(RemediationAction)
        case askingDidItWork
        case resolved
        case escalation
    }

    @Published public var state: WizardState = .pickSymptom
    @Published public var attemptedFixes: [AttemptedFix] = []
    @Published public var probeResults: [AudioProbeResult] = []

    public struct AttemptedFix: Codable, Sendable {
        public let actionId: String
        public let timestamp: Date
        public let beforeValue: String?
        public let afterValue: String?
    }

    private let maxFixAttempts = 3

    public func selectSymptom(_ symptom: AudioSymptom) async {
        // 1. Run snapshot probe (CoreAudio state)
        // 2. Run quick tests (Wine audio test exe)
        // 3. Based on symptom + evidence, navigate to first fix path
    }

    public func userReportsFixed() {
        state = .resolved
    }

    public func userReportsNotFixed() {
        if attemptedFixes.count >= maxFixAttempts {
            state = .escalation
        } else {
            // Re-run probes, branch to next fix path
        }
    }
}
```

### Pattern 5: AudioConfigSection (Following GraphicsConfigSection)
**What:** A SwiftUI section view for the Audio panel in ConfigView with Simple/Advanced toggle.
**When to use:** Audio section in ConfigView, same level as Graphics and Performance.
**Example:**
```swift
// AudioConfigSection.swift
struct AudioConfigSection: View {
    @ObservedObject var bottle: Bottle
    @AppStorage("audioAdvancedMode") private var advancedMode: Bool = false
    @StateObject private var monitor = AudioDeviceMonitor()
    @State private var audioStatus: AudioStatus = .unknown

    var body: some View {
        Section("config.title.audio") {
            // Status line
            AudioStatusView(status: audioStatus)

            // Test buttons row
            AudioTestButtonsView(bottle: bottle, onStatusUpdate: { audioStatus = $0 })

            // Simple/Advanced toggle
            Picker("", selection: $advancedMode) {
                Text("config.audio.simple").tag(false)
                Text("config.audio.advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Settings
            AudioSettingsView(bottle: bottle, advancedMode: advancedMode)

            // Badge if advanced overrides active in Simple mode
            if !advancedMode, hasAdvancedAudioOverrides {
                advancedOverridesBadge
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Coupling CoreAudio monitoring to UI lifecycle**: The `AudioDeviceMonitor` should be a standalone service that can run independently. The UI subscribes to its output. Don't embed CoreAudio property listener setup inside SwiftUI view `onAppear`.
- **Polling CoreAudio properties on a tight loop**: Use `AudioObjectAddPropertyListenerBlock` for event-driven updates. The 5-10s timer is only for "audio engine alive" health checks, not for property queries.
- **Writing Wine registry from the main thread**: Registry writes via `Wine.addRegistryKey` are async and involve launching a Wine process. Always use `Task` and show a progress indicator.
- **Hardcoding probe logic in views**: All probe execution should live in WhiskyKit (`AudioProbe` protocol + concrete implementations). Views call probes and display results.
- **Storing hardware identifiers in device history**: Per decisions, only store device display name + transport type. No `AudioDeviceID`, UID, or manufacturer strings in the persisted history.
- **Showing test exe errors to users**: The WhiskyAudioTest.exe output is consumed by probe logic and translated into `AudioFinding` structures. Raw Wine stderr is only in "Technical details" collapsed section.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CoreAudio device enumeration | Manual `sysctl` or `system_profiler` parsing | `AudioObjectGetPropertyData` with `AudioObjectPropertyAddress` | The C API is stable, documented, and the only reliable way to get real-time audio device state |
| Device change notifications | Polling `system_profiler SPAudioDataType` | `AudioObjectAddPropertyListenerBlock` on `kAudioHardwarePropertyDefaultOutputDevice` | Event-driven, zero-overhead when no changes occur |
| Ring buffer for device history | Custom circular array | Swift `Array` with bounded `append` + `removeFirst` (same as `DiagnosisHistory`) | Phase 5's `DiagnosisHistory` already does exactly this pattern; follow it |
| Wine registry reads/writes | Direct file parsing of `.reg` files | Existing `Wine.addRegistryKey` / `Wine.queryRegistryKey` | Already in the codebase and handles Wine process lifecycle correctly |
| Settings persistence | Custom file I/O | `BottleSettings` with new `BottleAudioConfig` group + `PropertyListEncoder` | Matches all existing config groups exactly |
| Audio findings display | Custom card views | Phase 5's `RemediationCardView` + `ConfidenceTier` | Identical visual pattern; audio findings use the same card structure |
| Toast/notification display | Custom notification system | SwiftUI `.toast` modifier or similar lightweight pattern; `UNUserNotificationCenter` for background | Standard macOS notification approach |
| Sample rate detection | Manual CoreAudio probing | `kAudioDevicePropertyNominalSampleRate` via `AudioObjectGetPropertyData` | Single property query, returns `Float64` |

**Key insight:** The hardest genuinely new work is the CoreAudio C-API wrapper and the WhiskyAudioTest.exe. Everything else -- settings model, persistence, registry integration, UI sections, findings display, remediation cards -- has exact precedent in the existing codebase from Phases 4 and 5.

## Common Pitfalls

### Pitfall 1: CoreAudio API Thread Safety
**What goes wrong:** AudioObjectPropertyListenerBlock fires on the wrong queue, causing data races or SwiftUI main-thread violations.
**Why it happens:** CoreAudio callbacks execute on whatever queue you specify (or a HAL-internal queue if you don't). Swift 6 strict concurrency catches this.
**How to avoid:** Always pass `DispatchQueue.main` as the queue parameter to `AudioObjectAddPropertyListenerBlock`. The `AudioDeviceMonitor` class should be `@MainActor` or use `@unchecked Sendable` with explicit dispatch. All property queries should happen on a known queue.
**Warning signs:** Purple runtime warnings about main-thread access, or `@Sendable` closure violations in Swift 6.

### Pitfall 2: Listener Leak / Crash on Dealloc
**What goes wrong:** AudioObject property listeners are not removed when the monitor is deallocated, leading to callbacks into freed memory.
**Why it happens:** `AudioObjectAddPropertyListenerBlock` retains the block but does not automatically unregister on dealloc. Known issue documented in Apple Developer Forums.
**How to avoid:** Use `AudioObjectRemovePropertyListenerBlock` in `deinit`. Keep a reference to both the `AudioObjectPropertyAddress` and the block used for registration. Consider using `AudioObjectAddPropertyListener` (function pointer variant) instead of the block variant for easier removal in Swift.
**Warning signs:** Crashes when navigating away from the Audio panel, or when disconnecting audio devices.

### Pitfall 3: Wine Registry Write Timing
**What goes wrong:** User changes audio driver setting, immediately runs the test, and the test uses the old driver because the registry write hasn't propagated.
**Why it happens:** `Wine.addRegistryKey` launches a `wine reg add` process which takes 1-3 seconds. The new registry value is not visible to subsequent Wine processes until the wineserver updates its in-memory copy.
**How to avoid:** Await the registry write completion before enabling the "Test" button. Show a brief spinner during writes. For the "Reset Audio State" action, kill wineserver after clearing registry, then let it restart fresh.
**Warning signs:** Test results don't reflect settings changes; user thinks settings don't work.

### Pitfall 4: Bluetooth HFP Sample Rate Detection False Positives
**What goes wrong:** User connects Bluetooth headphones in A2DP mode (good quality), but the system briefly shows HFP sample rate during connection negotiation, triggering a false "degraded audio" warning.
**Why it happens:** macOS negotiates Bluetooth profiles asynchronously. The sample rate may briefly show 8000 Hz during SCO/HFP negotiation before switching to A2DP's 44100/48000 Hz.
**How to avoid:** Debounce sample rate change events with a 2-3 second delay before triggering alerts. If the rate recovers to a normal value within the debounce window, suppress the alert. Only flag "unusual" rates that persist beyond the debounce period.
**Warning signs:** Users getting "audio degraded" warnings every time they connect AirPods.

### Pitfall 5: WhiskyAudioTest.exe Wine Compatibility
**What goes wrong:** The bundled test exe crashes or produces no output in certain Wine configurations.
**Why it happens:** WASAPI support in Wine on macOS can be incomplete. The exe might use APIs that the specific Wine version doesn't fully implement.
**How to avoid:** Use the simplest possible Windows audio API: `waveOutOpen` + `waveOutWrite` from WinMM. This is the oldest and most reliably implemented audio API in Wine. Include a fallback code path that uses `Beep()` (synchronous kernel32 call) if waveOut initialization fails. Parse the exe's stdout JSON result line; treat any non-zero exit code or missing JSON as "probe failed" rather than "audio broken".
**Warning signs:** Test exe producing exit code -1073741819 (access violation) on certain Wine/macOS combinations.

### Pitfall 6: Unbounded Device Change Event History
**What goes wrong:** A flaky USB audio interface generates connect/disconnect events every few seconds, filling the ring buffer with noise.
**Why it happens:** Some USB audio devices have power management issues on macOS that cause rapid connect/disconnect cycles.
**How to avoid:** Deduplicate events: if the same device name generates the same event type within 30 seconds, coalesce into one entry. The ring buffer's 20-event limit provides a hard cap, but deduplication prevents useful older events from being evicted by noise.
**Warning signs:** Device history showing dozens of identical "disconnected/reconnected" entries for the same device.

## Code Examples

### CoreAudio Device Property Queries
```swift
// Query device name (CFString)
func queryDeviceName(_ deviceID: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
    guard status == noErr else { return nil }
    return name as String
}

// Query transport type (UInt32 -> enum)
func queryTransportType(_ deviceID: AudioDeviceID) -> AudioTransportType {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
    return AudioTransportType(rawValue: transport)
}

// Query nominal sample rate (Float64)
func querySampleRate(_ deviceID: AudioDeviceID) -> Double? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var rate: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
    guard status == noErr else { return nil }
    return rate
}

// Query output channel count via stream configuration
func queryOutputChannelCount(_ deviceID: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
    let bufferListPointer = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { bufferListPointer.deallocate() }
    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
    let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
    var channelCount = 0
    let buffers = UnsafeBufferPointer(
        start: &bufferList.pointee.mBuffers,
        count: Int(bufferList.pointee.mNumberBuffers)
    )
    for buffer in buffers {
        channelCount += Int(buffer.mNumberChannels)
    }
    return channelCount
}
```

### CoreAudio Transport Type Mapping
```swift
// AudioTransportType enum mapping CoreAudio constants
public enum AudioTransportType: Sendable, Codable, Equatable {
    case builtIn
    case usb
    case bluetooth
    case airPlay
    case hdmi
    case displayPort
    case thunderbolt
    case virtual
    case aggregate
    case unknown

    init(rawValue: UInt32) {
        switch rawValue {
        case kAudioDeviceTransportTypeBuiltIn:     self = .builtIn
        case kAudioDeviceTransportTypeUSB:          self = .usb
        case kAudioDeviceTransportTypeBluetooth:    self = .bluetooth
        case kAudioDeviceTransportTypeAirPlay:      self = .airPlay
        case kAudioDeviceTransportTypeHDMI:         self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort:  self = .displayPort
        case kAudioDeviceTransportTypeThunderbolt:  self = .thunderbolt
        case kAudioDeviceTransportTypeVirtual:      self = .virtual
        case kAudioDeviceTransportTypeAggregate:    self = .aggregate
        default:                                     self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .builtIn:      "Built-in"
        case .usb:          "USB"
        case .bluetooth:    "Bluetooth"
        case .airPlay:      "AirPlay"
        case .hdmi:         "HDMI"
        case .displayPort:  "DisplayPort"
        case .thunderbolt:  "Thunderbolt"
        case .virtual:      "Virtual"
        case .aggregate:    "Aggregate"
        case .unknown:      "Unknown"
        }
    }
}
```

### WhiskyAudioTest.exe (Minimal C source)
```c
// whisky_audio_test.c
// Compile: x86_64-w64-mingw32-gcc -o WhiskyAudioTest.exe whisky_audio_test.c -lwinmm
#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>

int main(int argc, char* argv[]) {
    int beep_mode = 0;
    if (argc > 1 && strcmp(argv[1], "--beep") == 0) {
        beep_mode = 1;
    }

    WAVEFORMATEX wfx;
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = 44100;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = wfx.nChannels * wfx.wBitsPerSample / 8;
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
    wfx.cbSize = 0;

    HWAVEOUT hWaveOut = NULL;
    MMRESULT result = waveOutOpen(&hWaveOut, WAVE_MAPPER, &wfx, 0, 0,
                                   CALLBACK_NULL);

    if (result != MMSYSERR_NOERROR) {
        printf("{\"status\":\"error\",\"api\":\"waveOut\",\"code\":%d}\n",
               result);
        return 1;
    }

    // Generate short test buffer (100ms of silence or tone)
    int samples = 44100 / 10;  // 100ms
    int bufSize = samples * wfx.nBlockAlign;
    char* buf = (char*)calloc(bufSize, 1);

    if (beep_mode) {
        // Generate 440Hz sine wave
        short* samples16 = (short*)buf;
        for (int i = 0; i < samples * 2; i += 2) {
            double t = (double)(i / 2) / 44100.0;
            short val = (short)(32767.0 * sin(2.0 * 3.14159265 * 440.0 * t));
            samples16[i] = val;      // left
            samples16[i + 1] = val;  // right
        }
    }

    WAVEHDR header;
    memset(&header, 0, sizeof(header));
    header.lpData = buf;
    header.dwBufferLength = bufSize;

    waveOutPrepareHeader(hWaveOut, &header, sizeof(header));
    result = waveOutWrite(hWaveOut, &header, sizeof(header));

    if (result != MMSYSERR_NOERROR) {
        printf("{\"status\":\"error\",\"api\":\"waveOutWrite\",\"code\":%d}\n",
               result);
        waveOutClose(hWaveOut);
        free(buf);
        return 1;
    }

    // Wait for playback to complete
    while (!(header.dwFlags & WHDR_DONE)) {
        Sleep(10);
    }

    waveOutUnprepareHeader(hWaveOut, &header, sizeof(header));
    waveOutClose(hWaveOut);
    free(buf);

    printf("{\"status\":\"ok\",\"api\":\"waveOut\",\"sampleRate\":44100,"
           "\"channels\":2,\"beep\":%s}\n",
           beep_mode ? "true" : "false");
    return 0;
}
```

### Wine Audio WINEDEBUG Channels
```
# Curated audio debugging preset
WINEDEBUG=+mmdevapi,+dsound,+winmm

# Key channels for audio troubleshooting:
# +mmdevapi  -- Windows multimedia device API (primary audio subsystem)
# +dsound    -- DirectSound buffer management
# +winmm     -- WinMM waveOut/waveIn (legacy audio API)
# +pulse     -- PulseAudio driver (Linux, not relevant for macOS)
# +coreaudio -- Not a Wine debug channel; Wine's coreaudio driver uses mmdevapi channel

# Example Wine audio error patterns:
# 0024:err:mmdevapi:DllGetClassObject Driver initialization failed
# 0024:err:mmdevapi:MMDevEnum_GetDefaultAudioEndpoint No default device found
# 0024:warn:dsound:DSOUND_ReopenDevice Failed to reopen device
```

### Existing WineRegistry Pattern for Audio Keys
```swift
// The existing WineRegistry pattern shows how to add audio registry helpers.
// Wine.addRegistryKey and Wine.queryRegistryKey are private but accessible
// within the Wine class extension. New audio registry methods follow the
// exact same pattern as retinaMode/changeDpiResolution:
//
// Source: WineRegistry.swift
// private static func addRegistryKey(bottle:key:name:data:type:)
// private static func queryRegistryKey(bottle:key:name:type:)
//
// Audio-specific keys:
// HKCU\Software\Wine\Drivers -> "Audio" (string: "coreaudio" or "")
// HKCU\Software\Wine\DirectSound -> "HelBuflen" (string: "512"/"65536"/"131072")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SimplyCoreAudio SPM package | Direct CoreAudio C API wrapping | March 2024 (SimplyCoreAudio archived) | Must use raw API; no maintained Swift wrapper exists |
| Wine 1.x ALSA/OSS drivers | Wine 9.x mmdevapi with coreaudio backend | Wine ~1.4+ (2012) | All modern Wine audio goes through mmdevapi; direct waveOut still works |
| winmm-only Wine audio | mmdevapi (WASAPI) as primary path | Wine 1.3.24+ | WASAPI/mmdevapi is Wine's primary audio stack; winmm is a thin wrapper |
| Manual registry editing for audio | Settings UI with registry backing | This phase | Users no longer need to open regedit for audio configuration |

**Deprecated/outdated:**
- `SimplyCoreAudio` (archived March 2024) -- do not use as a dependency
- Wine's old `wineaudio.drv` (removed) -- replaced by `winecoreaudio.drv` backing `mmdevapi`
- `kAudioObjectPropertyElementMaster` -- deprecated in macOS 12, use `kAudioObjectPropertyElementMain`

## Open Questions

1. **WhiskyAudioTest.exe build integration**
   - What we know: The exe should be compiled from C using MinGW and shipped in the app bundle. The source is straightforward (~80 lines).
   - What's unclear: How to integrate the MinGW build into Whisky's Xcode build process. Options: (a) pre-build and check in the binary, (b) add a build phase script, (c) use a Makefile target.
   - Recommendation: Pre-build the exe and check it into the repository under `Whisky/Resources/WhiskyAudioTest.exe`. This avoids requiring MinGW on every developer machine. Add a script in `scripts/` for rebuilding when the source changes. The exe is tiny (<20KB) and platform-independent (runs under Wine).

2. **CoreAudio listener removal in Swift**
   - What we know: `AudioObjectRemovePropertyListenerBlock` has documented issues in Swift (Apple Developer Forums thread from 2016, still relevant).
   - What's unclear: Whether the block-based API works correctly for removal in Swift 6 with strict concurrency.
   - Recommendation: Use the function-pointer variant (`AudioObjectAddPropertyListener` / `AudioObjectRemovePropertyListener`) wrapped in an `@unchecked Sendable` class. This is more verbose but avoids the block-removal bug. If the block variant works in testing, switch to it for cleaner code.

3. **Wine audio driver status probing**
   - What we know: We can check if the Wine registry has an Audio driver key set, and we can run the WhiskyAudioTest.exe to exercise the audio stack.
   - What's unclear: How to detect whether Wine's coreaudio driver has actually initialized successfully without running a test program. Wine logs `err:mmdevapi:DllGetClassObject Driver initialization failed` on failure, but only during process startup.
   - Recommendation: Treat the WhiskyAudioTest.exe as the definitive audio health check. Supplement with Wine log scanning using the curated WINEDEBUG preset. Don't try to probe Wine's internal audio state without running a Wine process.

4. **"Reset Audio State" implementation details**
   - What we know: The action should clear Wine's stored device GUID/UID mappings and restart the bottle. Wine stores device mappings in the registry under mmdevapi keys.
   - What's unclear: The exact registry keys Wine uses for device GUID persistence. The keys are in `HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices`.
   - Recommendation: Research the exact mmdevapi registry paths by examining Wine's `dlls/mmdevapi/devenum.c` source. As a safe fallback, the "Reset" action can delete the entire `MMDevices` subtree and restart wineserver, which forces Wine to re-enumerate devices from scratch.

5. **macOS notification permissions**
   - What we know: Background device-change notifications use `UNUserNotificationCenter`. macOS apps need to request notification permission.
   - What's unclear: Whether Whisky already requests notification permission. If not, adding this could be a user-facing change.
   - Recommendation: Check if Whisky already uses `UNUserNotificationCenter` anywhere. If not, the first notification attempt will trigger a system permission prompt. As an alternative, use `.alert` style which doesn't require permission on macOS. Fall back to logging if notification delivery fails.

6. **XAudio2/OpenAL dependency detection for Advanced panel**
   - What we know: The advanced diagnostics should show XAudio2 and OpenAL presence. These are typically installed via winetricks (`xact`, `xaudio2`, `openal`).
   - What's unclear: The exact DLL names and paths to check for presence in the Wine prefix.
   - Recommendation: Check for DLL existence in `drive_c/windows/system32/`: `xaudio2_7.dll` (XAudio2), `xaudio2_9.dll` (XAudio2 for Win10+), `openal32.dll` (OpenAL). This is a file existence check, not a registry check. The winetricks verb cache from Phase 2 can also indicate whether these were installed.

## Sources

### Primary (HIGH confidence)
- **Codebase analysis** -- Direct reading of BottleSettings.swift, BottleGraphicsConfig.swift, BottleWineConfig.swift, ConfigView.swift, GraphicsConfigSection.swift, WineRegistry.swift, WineEnvironment.swift, EnvironmentBuilder.swift, Wine.swift, CrashClassifier.swift, CrashDiagnosis.swift, RemediationAction.swift, RemediationCardView.swift, DiagnosticsView.swift, ConfidenceTier.swift, DiagnosisHistory.swift, RemediationTimeline.swift, DiagnosticExporter.swift, PatternLoader.swift, ProgramSettings.swift, Bottle.swift, ProcessRegistry.swift, GPUDetection.swift
- **WhiskyKit Package.swift** -- Swift 6, macOS 15+, SPM resource bundles for `Diagnostics/Resources/`
- [Apple Developer Documentation: kAudioDevicePropertyTransportType](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertytransporttype) -- Transport type constants (verified via search)
- [Apple Developer Documentation: AudioObjectPropertyAddress](https://developer.apple.com/documentation/coreaudio/audioobjectpropertyaddress) -- Core AudioObject API reference

### Secondary (MEDIUM confidence)
- [WineHQ Sound Wiki](https://gitlab.winehq.org/wine/wine/-/wikis/Sound) -- Wine audio architecture overview, driver selection
- [Wine dsound_main.c source](https://github.com/wine-mirror/wine/blob/master/dlls/dsound/dsound_main.c) -- Verified HelBuflen registry key and default value (65536)
- [Wine mmdevapi/devenum.c source](https://github.com/wine-mirror/wine/blob/master/dlls/mmdevapi/devenum.c) -- mmdevapi device enumeration source
- [Wine winecoreaudio.drv source](https://github.com/wine-mirror/wine/tree/master/dlls/winecoreaudio.drv) -- macOS CoreAudio Wine driver implementation
- [WineHQ Forums: audio driver registry](https://forum.winehq.org/viewtopic.php?t=17771) -- HKCU\Software\Wine\Drivers Audio key usage confirmed
- [GitHub gist: enumerate audio devices in Swift](https://gist.github.com/SteveTrewick/c0668ee438eb784cbc5fb4674f0c2cd1) -- CoreAudio device enumeration pattern
- [WineHQ commit: dsound HelBuflen setting](https://www.winehq.org/pipermail/wine-cvs/2007-August/034762.html) -- Original HelBuflen registry setting addition
- [Steve Rubin: macOS Bluetooth audio quality](https://ssrubin.com/posts/fixing-macos-bluetooth-headphone-audio-quality-issues-with-hammerspoon.html) -- Bluetooth HFP sample rate drop behavior
- [SimplyCoreAudio (archived March 2024)](https://github.com/rnine/SimplyCoreAudio) -- Reference for API patterns, but NOT suitable as dependency

### Tertiary (LOW confidence)
- WhiskyAudioTest.exe WASAPI fallback behavior -- Could not verify current Wine WASAPI completeness on macOS. WinMM/waveOut is recommended as primary API for maximum compatibility. WASAPI may work but needs testing.
- Wine mmdevapi device GUID persistence registry paths -- Exact keys under `HKLM\Software\Microsoft\Windows\CurrentVersion\MMDevices` need verification against Wine source. The "Reset Audio State" action may need to target specific subkeys.
- `AudioObjectRemovePropertyListenerBlock` Swift 6 compatibility -- Apple Developer Forums thread from 2016 flagged issues; needs validation in current Swift/macOS versions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- No new dependencies; CoreAudio framework is system-provided; all patterns have direct codebase precedent
- Architecture: HIGH -- Every component has an exact analog in Phase 4 or Phase 5; the config/section/diagnostics patterns are proven
- CoreAudio API: MEDIUM -- API is stable and well-documented but C-level; Swift wrapping requires careful handling of unsafe pointers and listener lifecycle
- Wine audio registry: MEDIUM -- HelBuflen and Drivers/Audio keys are verified in Wine source; exact mmdevapi device GUID paths need further verification
- WhiskyAudioTest.exe: LOW -- WinMM/waveOut approach is well-understood; actual behavior in Whisky's Wine build needs empirical testing
- Pitfalls: HIGH -- Identified from direct codebase analysis, Apple Developer Forums issues, and Wine audio architecture constraints

**Research date:** 2026-02-10
**Valid until:** 2026-03-12 (30 days -- stable domain, CoreAudio API is mature, Wine audio architecture changes slowly)
