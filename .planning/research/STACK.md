# Stack Research

**Domain:** Wine bottle management macOS app -- tooling for addressing 435+ upstream issues
**Researched:** 2026-02-08
**Confidence:** MEDIUM (existing stack is well-understood; some recommendations rely on ecosystem assessment rather than library-specific docs)

## Existing Stack (Do Not Change)

These are already in the project and are not up for reconsideration. Documented here for completeness and to prevent redundant research.

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Swift 6 | 6.0 | Language | In use, strict concurrency enabled |
| SwiftUI | macOS 15+ | UI framework | In use throughout app |
| WhiskyKit | Local SPM | Core logic package | In use, actively developed |
| Sparkle | 2.8.1 | Auto-update framework | In use via SPM |
| SemanticVersion | 0.4.0 | Version parsing | In use in WhiskyKit |
| Swift Argument Parser | 1.5.0 | CLI argument parsing | In use in WhiskyCmd |
| SwiftFormat | 0.58.7 | Code formatting | CI-enforced, exact version required |
| SwiftLint | latest | Linting | CI-enforced |
| Wine 11.0 | Consumed binary | Windows compatibility layer | Bundled as WhiskyWine |
| PropertyList (plist) | System | Settings persistence | Bottle settings serialized to XML plist |

## Recommended Stack Additions

### 1. Wine Configuration Management and Troubleshooting Automation

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| WINEDEBUG channel parsing | Wine 11.0 built-in | Automated crash analysis | Wine's `WINEDEBUG` env var with `+seh`, `+relay`, `+timestamp` channels provides structured error data. Parse `err:`, `warn:`, `fixme:` prefixes and `c0000005` (access violation) patterns from log output to auto-classify crashes. Already capturing Wine output via `AsyncStream<ProcessOutput>` -- add a log analyzer layer on top. | HIGH |
| `os.log` / `Logger` (Apple) | macOS 15+ built-in | Structured app-side logging | Already in use (`Logger(subsystem:category:)`). Extend by defining more categories: one per module (Wine, Launcher, DXVK, Bottle, GPU). Use `.error` level for actionable issues, `.debug` for troubleshooting traces. Cost: zero dependencies. | HIGH |
| `OSLogStore` | macOS 15+ built-in | Programmatic log retrieval | Use `OSLogStore(scope: .currentProcessIdentifier)` to retrieve recent Whisky-side logs for inclusion in diagnostic reports, replacing the current file-based log tail approach in `StabilityDiagnostics`. Enables filtering by subsystem/category and time range. Limitation: only captures current process logs, not Wine subprocess output (keep file-based logs for Wine). | MEDIUM |
| Winetricks automation | Latest (shell script) | Dependency installation | Already partially integrated via `WinetricksView`. For systematic issue fixing, automate common winetricks verbs (vcrun2019, dotnet48, d3dx9, dxvk) with pre-validation using `WinePrefixValidation` to check prerequisites before running. No library needed -- shell out to bundled winetricks script. | HIGH |
| Wine registry manipulation | Wine 11.0 built-in | Per-app configuration | Already have `WineRegistry` class. Extend to support programmatic registry edits for game-specific fixes (DPI overrides, compatibility modes, DLL redirects) without requiring users to use regedit. Pattern: define registry fix profiles as `Codable` structs, apply via `Wine.runWine(["reg", "add", ...])`. | HIGH |

**Rationale:** The project already has the foundation for Wine troubleshooting (log capture, diagnostic reports, prefix validation). The gap is **automated analysis** -- parsing Wine output to detect known error patterns and suggesting fixes. This requires no new dependencies, only new logic layered on existing infrastructure.

