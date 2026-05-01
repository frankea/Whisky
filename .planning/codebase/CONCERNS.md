# Codebase Concerns

**Analysis Date:** 2026-02-08

## Tech Debt

**Large Monolithic Configuration File:**
- Issue: `BottleSettings.swift` is 783 lines with multiple SwiftLint disables (`file_length`, `type_body_length`, `cyclomatic_complexity`, `function_body_length`)
- Files: `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift`
- Impact: Difficult to test individual settings, high complexity in `environmentVariables()` method, harder to navigate and maintain. Single changes affect large surface area.
- Fix approach: Split into focused configuration sub-types (WineSettings, GraphicsSettings, PerformanceSettings). Move environment variable construction to separate builders.

**Large Wine Execution Interface:**
- Issue: `Wine.swift` is 690 lines with `file_length` disabled, handles process execution, DXVK setup, log retention, and command generation
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift`
- Impact: Multiple responsibilities make testing difficult. Changes to one function risk breaking others. Termination handling and stream cleanup are complex.
- Fix approach: Extract Wine process execution into ProcessExecutor, log management into LogManager, command generation into CommandBuilder.

## Known Bugs and Platform Issues

**Hardcoded "crossover" Username Remaining:**
- Issue: ClickOnceManager still hardcodes "crossover" path in two locations despite changelog entry stating this was fixed
- Files: `WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift:77`, `WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift:250`
- Trigger: Using ClickOnce with Wine prefixes created with different usernames (CrossOver, wine, custom)
- Workaround: Manually set up ClickOnce directories with "crossover" username
- Fix approach: Use `WinePrefixValidation.getUserDirectory()` to detect actual username instead of hardcoding

**Platform-Specific Test Failures:**
- Issue: ClipboardManager tests skip in headless CI environments, indicating clipboard integration is fragile
- Files: `WhiskyKit/Tests/WhiskyKitTests/ClipboardManagerTests.swift`, `WhiskyKit/Tests/WhiskyKitTests/ClipboardManagerEdgeCaseTests.swift`
- Symptoms: Tests pass locally but fail in CI. Image clipboard operations skipped in headless mode.
- Current mitigation: Tests skip gracefully with `#available` checks
- Recommendations: Add platform detection utilities, mock clipboard for CI, or redesign clipboard integration to use system frameworks

**TempFileTracker Lock Detection Variations:**
- Issue: TempFileTracker uses `isFileLocked()` which may behave differently across macOS versions and file systems
- Files: `WhiskyKit/Sources/WhiskyKit/TempFileTracker.swift:135-149`
- Symptoms: Cleanup failures on certain file systems or with certain process states
- Current mitigation: Exponential backoff retry logic (1s, 2s, 4s)
- Recommendations: Add file system type detection, improve lock detection for NFS/SMB shares

## Security Considerations

**Shell Escaping Complexity and Pre-Escaped Flag:**
- Risk: The `preEscaped` parameter in `Wine.generateRunCommand()` creates two code paths that could lead to injection if misused
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:302-320`
- Current mitigation: Default `preEscaped: Bool = false` makes safe usage the default
- Recommendations: Remove `preEscaped` parameter entirely, always escape args. Validate all callers use escaped arguments.

**Environment Variable Key Validation:**
- Risk: `isValidEnvKey()` validates environment keys but the validation logic is simple (alphanumeric + underscore)
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:95`, used in `generateRunCommand()` and `generateTerminalEnvironmentCommand()`
- Current mitigation: Keys that fail validation are logged and skipped
- Recommendations: Add explicit test for environment key validation edge cases, document the validation rules

