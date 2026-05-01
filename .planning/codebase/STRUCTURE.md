# Codebase Structure

**Analysis Date:** 2026-02-08

## Directory Layout

```
Whisky/                                # Root project directory
├── Whisky/                             # macOS SwiftUI app target
│   ├── WhiskyApp.swift                 # @main entry point
│   ├── AppDelegate.swift                # App lifecycle and URL handling
│   ├── Views/                          # SwiftUI view components
│   │   ├── WhiskyApp.swift             # Main window and menu setup
│   │   ├── ContentView.swift           # Primary UI container (sidebar + detail)
│   │   ├── FileOpenView.swift          # Bottle file open dialog
│   │   ├── SparkleView.swift           # Update menu integration
│   │   ├── Bottle/                     # Bottle management views
│   │   │   ├── BottleView.swift        # Single bottle detail view
│   │   │   ├── BottleListEntry.swift   # Bottle list row component
│   │   │   ├── BottleCreationView.swift # New bottle dialog
│   │   │   ├── ConfigView.swift        # Bottle settings container
│   │   │   ├── WineConfigSection.swift # Wine version/debug settings
│   │   │   ├── MetalConfigSection.swift # Metal graphics settings
│   │   │   ├── DXVKConfigSection.swift # DXVK configuration
│   │   │   ├── PerformanceConfigSection.swift # Performance presets
│   │   │   ├── LauncherConfigSection.swift # Game launcher settings
│   │   │   ├── InputConfigSection.swift # Input device settings
│   │   │   ├── DPIConfigSheetView.swift # DPI scaling dialog
│   │   │   ├── SettingItemView.swift   # Reusable setting UI component
│   │   │   ├── RunningProcessesView.swift # Active processes list
│   │   │   ├── WinetricksView.swift    # Winetricks integration
│   │   │   └── Pins/                   # Pinned programs management
│   │   ├── Programs/                   # Program management views
│   │   │   ├── ProgramsView.swift      # Program list
│   │   │   ├── ProgramView.swift       # Single program detail
│   │   │   ├── ProgramMenuView.swift   # Program context menu
│   │   │   ├── EnvironmentArgView.swift # Program env/args editor
│   │   ├── Settings/                   # App settings views
│   │   │   └── SettingsView.swift      # Preferences window
│   │   ├── Setup/                      # Initial setup flows
│   │   │   ├── SetupView.swift         # Setup wizard container
│   │   │   ├── WelcomeView.swift       # Welcome screen
│   │   │   ├── RosettaView.swift       # Apple Silicon compatibility check
│   │   │   ├── WhiskyWineDownloadView.swift # Wine download progress
│   │   │   └── WhiskyWineInstallView.swift # Wine installation progress
│   │   └── Common/                     # Reusable UI components
│   │       ├── BottomBar.swift         # Status/action bar
│   │       ├── ActionView.swift        # Generic action buttons
│   │       └── RenameView.swift        # Rename dialog
│   ├── View Models/
│   │   └── BottleVM.swift              # Bottle list state, creation, persistence
│   ├── Utils/                          # App-specific utilities
│   ├── Extensions/                     # App-specific extensions
│   ├── AppDelegate.swift               # Xcode app delegate lifecycle
│   ├── Localizable.xcstrings           # Localization strings
│   ├── Assets.xcassets/                # App icons, colors
│   └── Preview Content/                # SwiftUI previews
│
├── WhiskyKit/                          # Reusable Swift package (published separately)
│   ├── Sources/WhiskyKit/
│   │   ├── Whisky/                     # Domain models - bottles and programs
│   │   │   ├── Bottle.swift            # @MainActor Wine prefix model
│   │   │   ├── BottleData.swift        # Bottle discovery and persistence
│   │   │   ├── Program.swift           # Windows executable with settings
│   │   │   ├── ProgramSettings.swift   # Per-program overrides
│   │   │   ├── BottleSettings.swift    # Hierarchical bottle configuration
│   │   │   ├── BottleWineConfig.swift  # Wine version and debug settings
│   │   │   ├── BottleMetalConfig.swift # Metal graphics options
│   │   │   ├── BottleDXVKConfig.swift  # DXVK translation layer settings
│   │   │   ├── BottlePerformanceConfig.swift # Performance optimization presets
│   │   │   ├── BottleLauncherConfig.swift # Game launcher (Origin, Steam, Epic)
│   │   │   ├── BottleInputConfig.swift # Input device configuration
│   │   │   └── LaunchResult.swift      # Program execution result
│   │   │
│   │   ├── Wine/                       # Wine process execution layer
│   │   │   ├── Wine.swift              # Core Wine execution interface (30KB)
│   │   │   ├── WineEnvironment.swift   # Environment variable cascading
│   │   │   ├── WineRegistry.swift      # Wine registry manipulation
│   │   │   ├── WinePrefixValidation.swift # Bottle integrity checks
│   │   │   ├── WinePrefixDiagnostics.swift # Diagnostic gathering
│   │   │   ├── GPUDetection.swift      # macOS GPU capabilities detection
│   │   │   ├── LauncherPresets.swift   # Game launcher compatibility presets
│   │   │   └── MacOSCompatibility.swift # macOS version-specific fixes
│   │   │
│   │   ├── WhiskyWine/                 # Wine runtime management
│   │   │   ├── WhiskyWineInstaller.swift # Wine binary installation
│   │   │   ├── WhiskyWineSetupDiagnostics.swift # Setup validation
│   │   │   └── WhiskyWineVersion.swift # Wine version tracking
│   │   │
│   │   ├── PE/                         # Windows PE file parsing
│   │   │   ├── PortableExecutable.swift # PE format parser (headers, sections)
│   │   │   ├── COFFFileHeader.swift    # COFF header parsing
│   │   │   ├── OptionalHeader.swift    # Optional header (PE32/PE32+)
│   │   │   ├── Section.swift           # Section header parsing
│   │   │   ├── IconCache.swift         # Icon extraction and caching
│   │   │   ├── Magic.swift             # PE signature validation
│   │   │   ├── BitmapInfo.swift        # Bitmap metadata parsing
│   │   │   └── RSRC/                   # Resource section parsing
│   │   │
│   │   ├── Utils/                      # System and platform utilities
│   │   │   ├── DistributionConfig.swift # Wine distribution configuration
│   │   │   ├── Rosetta2.swift          # Apple Silicon detection
│   │   │   ├── StabilityDiagnostics.swift # System compatibility checks
│   │   │   ├── TerminalApp.swift       # Terminal integration
│   │   │   ├── ClickOnceManager.swift  # ClickOnce app support
│   │   │   ├── ClipboardManager.swift  # Clipboard integration
│   │   │   ├── TempFileTracker.swift   # Temporary file management
│   │   │   ├── ProcessRegistry.swift   # Running process tracking
│   │   │   ├── ShellLink.swift         # Windows .lnk file parsing
│   │   │   └── Tar.swift               # Tar archive extraction
│   │   │
│   │   ├── Extensions/                 # Type extensions (all files)
│   │   │   ├── Bundle+Extensions.swift # Bundle identifier utilities
│   │   │   ├── FileHandle+Extensions.swift # Streaming utilities
│   │   │   ├── FileManager+Extensions.swift # File system utilities
│   │   │   ├── Logger+Extensions.swift # Logging configuration
│   │   │   ├── Process+Extensions.swift # AsyncStream process output
│   │   │   ├── Program+Extensions.swift # Program discovery
│   │   │   └── URL+Extensions.swift    # URL utilities
│   │   │
│   │   └── Documentation.docc/         # DocC documentation
│   │
│   └── Tests/WhiskyKitTests/           # Unit tests for WhiskyKit
│       ├── WineTests.swift
│       ├── BottleTests.swift
│       ├── PortableExecutableTests.swift
│       ├── ClickOnceManagerTests.swift
│       ├── ClipboardManagerTests.swift
│       ├── ProcessRegistryTests.swift
│       ├── TempFileTrackerTests.swift
│       └── [other test files]
│
├── WhiskyCmd/                          # CLI tool target
│   ├── main.swift                      # ArgumentParser CLI entry point
│   └── [Subcommands: List, Create, Add, Delete, Remove, Run, Shellenv]
│
├── WhiskyThumbnail/                    # Finder file provider extension
│   ├── [File provider implementation]
│   └── Icons.xcassets/
│
├── Whisky.xcodeproj/                   # Xcode project configuration
│   ├── project.pbxproj
│   └── xcshareddata/
│       └── xcschemes/                  # Build schemes
│
├── WhiskyKit/                          # Swift package manifest
│   ├── Package.swift
│   ├── Package.resolved
│   ├── Sources/
│   └── Tests/
│
├── Localization/Localizable.xcstrings  # Localization (EN source)
├── CHANGELOG.md                         # User-facing change log
├── .swiftformat                         # SwiftFormat configuration
├── .swiftlint.yml                      # SwiftLint rules (GPL header, no force unwrap)
└── [Config: .github/, docs/, images/]
```