### 2. macOS App Diagnostics and Crash Reporting

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| MetricKit (`MXCrashDiagnostic`) | macOS 12+ built-in | System-level crash capture | Captures crashes that in-process reporters miss (memory pressure, background terminations, OS signals). Zero dependency cost. Delivers diagnostic reports immediately on macOS 12+. Implement `MXMetricManagerSubscriber` to collect crash data and include in `StabilityDiagnostics` reports. | HIGH |
| Apple's Unified Logging | macOS 15+ built-in | Structured diagnostics | Already using `Logger`. Add `signpost` intervals for Wine process lifecycle (start, output, termination) to enable Instruments profiling of launch times and hang detection. | MEDIUM |
| `StabilityDiagnostics` (existing) | In-project | Diagnostic report generation | Already built. Extend with: (a) Wine log pattern analysis, (b) MetricKit crash data, (c) prefix health checks, (d) GPU capability summary. Keep report bounded and privacy-safe (existing design). | HIGH |

**What NOT to use for crash reporting:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Sentry SDK (sentry-cocoa 9.x) | Adds 3rd-party dependency + data collection to a privacy-focused open-source app. Requires server infrastructure or paid account. macOS needs extra config (`enableUncaughtNSExceptionReporting`). Overkill for this use case. | MetricKit (free, built-in, no data leaves device) + existing `StabilityDiagnostics` |
| PLCrashReporter 1.12.x | Adds binary framework dependency. Signal handler limitations with Swift. MetricKit covers the same crash types since macOS 12 with less complexity. | MetricKit |
| Firebase Crashlytics | Google dependency, requires Google account, data collection concerns for open-source app. | MetricKit |

**Rationale:** Whisky is a privacy-focused open-source app distributed outside the App Store. Adding third-party crash reporting services would conflict with the project's values and add unnecessary dependencies. MetricKit provides system-level crash data with zero dependencies, and the existing `StabilityDiagnostics` infrastructure handles user-facing diagnostic reports.