**Log Files May Contain Sensitive Data:**
- Risk: Wine process output logs may contain command-line arguments or environment data from user programs
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:630-667` (log retention), `WhiskyKit/Sources/WhiskyKit/Extensions/FileHandle+Extensions.swift`
- Current mitigation: CHANGELOG notes "Process environment logging now records keys only (not values)"
- Recommendations: Add log sanitization layer to strip sensitive patterns (paths, URLs, API keys), implement log encryption at rest

## Performance Bottlenecks

**Inefficient Icon Caching and Extraction:**
- Problem: Icon cache files may accumulate; PE binary parsing for icon extraction could be slow for large executables
- Files: `WhiskyKit/Sources/WhiskyKit/PE/IconCache.swift`, `WhiskyKit/Sources/WhiskyKit/PE/PortableExecutable.swift:257 lines`
- Cause: No size limits on cache, PE parsing does complete file reads before extraction
- Improvement path: Implement cache size limits with LRU eviction, stream-based PE parsing to stop after finding icon resources

**Log Retention Enforcement Overhead:**
- Problem: `Wine.enforceLogRetention()` runs synchronously, scanning directory on every program execution
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:630-667`
- Cause: Accumulating log files over time could slow directory traversal
- Improvement path: Use timer-based enforcement instead of per-execution, async directory enumeration with progress tracking

**ClickOnce Detection Full Directory Recursion:**
- Problem: `ClickOnceManager.detectAppRefFile()` recursively scans entire ClickOnce directory
- Files: `WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift:73-103`
- Cause: Could be slow with deeply nested or many files
- Improvement path: Depth limit on recursion, cache results per bottle, add progress callbacks

## Fragile Areas

**ProcessRegistry Cleanup on App Termination:**
- Files: `WhiskyKit/Sources/WhiskyKit/ProcessRegistry.swift:150-230`
- Why fragile: Uses ObjectIdentifier tracking that depends on Process instance lifetime. SIGTERM timeout (5 seconds) is hardcoded. Force kill via SIGKILL may corrupt Wine prefix state.
- Safe modification: Add timeouts as configurable constants, add soft-landing mode that waits for wineserver graceful shutdown first
- Test coverage: Basic registration/unregistration tested, but cleanup timing and SIGKILL behavior not covered

**TempFileTracker Retry Logic with Race Conditions:**
- Files: `WhiskyKit/Sources/WhiskyKit/TempFileTracker.swift:132-160`
- Why fragile: File locks checked before deletion, but file could be re-locked between check and deletion. Exponential backoff timing is linear (2^n seconds)
- Safe modification: Use atomic delete-or-lock, implement proper timeout floors to avoid excessive delays
- Test coverage: Locked file tests skip on some platforms

