# Testing Patterns

**Analysis Date:** 2026-02-08

## Test Framework

**Runner:**
- Swift Package Manager with `swift test` command
- Config: `WhiskyKit/Package.swift` defines test target
- Two test frameworks used concurrently:
  - **XCTest** (traditional) - for compatibility tests
  - **Testing** (Swift 6+) - for newer tests (ClickOnceManagerTests)

**Assertion Library:**
- XCTest assertions: `XCTAssertEqual()`, `XCTAssertTrue()`, `XCTAssertFalse()`, `XCTAssertNil()`
- Testing framework assertions: `#expect()` macro

**Run Commands:**
```bash
# Run all tests in WhiskyKit
swift test --package-path WhiskyKit

# Run specific test file
swift test --package-path WhiskyKit --filter WineTests

# Watch mode (if supported by your environment)
swift test --package-path WhiskyKit --watch
```

## Test File Organization

**Location:**
- Co-located with source code organization
- All tests: `WhiskyKit/Tests/WhiskyKitTests/`
- Tests mirror source structure: source in `Sources/WhiskyKit/`, tests in `Tests/WhiskyKitTests/`

**Naming:**
- Test files: `[SourceName]Tests.swift` (e.g., `ProgramTests.swift`, `WineTests.swift`)
- Edge case tests: `[SourceName]EdgeCaseTests.swift` (e.g., `ClipboardManagerEdgeCaseTests.swift`)
- Test classes: `final class [SourceName]Tests: XCTestCase`
- Test structs (new framework): `@Suite struct [SourceName]Tests`

**Structure:**
```
WhiskyKit/Tests/WhiskyKitTests/
├── BottleSettingsTests.swift
├── ConfigurationTests.swift
├── ClipboardManagerTests.swift
├── ClipboardManagerEdgeCaseTests.swift
├── ClickOnceManagerTests.swift
├── ProgramTests.swift
├── WineTests.swift
├── ProgramExtensionTests.swift
├── BinaryParsingTests.swift
└── ... (42 more test files, 46 total)
```

## Test Structure

**XCTest Suite Organization:**
```swift
// From ProgramTests.swift
// MARK: - Program Core Functionality Tests

final class ProgramCoreTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!
    var programURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "program_core_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)

        programURL = driveCURL.appending(path: "test_game.exe")
        try? Data("fake exe".utf8).write(to: programURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
}
```

**Swift Testing Suite Organization:**
```swift
// From ClickOnceManagerTests.swift
@Suite("ClickOnceManager Tests")
struct ClickOnceManagerTests {
    @Test("Detects ClickOnce directory when it doesn't exist")
    @MainActor func detectAppRefFileNoDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.shared.detectAppRefFile(in: bottle)

        #expect(appRefs.isEmpty, "Should return empty array when ClickOnce directory doesn't exist")
    }
}
```

**Patterns:**
- **Setup**: `override func setUp()` creates temporary test fixtures (files, directories, data)
- **Teardown**: `override func tearDown()` cleans up with `try?` to suppress errors
- **Actor isolation**: `@MainActor func testMethod()` for tests requiring main thread
- **Test organization**: `// MARK: - Section Name` to group related tests
- **Defer blocks**: Used in Swift Testing for setup/teardown within test methods

## Test Structure Details

### XCTest Pattern
```swift
final class BottleSettingsTests: XCTestCase {
    // MARK: - BottleSettings Default Values

    func testBottleSettingsDefaultValues() {
        let settings = BottleSettings()

        XCTAssertEqual(settings.name, "Bottle")
        XCTAssertEqual(settings.windowsVersion, .win10)
        XCTAssertFalse(settings.metalHud)
    }
}
```

### Swift Testing Pattern
```swift
@Suite("ClipboardManager Tests")
struct ClipboardManagerTests {
    @Test("Detects ClickOnce directory when it doesn't exist")
    @MainActor func detectAppRefFileNoDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // test body
        #expect(result == expected)
    }
}
```

## Mocking

**Framework:**
- Not detected - codebase uses real objects in tests
- `@unchecked Sendable` used for thread-safe real objects (e.g., `ClipboardManager`)

**Patterns:**
- **Fixture creation**: Temporary directories and files created in setUp/defer blocks
- **Real object testing**: Tests use actual implementations (Bottle, Program, BottleSettings)
- **Isolation via fixtures**: Each test gets unique temp directories via UUID: `UUID().uuidString`

**What to Mock:**
- Not explicitly used in patterns
- Real objects preferred for unit tests

**What NOT to Mock:**
- File system operations use real temporary directories
- Wine processes and external tools not mocked

## Fixtures and Factories