## Directory Purposes

**Whisky/ (Main App Target):**
- Purpose: macOS SwiftUI application for Wine bottle management
- Entry point: `Whisky/Views/WhiskyApp.swift`
- State management: `Whisky/View Models/BottleVM.swift` (singleton)

**Views/ (UI Layer):**
- Purpose: SwiftUI components organized by feature
- Bottle/: Bottle creation, listing, configuration, running processes
- Programs/: Program discovery, editing, launch settings
- Settings/: App preferences
- Setup/: Initial Wine installation, Rosetta compatibility setup
- Common/: Reusable components (status bar, dialogs, rename)

**WhiskyKit/Sources/WhiskyKit/ (Core Domain Package):**
- Published as separate Swift package, reusable in other projects
- Whisky/: Domain models (Bottle, Program, BottleSettings and configuration types)
- Wine/: Process execution, environment setup, registry manipulation
- WhiskyWine/: Wine runtime installation and management
- PE/: Windows executable parsing for icons and architecture detection
- Utils/: System utilities (Rosetta2, diagnostics, ClickOnce, clipboard, temp files, process registry)
- Extensions/: Type extensions for Foundation and system frameworks

**WhiskyCmd/:**
- Purpose: CLI interface for programmatic bottle/program management
- Uses: WhiskyKit models directly, no state management
- Pattern: ArgumentParser with async subcommands

