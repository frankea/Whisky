# Coding Conventions

**Analysis Date:** 2026-02-08

## Naming Patterns

**Files:**
- PascalCase for all Swift files: `Bottle.swift`, `Program.swift`, `ClickOnceManager.swift`
- Test files mirror source names with `Tests` suffix: `ProgramTests.swift`, `BottleSettingsTests.swift`
- Grouped test files use logical prefixes: `ClipboardManagerTests.swift`, `ClipboardManagerEdgeCaseTests.swift`

**Functions:**
- camelCase for all functions: `createBottle()`, `generateEnvironment()`, `detectAppRefFile(in:)`
- Verb-first naming: `validate()`, `parse()`, `sanitize()`, `extract()`
- Private functions use same convention: `private func saveSettings()`
- Static utility functions grouped in classes: `Wine.isValidEnvKey(_:)`, `Wine.isAsciiLetter(_:)`

**Variables:**
- camelCase for all variables: `bottleURL`, `tempDir`, `programURL`, `isAvailable`
- Boolean properties are prefixed with verbs: `pinned`, `inFlight`, `isAvailable`, `isLarge()`
- Published properties are explicitly marked: `@Published public var settings: BottleSettings`
- Private properties use underscore prefix convention in class context: `private let logger`

**Types:**
- PascalCase for types: `Bottle`, `Program`, `BottleSettings`, `WinVersion`
- Enums use PascalCase: `BottleCreationError`, `WineInterfaceError`, `ClipboardContent`
- Protocol names typically end in -able: `Sendable`, `Codable`, `Identifiable`, `Equatable`, `Hashable`
- Error enums conform to `LocalizedError` and implement `errorDescription`

**Constants:**
- UPPER_SNAKE_CASE for constants: `largeContentThreshold`, but some use camelCase when defining static properties
- Example: `public static let largeContentThreshold: Int = 10 * 1_024 // 10 KB`
- Private constants use lowercase with leading underscore: `private let maxRetries`

## Code Style

**Formatting:**
- SwiftFormat 0.58.7 required (CI enforces exact version)
- 4-space indentation
- 120 character line limit
- LF line endings (not CRLF)
- Removed redundant self references (disabled rule in `.swiftformat`)
- `--wraparguments before-first` and `--wrapparameters before-first` for multiline calls

**Linting:**
- SwiftLint enforces:
  - No force unwrapping (`!`) - opt_in_rules include `force_unwrapping`
  - GPL v3 file header on every Swift file (required, severity: error)
  - Header pattern enforced from `.swiftlint.yml`
- Disabled conflicts between SwiftFormat and SwiftLint (`trailingCommas`, `redundantExtensionACL`)

**File Header Pattern:**
Every Swift file must start with:
```swift
//
//  FileName.swift
//  TargetName
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//
```

## Import Organization

**Order:**
1. Standard library imports: `import Foundation`, `import os.log`, `import AppKit`
2. Framework imports: `import SwiftUI`, `import SemanticVersion`
3. Internal module imports: `@testable import WhiskyKit` (test files only)
4. Local module imports: `import WhiskyKit`

**Path Aliases:**
- None detected in current codebase
- Import statements use fully qualified module names

**Example import block from `BottleSettingsTests.swift`:**
```swift
import SemanticVersion
@testable import WhiskyKit
import XCTest
```

## Error Handling

**Patterns:**
- Custom error types conform to `LocalizedError` and implement `errorDescription: String?`
- Error enums use associated values for context: `case pathTraversal(path: String)`
- Example from `TarError.swift`:
```swift
public enum TarError: LocalizedError {
    case pathTraversal(path: String)
    case unsafeSymlink(path: String, target: String)
    case commandFailed(output: String)

    public var errorDescription: String? {
        switch self {
        case let .pathTraversal(path):
            "Archive contains unsafe path that escapes target directory: \(path)"
        // ...
        }
    }
}
```

- Error throwing uses descriptive cases: `throw ClickOnceError.fileNotFound(url)`
- Try-catch in critical paths logs before re-throwing or providing defaults
- Silent failures in initialization catch and log with `Logger.wineKit.error(...)`

**Example from `Program.swift` initialization:**
```swift
do {
    self.settings = try ProgramSettings.decode(from: settingsUrl)
} catch {
    Logger.wineKit.error("Failed to load settings for `\(name)`: \(error)")
    self.settings = ProgramSettings()
}
```

## Logging

**Framework:** `os.log` with `Logger` class from Foundation
- Not `print()` or standard console logging
- Private logger instances per class: `private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ClassName")`

**Levels and Usage:**
- `.debug()` - Low-level operational details: `logger.debug("ClickOnce directory not found")`
- `.info()` - General operational flow: `logger.info("Detected N ClickOnce applications")`
- `.warning()` - Potentially problematic situations: `logger.warning("Large clipboard content detected")`
- `.error()` - Error conditions requiring attention: `logger.error("Failed to load settings")`