**Wine Environment Variable Cascade:**
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift:362-375`, `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift`
- Why fragile: User settings override bottle settings which override Wine defaults, but merge logic is scattered. Order of operations matters.
- Safe modification: Implement explicit EnvironmentBuilder with documented precedence rules, add builder tests for all precedence combinations
- Test coverage: Individual variable tests exist but precedence combinations are limited

**ClickOnce Manifest URL Parsing:**
- Files: `WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift:131-200`
- Why fragile: Handles percent-encoding variations (single and double), but URL validation is loose. normalizeURLString tries decode-once then decode-twice.
- Safe modification: Add explicit test cases for malformed URLs, add URL scheme validation (http/https only)
- Test coverage: Not directly tested; edge cases unknown

## Scaling Limits

**Wine Process Log Accumulation:**
- Current capacity: Logs capped at 5GB total per retention policy in changelog
- Limit: On low-disk systems or with long sessions, 5GB could fill storage
- Scaling path: Implement per-session log rotation, compressed log archiving, configurable retention size

**Icon Cache File Count:**
- Current capacity: No documented limit
- Limit: Could accumulate to thousands of cache files
- Scaling path: Implement cache pruning with configurable max files, add age-based cleanup

**ProcessRegistry In-Memory Tracking:**
- Current capacity: All active processes tracked in memory
- Limit: Long-running sessions with many program launches could accumulate stale references
- Scaling path: Add automatic cleanup of terminated processes, implement bounded registry size

## Dependencies at Risk

**SwiftFormat Version Lock:**
- Risk: Exact version required (0.58.7), CI enforces it. If version is no longer available or has bugs, upgrade is forced.
- Impact: Code style becomes inconsistent if version is lost, harder to onboard contributors if they use different version
- Migration plan: Document pinned version in CLAUDE.md (already done), consider moving to configuration-based formatting to reduce version coupling

**Sendable Safety with @unchecked:**
- Risk: ProcessRegistry and TempFileTracker use `@unchecked Sendable` to suppress Swift 6 concurrency checks
- Impact: Could mask actual thread safety issues that @unchecked is hiding
- Migration plan: Replace NSLock-protected storage with Swift Concurrency primitives (actors or locks), remove @unchecked

## Test Coverage Gaps

**Binary PE Parsing Not Fully Tested:**
- What's not tested: Edge cases in PE file structure parsing (corrupt headers, truncated sections, unusual resource layouts)
- Files: `WhiskyKit/Sources/WhiskyKit/PE/PortableExecutable.swift:257 lines`, `WhiskyKit/Sources/WhiskyKit/PE/Section.swift`, `WhiskyKit/Sources/WhiskyKit/PE/COFFFileHeader.swift`, `WhiskyKit/Sources/WhiskyKit/PE/OptionalHeader.swift`
- Risk: Malformed PE files could crash parser or produce incorrect results
- Priority: High - affects icon extraction for untrusted programs

**Extension Methods Not Tested:**
- What's not tested: FileHandle, FileManager, Logger, Bundle, URL extensions
- Files: `WhiskyKit/Sources/WhiskyKit/Extensions/FileHandle+Extensions.swift:254 lines`, `WhiskyKit/Sources/WhiskyKit/Extensions/FileManager+Extensions.swift`, `WhiskyKit/Sources/WhiskyKit/Extensions/Logger+Extensions.swift`, `WhiskyKit/Sources/WhiskyKit/Extensions/URL+Extensions.swift`
- Risk: Breaking changes to these extensions affect all code using them
- Priority: Medium - these are utilities but widely used

**macOS Compatibility Thresholds:**
- What's not tested: MacOSVersion comparison and compatibility flags
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/MacOSCompatibility.swift`
- Risk: Version checks could fail on edge cases or future macOS versions
- Priority: Medium - affects feature gates and debug mode selection

**Bottle Settings Precedence:**
- What's not tested: Complex precedence rules when user settings override bottle settings which override program settings
- Files: `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift:525-700 (environmentVariables method)`
- Risk: Settings precedence bugs could silently disable optimizations or safety features
- Priority: High - affects game compatibility and performance

**WineRegistry and Configuration Serialization:**
- What's not tested: Round-trip serialization of complex nested settings types
- Files: `WhiskyKit/Sources/WhiskyKit/Wine/WineRegistry.swift`
- Risk: Settings could be lost or corrupted on save/load cycles
- Priority: Medium - affects long-term data integrity

**ClickOnceManager Installation Path:**
- What's not tested: Directory creation, permission handling, manifest installation to actual Wine prefix
- Files: `WhiskyKit/Sources/WhiskyKit/ClickOnceManager.swift:239-280 (install method)`
- Risk: Installation could fail silently or partially
- Priority: Low - ClickOnce is niche use case

## Missing Critical Features

**No Progress Reporting for Long Operations:**
- Problem: Wine prefix initialization, DXVK installation, winetricks execution, log retention enforcement all block without progress feedback
- Blocks: UI cannot show progress or allow cancellation
- Impact: Large operations feel frozen; user unsure if app is responsive

**No Configuration Validation:**
- Problem: BottleSettings can be set to invalid combinations (e.g., Windows version incompatible with DX version)
- Blocks: Programs may fail mysteriously due to invalid settings
- Impact: Hard to debug user configuration issues

**No Backup/Recovery for Settings:**
- Problem: Lost settings.plist corrupts entire bottle configuration
- Blocks: Recovery requires manual reconstruction or backup restore
- Impact: User frustration if settings file is corrupted

---

*Concerns audit: 2026-02-08*