**WhiskyThumbnail/:**
- Purpose: macOS file provider extension for Windows executable icons
- Integrates: Finder icon display via PE parsing

## Key File Locations

**Entry Points:**
- `Whisky/Views/WhiskyApp.swift`: macOS app main window, menu, update integration
- `Whisky/AppDelegate.swift`: App lifecycle (launch alerts, URL handling, termination)
- `WhiskyCmd/main.swift`: CLI argument parsing and subcommand routing

**Configuration:**
- `Whisky/Localizable.xcstrings`: User-facing localized strings (English source)
- `.swiftformat`: Code formatting rules (4-space indent, 120 char line limit)
- `.swiftlint.yml`: Linting rules (GPL header, no force unwrap)
- `Whisky.xcodeproj/`: Build configuration and schemes

**Core Logic:**
- `WhiskyKit/Sources/WhiskyKit/Whisky/Bottle.swift`: Wine prefix model
- `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift`: Wine process execution (29KB)
- `Whisky/View Models/BottleVM.swift`: UI state management and persistence

**Tests:**
- `WhiskyKit/Tests/WhiskyKitTests/`: Unit tests for WhiskyKit modules

## Naming Conventions

**Files:**
- Swift files: PascalCase (`BottleVM.swift`, `WhiskyApp.swift`)
- Views: `[Feature]View.swift` (e.g., `BottleView.swift`, `ProgramsView.swift`)
- View Models: `[Domain]VM.swift` (e.g., `BottleVM.swift`)
- Models: `[Noun].swift` (e.g., `Bottle.swift`, `Program.swift`)
- Configuration: `[Domain][Type]Config.swift` (e.g., `BottleWineConfig.swift`)
- Tests: `[Module]Tests.swift` (e.g., `WineTests.swift`, `BottleTests.swift`)