**Patterns:**
- Log on significant state changes: `logger.info("Registered process")`
- Log when resources are locked or retried: `logger.warning("File is locked, attempt N/M")`
- Log successful completion of important operations: `logger.info("Successfully cleaned up file")`
- Log parse/extraction results at debug level: `logger.debug("Parsed ClickOnce manifest")`

**Example from `TempFileTracker.swift`:**
```swift
private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "TempFileTracker")
logger.debug("Registered temp file")
logger.warning("File is locked, attempt 1/3")
logger.info("Successfully cleaned up file")
logger.error("Failed to cleanup after 3 attempts")
```

## Comments

**When to Comment:**
- Document complex algorithms or non-obvious security implications: `// Note: Uses explicit ASCII checks rather than Swift's Unicode-aware methods...`
- Explain why something is done, not what: `// Warning: This will break if two programs share the same name`
- Note intentional limitations or known issues: `// Note: The argument splitting doesn't handle quoted arguments`

**JSDoc/TSDoc Style (Swift Doc):**
- Documentation uses triple-slash `///` for public API elements
- Structured with headings like `## Overview`, `## Usage`, `## Topics`
- Include code examples in triple-backtick markdown blocks
- Parameter documentation uses `- Parameter name:` or `- Parameters:`
- Return documentation uses `- Returns:`
- Exception documentation uses `- Throws:`

**Example from `Bottle.swift`:**
```swift
/// Represents an isolated Wine environment for running Windows applications.
///
/// A bottle is a Wine prefix—a self-contained directory containing a Windows-like
/// filesystem, registry, and configuration. Each bottle can have different Windows
/// versions, installed programs, and settings without affecting other bottles.
///
/// ## Overview
/// Bottles are the primary organizational unit in Whisky. Users can create multiple
/// bottles for different games or applications, each with its own configuration.
///
/// ## Creating a Bottle
///
/// ```swift
/// let bottle = Bottle(bottleUrl: bottleURL)
/// ```
///
/// - Parameters:
///   - bottleUrl: The URL to the bottle's root directory.
///   - inFlight: Whether the bottle is currently being created. Defaults to `false`.
/// - Throws: Never
```

## Function Design

**Size:**
- Functions typically 10-50 lines
- Longer functions broken into smaller helpers with descriptive names
- Private helper functions perform specific tasks: `createBottleDirectory()`, `persistBottleCreation()`

**Parameters:**
- Use explicit parameter names: `func runProgram(at url: URL, args: [String], bottle: Bottle)`
- Named parameters required for clarity (no positional-only parameters)
- Default values for optional settings: `public func cleanupWithRetry(file: URL, maxRetries: Int = 3)`

**Return Values:**
- Prefer returning simple types: `String`, `URL`, `[URL]`, `[String: String]`
- Use tuples for related return values: `(pin: PinnedProgram, program: Program, id: String)`
- Complex objects returned from initializers: `Bottle(bottleUrl: URL)`
- Async functions return via `AsyncStream` for streaming: `AsyncStream<ProcessOutput>`

**Actor Isolation:**
- Use `@MainActor` on types that manage UI state: `@MainActor public final class Bottle`
- Use `nonisolated` for thread-safe identity access: `public nonisolated var id: URL { url }`
- Cross-actor operations documented with requirements: `@MainActor func method()`

## Module Design

**Exports:**
- Use `public` for APIs intended for library consumption
- `internal` or undecorated for private module implementation
- Consistent access control across related types

**Barrel Files:**
- Not extensively used
- Main modules organized by feature: `Whisky/`, `Wine/`, `PE/`, `Utils/`

**Example Module Structure from `WhiskyKit/Sources/WhiskyKit/`:**
```
Whisky/
  - Bottle.swift (core model)
  - Program.swift (core model)
  - BottleSettings.swift (configuration)
  - BottleVM.swift (UI state - in main app)

Wine/
  - Wine.swift (process execution)
  - WineEnvironment.swift (configuration)
  - WineRegistry.swift (registry access)
  - LauncherPresets.swift (defaults)

PE/
  - PortableExecutable.swift (parser)
  - IconCache.swift (caching)
  - Magic.swift (file type detection)

Utils/
  - TempFileTracker.swift (resource cleanup)
  - ProcessRegistry.swift (process tracking)
  - ClipboardManager.swift (clipboard operations)
```

## Mark Comments

**Organization:**
- Use `// MARK: -` to divide logical sections within files
- Examples in codebase:
  - `// MARK: - Detection Tests`
  - `// MARK: - Configuration`
  - `// MARK: - Cross-actor access (nonisolated members on @MainActor Bottle)`
  - `// MARK: - Environment Variables`

## Disabled SwiftFormat Rules

Rules intentionally disabled (in `.swiftformat`):
- `redundantSelf` - Allow explicit self where it improves clarity (MainActor context)
- `fileHeader` - Managed by SwiftLint instead
- `trailingCommas` - Let SwiftLint manage
- `wrapMultilineStatementBraces` - Avoid conflicts with SwiftLint opening_brace
- `extensionAccessControl` - Nested types need explicit access modifiers
- `redundantExtensionACL` - More explicit is better for clarity

---

*Convention analysis: 2026-02-08*
