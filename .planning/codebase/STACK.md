# Technology Stack

**Analysis Date:** 2026-02-08

## Languages

**Primary:**
- Swift 6.0 - All application code, both main app and WhiskyKit library

## Runtime

**Environment:**
- macOS 15.0 (Sequoia) - Deployment target for all targets
- Apple Silicon (arm64) and Intel (x86_64) support via Xcode universal builds

**Build System:**
- Xcode (via xcodebuild)
- Swift Package Manager (for WhiskyKit and dependencies)

## Frameworks

**Core UI:**
- SwiftUI - All user interface views and layouts
- AppKit - Native macOS UI components, window management, file dialogs
- Foundation - Core data types and utilities

**System Frameworks:**
- os.log - Structured logging throughout codebase
- QuickLookThumbnailing - Icon extraction for file provider extension (`WhiskyThumbnail`)
- Quartz - Graphics and PDF handling

**Process & Shell:**
- Foundation.Process - Running Wine executables and system commands
- Foundation.Pipe - Capturing process output

## Package Dependencies

**Update Management:**
- Sparkle 2.6.0+ - Automatic app updates with delta downloads and DSA signature verification
  - Configured in `Whisky/Info.plist` with appcast URL
  - Entry point: `Whisky/Views/SparkleView.swift`

**CLI Infrastructure:**
- ArgumentParser 1.2.3+ - Command-line argument parsing for WhiskyCmd target
  - Used in `WhiskyCmd/` for programmatic control

**Version Handling:**
- SemanticVersion 0.4.0+ - Semantic versioning for Wine/WhiskyWine version comparisons
  - Used across `WhiskyKit` for version management and comparison

**Documentation:**
- swift-docc-plugin 1.4.3+ - DocC documentation generation (development-only)

## Configuration

**Code Formatting:**
- SwiftFormat 0.58.7 (required - exact version enforced in CI)
  - Config: `.swiftformat`
  - Settings: 4-space indent, 120 char line limit, LF line endings
  - Run: `swiftformat .`

**Linting:**
- SwiftLint - Static code analysis
  - Config: `.swiftlint.yml`
  - Enforces: No force unwrapping, GPL v3 file headers
  - Run: `swiftlint`

## Build Targets

**Whisky:**
- Main macOS application for Wine bottle management
- Location: `Whisky.xcodeproj` → Whisky target
- Output: `Whisky.app`
- Frameworks linked: Sparkle, SemanticVersion, WhiskyKit, QuickLookThumbnailing, Quartz

**WhiskyKit:**
- Reusable Swift package with core logic
- Location: `WhiskyKit/Package.swift`
- Swift language mode: 6 (strict concurrency)
- Published to separate repository for external use
- Targets: WhiskyKit (library), WhiskyKitTests (unit tests)

**WhiskyCmd:**
- Command-line interface for programmatic bottle control
- Location: `WhiskyCmd/` directory
- Frameworks linked: WhiskyKit, ArgumentParser, SemanticVersion

**WhiskyThumbnail:**
- File provider extension for Windows executable icons
- Frameworks linked: WhiskyKit, QuickLookThumbnailing, Quartz
- Enables Quick Look previews of .exe files in Finder

## Concurrency Model

**Thread Safety:**
- Swift 6 strict concurrency enforcement enabled
- `@MainActor` isolation on all UI state models: `Bottle`, `Program`, `BottleVM`
- `nonisolated` properties allow cross-thread access to identifiers
- `@preconcurrency` used where bridging legacy code
- AsyncStream for non-blocking process output

## Platform Requirements

**Development:**
- macOS Sonoma or later (for Swift 6.0 toolchain)
- Xcode 16+
- SwiftFormat 0.58.7 (exact version, installed via Homebrew or package manager)

**Runtime:**
- macOS Sequoia (15.0) or later
- Wine runtime (WhiskyWine) downloaded from GitHub Releases
- Rosetta 2 translation layer support detected at runtime

**Distribution:**
- Code signing and notarization required for distribution outside App Store
- Sparkle appcast feed URL: `https://frankea.github.io/Whisky/appcast.xml`

---

*Stack analysis: 2026-02-08*