**Directories:**
- Feature groups: PascalCase with descriptive names (`Bottle/`, `Programs/`, `Settings/`, `Setup/`)
- Module groups: PascalCase, single feature per directory (`Wine/`, `Whisky/`, `PE/`, `Utils/`)
- View organization: By feature area, not by view type

**Types:**
- Classes: PascalCase, mutable state (e.g., `Bottle`, `BottleVM`, `Wine`)
- Structs: PascalCase, value types (e.g., `BottleSettings`, `Program`, `PortableExecutable`)
- Enums: PascalCase (e.g., `Architecture`, `WinVersion`, `LaunchResult`)
- Protocols: PascalCase ending in "able" or descriptive (e.g., `AsyncParsableCommand`)
- Properties: camelCase, @Published for observable state in ObservableObjects

**Functions/Methods:**
- camelCase, action verbs (e.g., `runProgram()`, `constructWineEnvironment()`, `killBottle()`)
- Async methods: no "Async" suffix, use async/await syntax
- Static methods: used for singleton-like access (e.g., `Wine.runProgram()`)

## Where to Add New Code

**New Feature (in main app):**
- Primary code: `Whisky/Views/[FeatureName]/`
- State management: Add properties/methods to `Whisky/View Models/BottleVM.swift`
- Tests: Add test file to `WhiskyKit/Tests/WhiskyKitTests/` if WhiskyKit logic

**New Component/Module:**
- WhiskyKit library code: `WhiskyKit/Sources/WhiskyKit/[ModuleName]/`
- App-specific code: `Whisky/[LayerName]/` (Views, Utils, Extensions)
- Ensure GPL v3 header on all Swift files (enforced by SwiftLint)

**New Configuration Type:**
- Location: `WhiskyKit/Sources/WhiskyKit/Whisky/Bottle[Category]Config.swift`
- Pattern: Codable struct, private nested in BottleSettings, exposed via computed properties
- Cascade: Add to BottleSettings.environmentVariables() for Wine environment inclusion

**New Wine Utility:**
- Location: `WhiskyKit/Sources/WhiskyKit/Wine/` if core execution, `Utils/` if helper
- Pattern: Static methods on Wine class or standalone struct
- Async execution: Return AsyncStream<ProcessOutput> for non-blocking operations

**Utilities/Helpers:**
- Shared helpers: `WhiskyKit/Sources/WhiskyKit/Utils/`
- App-only utilities: `Whisky/Utils/`
- Type extensions: `[WhiskyKit|Whisky]/Extensions/`

**Tests:**
- Location: `WhiskyKit/Tests/WhiskyKitTests/[Module]Tests.swift`
- Pattern: XCTest with setUp/tearDown, named test methods (test*)
- Run: `swift test --package-path WhiskyKit`

## Special Directories

**Documentation.docc/:**
- Purpose: DocC documentation for WhiskyKit public API
- Generated: No (hand-written source)
- Committed: Yes

**Preview Content/:**
- Purpose: SwiftUI preview data and mock objects
- Generated: No (hand-written)
- Committed: Yes
- Used in: Xcode previews for development

**Assets.xcassets/:**
- Purpose: App icons, colors, images
- Generated: No (hand-curated)
- Committed: Yes

**.build/ and DerivedData/:**
- Purpose: Compiled products and intermediate build artifacts
- Generated: Yes
- Committed: No (excluded via .gitignore)

**Tests/WhiskyKitTests/:**
- Purpose: Unit tests for WhiskyKit modules
- Generated: No (hand-written)
- Committed: Yes
- Run: `swift test --package-path WhiskyKit`

---

*Structure analysis: 2026-02-08*