### 3. Game Compatibility Database and Per-App Configuration

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Local JSON compatibility database | Custom | Per-game configuration profiles | Ship a bundled JSON file mapping game executables (by name or Steam AppID) to known-good Wine configurations. Structure: `{ "games": [{ "name": "...", "patterns": ["*.exe"], "settings": { "dxvk": true, "forceD3D11": true, ... }, "status": "gold" }] }`. Update via GitHub releases alongside WhiskyWine binaries. | HIGH |
| `ProgramSettings` (existing) | In-project | Per-program overrides | Already exists but underutilized. Extend to support all `BottleSettings` overrides at per-program level. Configuration cascade: game DB defaults -> bottle settings -> program settings -> user overrides. | HIGH |
| Community compatibility reports | GitHub Discussions | Crowdsourced testing data | Whisky-App already has a [Game List discussion](https://github.com/orgs/Whisky-App/discussions/348) with Platinum/Gold/Silver/Bronze/Borked ratings. Formalize into structured data that feeds the local JSON database. No API needed -- maintain as a curated file in the repo. | MEDIUM |

**What NOT to use for compatibility data:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| ProtonDB API | ProtonDB is Linux/Proton-specific. Proton includes patches not in vanilla Wine. Compatibility ratings don't transfer to macOS+Wine 11+D3DMetal stack. The community API deployment was terminated due to budget. | Local curated database specific to macOS/WhiskyWine |
| WineHQ AppDB scraping | No official API. AppDB data is Wine-version-specific and not macOS-focused. Web scraping is fragile and ToS-questionable. | Local curated database |
| Live API calls for compatibility | Adds network dependency, latency, and failure modes to app launch. Privacy concern (leaks which games user runs). | Bundled JSON updated with releases |

**Rationale:** macOS+Wine compatibility is fundamentally different from Linux+Proton compatibility. D3DMetal, MoltenVK, and Apple Silicon specifics mean ProtonDB/AppDB data does not reliably transfer. A curated local database specific to WhiskyWine is more accurate and avoids network/privacy concerns.

### 4. SwiftUI Patterns for Complex Settings/Configuration UIs

| Pattern | Where to Apply | Why Recommended | Confidence |
|---------|---------------|-----------------|------------|
| `Form` + `.formStyle(.grouped)` + `DisclosureGroup` | Already in `ConfigView` | Current pattern is correct. Keep using it. Each config section (`WineConfigSection`, `LauncherConfigSection`, etc.) is a `DisclosureGroup` inside a grouped `Form`. This matches Apple's Settings app patterns. | HIGH |
| `@AppStorage` for UI state | Already in `ConfigView` | Section expansion states are persisted via `@AppStorage`. This is the right pattern -- keep using it for all non-model UI preferences. | HIGH |
| Progressive disclosure with conditional content | Already in `LauncherConfigSection` | Current pattern of showing sub-settings only when parent toggle is enabled (e.g., GPU vendor picker shown only when GPU spoofing enabled) is correct. Apply consistently across all sections. | HIGH |
| `SettingItemView` (existing) | Bottle config sections | Already have a reusable setting item component. Use for consistency across all config sections. | HIGH |
| `Inspector` modifier (macOS 14+) | Per-program settings panel | Use `.inspector(isPresented:)` for showing per-program configuration overrides in a trailing column when a program is selected. Better than sheet/popover for settings that users reference while configuring. Available since macOS 14. | MEDIUM |
| Migrate to `@Observable` macro | `Bottle`, `BottleVM`, `CheckForUpdatesViewModel` | Current code uses `@ObservableObject` + `@ObservedObject` + `@Published`. The `@Observable` macro (Swift 5.9+, macOS 14+) provides better performance by only invalidating views that read changed properties. Since the deployment target is already macOS 15, migration is safe. **Caveat:** `@Observable` requires classes (already the case for `Bottle`). Migration is incremental -- can be done class-by-class. `@StateObject` to `@State` migration needs care (see Alternatives). | MEDIUM |

**What NOT to use for settings UI:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| sindresorhus/Settings package (3.1.1) | Designed for app-level Settings window. Whisky's config is per-bottle, not app-level. The package adds a dependency for something SwiftUI's built-in `Form` + `DisclosureGroup` already handles well. | Native SwiftUI `Form` with `.formStyle(.grouped)` (already in use) |
| Custom NSViewRepresentable for settings | Unnecessary complexity. SwiftUI's macOS Form support is mature enough since macOS 13 for this use case. AppKit bridging adds maintenance burden. | Pure SwiftUI |
| TabView for config sections | Config sections have variable importance and users need to see multiple sections at once. Tabs hide all non-selected content. The current scrollable `Form` with collapsible `DisclosureGroup`s is superior for this use case. | `Form` + `DisclosureGroup` (current approach) |

**`@Observable` migration notes:**

The migration from `ObservableObject` to `@Observable` is worthwhile but has a critical gotcha: `@StateObject` provides deferred, one-time initialization (via `@autoclosure`), while `@State` with `@Observable` classes does not guarantee single initialization. For `Bottle` objects that own Wine state, ensure they are created once and passed down, not recreated on view rebuilds. Migration strategy:
1. Start with leaf view models (`CheckForUpdatesViewModel`)
2. Progress to `BottleVM`
3. `Bottle` last (most complex, most consumers)

## Supporting Libraries (Already Available, No New Dependencies)

| Library | Purpose | When to Use |
|---------|---------|-------------|
| `Foundation.Process` | Wine/winetricks subprocess execution | Already used throughout. No changes needed. |
| `os.log` / `Logger` | Structured logging | Already used. Extend categories. |
| `MetricKit` | System-level diagnostics | Add subscriber for crash/hang/CPU diagnostics. |
| `PropertyListEncoder/Decoder` | Settings persistence | Already used for bottle settings. |
| `NSWorkspace` | File/app operations | Already used for opening URLs, launching apps. |

## Version Compatibility Matrix

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| Swift 6.0 | macOS 15+ deployment target | Strict concurrency required, `@MainActor` isolation |
| SwiftUI (macOS 15) | `@Observable` macro, `Inspector`, `Form.grouped` | All recommended patterns available |
| Wine 11.0 | DXVK-macOS, MoltenVK 1.4.x, D3DMetal | WhiskyWine bundles all three |
| MetricKit | macOS 12+ (immediate delivery macOS 12+) | Well within macOS 15 deployment target |
| Sparkle 2.8.1 | macOS 10.13+, SPM | Current version, no update needed |
| `OSLogStore` | macOS 15+ (`.currentProcessIdentifier`) | Full functionality at deployment target |

## Stack Patterns by Issue Category

**If addressing stability issues (crashes, hangs):**
- Use MetricKit `MXCrashDiagnostic` + `MXHangDiagnostic` for system-level data
- Use WINEDEBUG `+seh` channel parsing for Wine-side crash analysis
- Extend `StabilityDiagnostics` with automated pattern matching
- Because: most stability issues are in Wine subprocess, not Whisky app itself

**If addressing launcher compatibility (Steam, EA, Rockstar):**
- Use `LauncherPresets` environment overrides (already built)
- Use Wine registry manipulation for launcher-specific fixes
- Add to local compatibility database with launcher-specific entries
- Because: launcher fixes are primarily environment variable and registry configuration

**If addressing game compatibility (per-game fixes):**
- Use local JSON compatibility database for known-good configurations
- Extend `ProgramSettings` for per-program overrides
- Use `Inspector` modifier for per-program settings UI
- Because: games need individual configuration that differs from bottle defaults

**If addressing UI/UX improvements:**
- Use current `Form` + `DisclosureGroup` pattern (proven, already working)
- Migrate to `@Observable` incrementally for performance gains
- Use `Inspector` for contextual settings panels
- Because: the current UI pattern is correct; improvements are incremental

## Sources

- [Wine Debug Channels Wiki](https://wiki.winehq.org/Debug_Channels) -- WINEDEBUG environment variable and channel documentation (HIGH confidence)
- [Apple MetricKit Documentation](https://developer.apple.com/documentation/MetricKit) -- MXCrashDiagnostic, system-level crash reporting (HIGH confidence)
- [Apple OSLogStore Documentation](https://developer.apple.com/documentation/os/oslogstore) -- Programmatic log retrieval (HIGH confidence)
- [Apple SwiftUI Settings Documentation](https://developer.apple.com/documentation/swiftui/settings) -- Settings scene and Form patterns (HIGH confidence)
- [Apple @Observable Migration Guide](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro) -- ObservableObject to Observable migration (HIGH confidence)
- [Apple Inspector API](https://developer.apple.com/videos/play/wwdc2023/10161/) -- WWDC23 Inspector view modifier (HIGH confidence)
- [Whisky-App Game List Discussion](https://github.com/orgs/Whisky-App/discussions/348) -- Community compatibility reports (MEDIUM confidence)
- [ProtonDB](https://www.protondb.com/) -- Linux/Proton compatibility data, NOT transferable to macOS (used as counter-example)
- [PLCrashReporter 1.12.2](https://github.com/microsoft/plcrashreporter) -- Evaluated and rejected for this use case (MEDIUM confidence)
- [Sentry Cocoa 9.4.0](https://github.com/getsentry/sentry-cocoa) -- Evaluated and rejected for this use case (MEDIUM confidence)
- [Winetricks](https://github.com/Winetricks/winetricks) -- Wine configuration automation script (HIGH confidence)
- [MoltenVK 1.4.0](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.0) -- Vulkan 1.4 on macOS via Metal (MEDIUM confidence on exact version)
- [SwiftUI for Mac 2025](https://troz.net/post/2025/swiftui-mac-2025/) -- Current SwiftUI macOS patterns assessment (MEDIUM confidence)

---
*Stack research for: Wine bottle management macOS app -- tooling for 435+ upstream issues*
*Researched: 2026-02-08*