**Test Data:**
```swift
// From ProgramTests.swift - creating test data
tempDir = FileManager.default.temporaryDirectory.appending(path: "program_core_\(UUID().uuidString)")
bottleURL = tempDir.appending(path: "TestBottle")

let driveCURL = bottleURL.appending(path: "drive_c")
try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)

programURL = driveCURL.appending(path: "test_game.exe")
try? Data("fake exe".utf8).write(to: programURL)
```

**Location:**
- Inline in test setUp() methods
- Defer blocks for cleanup in Swift Testing
- No separate factory classes detected

**Test-specific helpers:**
```swift
// From ConfigurationTests.swift
private func createVersionDict(major: Int, minor: Int, patch: Int) -> [String: Any] {
    ["major": major, "minor": minor, "patch": patch, "preRelease": "", "build": ""]
}
```

## Coverage

**Requirements:**
- Not enforced (no minimum coverage threshold detected)
- Coverage tracking enabled in `codecov.yml` (file exists in project root)

**View Coverage:**
```bash
# SwiftPM doesn't generate coverage by default
# Coverage would need to be measured via:
# - Xcode scheme settings (enableCodeCoverage)
# - Third-party tools (e.g., fastlane with slather)
```

## Test Types

**Unit Tests:**
- Scope: Individual classes and functions in isolation
- Approach: Test single responsibility with real fixtures
- Example: `testProgramNameFromURL()` tests name extraction from URL
- Example: `testIsValidEnvKeyWithValidKeys()` tests environment variable validation

**Integration Tests:**
- Scope: Multiple components working together
- Approach: Create bottles, programs, settings in sequence
- Example: `testBottleSettingsEncodingDecodingRoundtrip()` tests persistence layer
- Example: `testRoundTripWithCustomValues()` tests encoding/decoding with nested types

**E2E Tests:**
- Framework: Not detected
- Notes: No end-to-end tests in WhiskyKit; main app testing likely in Whisky target

## Common Patterns

**Async Testing:**
```swift
// From ClipboardManagerTests.swift with async setUp/tearDown
override func setUp() async throws {
    try await super.setUp()
    clipboardManager = ClipboardManager.shared
    clipboardManager.clear()
}

override func tearDown() async throws {
    clipboardManager.clear()
    try await super.tearDown()
}
```

**Error Testing:**
```swift
// From ClickOnceManagerTests.swift
@Test("Throws error when file not found")
func parseManifestFileNotFound() throws {
    let nonExistentFile = FileManager.default.temporaryDirectory.appending(path: "nonexistent.appref-ms")

    #expect(throws: ClickOnceError.self) {
        _ = try ClickOnceManager.shared.parseManifest(from: nonExistentFile)
    }
}

// XCTest version (not shown in codebase but pattern would be):
// XCTAssertThrowsError(try someThrowingFunction())
```

**MainActor Testing:**
```swift
// From ProgramTests.swift
@MainActor
func testProgramNameFromURL() throws {
    let bottle = Bottle(bottleUrl: bottleURL)
    let program = Program(url: programURL, bottle: bottle)

    XCTAssertEqual(program.name, "test_game.exe")
}
```

**Skip Tests (Headless Environments):**
```swift
// From ClipboardManagerTests.swift - gracefully handle CI without display
guard let tiffData = testImage.tiffRepresentation, !tiffData.isEmpty else {
    throw XCTSkip("Skipping image test in headless environment (no display available)")
}
```

## Test Count and Coverage

- **Total test files**: 46
- **Total test functions**: 766+ individual tests
- **Key test modules**:
  - `ClickOnceManagerTests.swift` - ClickOnce deployment detection
  - `ProgramTests.swift` - Program core functionality, pinning, settings
  - `BottleSettingsTests.swift` - Settings encoding/decoding
  - `ConfigurationTests.swift` - Complex configuration decoding
  - `WineTests.swift` - Environment validation, version comparisons
  - `ClipboardManagerTests.swift` - Clipboard operations
  - `BinaryParsingTests.swift` - Binary format parsing
  - `PETests.swift` - Portable Executable parsing
  - `TempFileTrackerTests.swift` - Temporary file cleanup

## Testing Best Practices Observed

1. **Isolation**: Each test gets unique temporary directory via UUID
2. **Cleanup**: Proper tearDown and defer blocks to prevent test pollution
3. **Descriptive Names**: Test names describe what is being tested and expected outcome
4. **Comprehensive Coverage**: Edge cases tested (empty, null, invalid input)
5. **Encoding Roundtrips**: Persistence tested with encode/decode cycles
6. **Enum/Value Validation**: All enum cases tested for values and conversions
7. **Error Cases**: Both success and failure paths tested
8. **Comment Organization**: `// MARK: -` sections group related tests

---

*Testing analysis: 2026-02-08*
