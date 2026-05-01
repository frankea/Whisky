# Architecture

**Analysis Date:** 2026-02-08

## Pattern Overview

**Overall:** Layered architecture with feature-organized domain models, functional Wine process execution layer, and SwiftUI-based presentation layer.

**Key Characteristics:**
- Clear separation between domain logic (WhiskyKit), state management (BottleVM), and UI (SwiftUI views)
- Main actor isolation for thread-safe core models
- Non-blocking async execution via `AsyncStream` for Wine process output
- Configuration cascading from bottle settings → program settings → user overrides
- Modular organization: features divided into domain modules (Whisky, Wine, WhiskyWine, PE) rather than by layer

## Layers

**Presentation Layer:**
- Purpose: macOS SwiftUI interface for bottle and program management
- Location: `Whisky/Views/`
- Contains: SwiftUI View components (ContentView, BottleView, BottleListEntry, ConfigView, ProgramView, etc.)
- Depends on: BottleVM, WhiskyKit models
- Used by: macOS app only

**State Management Layer:**
- Purpose: Single source of truth for bottle list and UI state, coordinating between UI and domain
- Location: `Whisky/View Models/BottleVM.swift`
- Contains: `BottleVM` (main actor isolated singleton), bottle persistence coordination
- Depends on: WhiskyKit (Bottle, BottleData, BottleSettings, Wine)
- Used by: All SwiftUI views via @EnvironmentObject

**Domain Layer (Core Models):**
- Purpose: Core data structures representing Wine bottles, programs, and their configuration
- Location: `WhiskyKit/Sources/WhiskyKit/Whisky/`
- Contains:
  - `Bottle.swift` - Wine prefix isolation unit, main actor isolated
  - `Program.swift` - Windows executable with per-program settings
  - `BottleSettings.swift` - Hierarchical configuration (wine, metal, DXVK, performance, launcher, input)
  - Configuration types: `BottleWineConfig`, `BottleMetalConfig`, `BottleDXVKConfig`, `BottlePerformanceConfig`, `BottleLauncherConfig`, `BottleInputConfig`
  - `BottleData.swift` - Bottle discovery and persistence
  - `ProgramSettings.swift` - Per-program environment overrides
- Depends on: Foundation, SemanticVersion
- Used by: Wine layer, BottleVM, WhiskyCmd

**Wine Execution Layer:**
- Purpose: Non-blocking Wine process execution and Wine-related utilities
- Location: `WhiskyKit/Sources/WhiskyKit/Wine/`
- Contains:
  - `Wine.swift` - Primary interface for running programs, executing Wine commands, managing bottles
  - `WineEnvironment.swift` - Environment variable construction with POSIX validation and cascading configuration
  - `WineRegistry.swift` - Wine registry manipulation
  - `GPUDetection.swift` - macOS GPU detection for Metal/DXVK selection
  - `LauncherPresets.swift` - Game launcher (Origin, Steam, Epic) compatibility presets
  - `MacOSCompatibility.swift` - macOS version-specific environment fixes
  - `WinePrefixValidation.swift` - Bottle integrity checking
  - `WinePrefixDiagnostics.swift` - Diagnostic information gathering
- Depends on: Bottle, BottleSettings, Process extensions, Foundation
- Used by: BottleVM, CLI, presentation layer

**Wine Runtime Management:**
- Purpose: WhiskyWine installation and setup
- Location: `WhiskyKit/Sources/WhiskyKit/WhiskyWine/`
- Contains:
  - `WhiskyWineInstaller.swift` - Wine binary installation and update handling
  - `WhiskyWineSetupDiagnostics.swift` - Setup validation and troubleshooting
  - `WhiskyWineVersion.swift` - Wine version tracking
- Depends on: Foundation, Process
- Used by: Wine layer, setup views

**Windows Executable Parser:**
- Purpose: Parse PE format to extract architecture and icons from Windows executables
- Location: `WhiskyKit/Sources/WhiskyKit/PE/`
- Contains:
  - `PortableExecutable.swift` - PE file parser (headers, sections, architecture detection)
  - `COFFFileHeader.swift` - Common Object File Format header parsing
  - `OptionalHeader.swift` - Optional header (PE32/PE32+) parsing
  - `Section.swift` - PE section header parsing
  - `IconCache.swift` - Extracted icon caching
  - `RSRC/` - Resource section parsing for icon extraction
  - `BitmapInfo.swift` - Bitmap metadata extraction
  - `Magic.swift` - PE signature validation
- Depends on: AppKit (NSImage), Foundation
- Used by: Program creation, UI icon display

**System Utilities:**
- Purpose: Cross-cutting utilities and platform-specific functionality
- Location: `WhiskyKit/Sources/WhiskyKit/Utils/`
- Contains:
  - `DistributionConfig.swift` - Wine distribution configuration
  - `Rosetta2.swift` - Apple Silicon compatibility checks
  - `StabilityDiagnostics.swift` - System stability and compatibility diagnostics
  - `TerminalApp.swift` - Terminal integration
- Depends on: Foundation, os.log
- Used by: Wine layer, setup, diagnostics

**Extensions:**
- Purpose: Extend standard types with domain-specific behavior
- Location: `WhiskyKit/Sources/WhiskyKit/Extensions/`
- Contains:
  - `Process+Extensions.swift` - Async stream support for process output
  - `Bundle+Extensions.swift` - Bundle identifier utilities
  - `FileHandle+Extensions.swift` - File handle streaming utilities
  - `FileManager+Extensions.swift` - File system convenience methods
  - `Logger+Extensions.swift` - Logging utilities
  - `Program+Extensions.swift` - Program-related extensions
  - `URL+Extensions.swift` - URL utility methods
- Used by: All layers

**Platform Integrations:**
- Purpose: Target-specific implementations
- Location: `Whisky/` (main app), `WhiskyCmd/` (CLI), `WhiskyThumbnail/` (file provider)
- WhiskyCmd entry: `WhiskyCmd/main.swift` - ArgumentParser CLI with subcommands (list, create, run, etc.)
- WhiskyThumbnail: File provider extension for Windows icon display in Finder

## Data Flow

**Bottle Creation Flow:**

1. User initiates via UI or CLI → BottleVM.createNewBottle() / WhiskyCmd Create
2. BottleVM validates, creates directory, initializes Bottle
3. Bottle loads/creates BottleSettings plist file
4. Wine.changeWinVersion() executed via AsyncStream
5. Bottle persisted to BottleData, UI updates

**Program Execution Flow:**

1. User selects program in UI → Wine.runProgram()
2. Wine.runProgram() calls Wine.constructWineEnvironment()
3. Environment construction:
   - Start with Wine defaults (WINEPREFIX, WINEDEBUG, etc.)
   - Apply macOS compatibility fixes
   - Merge bottle.settings.environmentVariables()
   - Merge program.settings.environmentVariables()
   - Merge user-provided environment overrides
4. Validation: isValidEnvKey() filters POSIX-unsafe keys
5. Process execution: Wine.runWineProcess() returns AsyncStream<ProcessOutput>
6. UI consumes stream, displays output in real-time

**State Persistence:**

- Bottle.settings uses @Published with didSet observer
- didSet calls saveSettings() which writes to plist
- Program settings follow same pattern
- BottleData.loadBottles() reads from discovery paths on launch

**State Management:**

- BottleVM.shared singleton maintains @Published bottles array
- SwiftUI views use @EnvironmentObject(BottleVM.shared)
- UI state changes propagate immediately to views
- Cross-actor access via nonisolated Bottle.id property

## Key Abstractions

**Bottle (Main Abstraction):**
- Purpose: Represents isolated Wine prefix environment
- Examples: `WhiskyKit/Sources/WhiskyKit/Whisky/Bottle.swift`
- Pattern: @MainActor isolated ObservableObject with automatic persistence
- Exposes: url, settings (BottleSettings), programs ([Program]), inFlight, isAvailable
- Usage: Primary organizational unit for all Wine operations

**BottleSettings (Hierarchical Configuration):**
- Purpose: Encapsulates all bottle-level configuration
- Examples: `WhiskyKit/Sources/WhiskyKit/Whisky/BottleSettings.swift`
- Pattern: Struct with private nested configuration objects (BottleWineConfig, etc.)
- Provides: Computed properties for all settings, environmentVariables() method
- Usage: Automatically serialized to plist, provides cascade point for program overrides

**Wine (Static Execution Interface):**
- Purpose: Singleton-like static class providing Wine operations without state
- Examples: `WhiskyKit/Sources/WhiskyKit/Wine/Wine.swift`
- Pattern: Static methods returning AsyncStream<ProcessOutput> for non-blocking execution
- Key methods: runProgram(), wineVersion(), killBottle(), changeWinVersion(), enableDXVK()
- Usage: Called from BottleVM and UI, supports cross-thread communication

**WineEnvironment (Configuration Cascade):**
- Purpose: Construct merged environment from bottle → program → user overrides
- Examples: `WhiskyKit/Sources/WhiskyKit/Wine/WineEnvironment.swift`
- Pattern: Extension on Wine providing constructWineEnvironment(for:environment:)
- Validation: POSIX environment key validation (ASCII [A-Za-z_][A-Za-z0-9_]*)
- Usage: Called before each program execution

**Program (Per-Executable Configuration):**
- Purpose: Represents discovered Windows executable with override settings
- Examples: `WhiskyKit/Sources/WhiskyKit/Whisky/Program.swift`
- Pattern: ObservableObject with ProgramSettings for environment/argument overrides
- Usage: Discovered by scanning bottle's drive_c, edited via ProgramView

**AsyncStream<ProcessOutput> (Non-blocking Output):**
- Purpose: Stream Wine process output without blocking UI
- Pattern: Process extension (Process+Extensions.swift) wraps Foundation Process
- Provides: Async iteration over stdout, stderr, and lifecycle events
- Usage: Wine.runProgram() and related methods return streams for UI consumption

**PortableExecutable (Binary Metadata):**
- Purpose: Parse Windows .exe/.dll files for architecture and icons
- Examples: `WhiskyKit/Sources/WhiskyKit/PE/PortableExecutable.swift`
- Pattern: Struct parsing PE headers (COFF, optional, sections)
- Usage: Program creation, icon extraction for UI display

## Entry Points

**macOS App:**
- Location: `Whisky/Views/WhiskyApp.swift`
- Triggers: User launches Whisky.app
- Responsibilities:
  - @main entry point with WindowGroup
  - Initializes SPUStandardUpdaterController (Sparkle auto-updates)
  - Creates ContentView with BottleVM.shared environment
  - Menu commands for setup, CLI install, bottle opening, logs, kill bottles, clear caches
  - AppDelegate handles URL opening and app lifecycle

**App Delegate:**
- Location: `Whisky/AppDelegate.swift`
- Triggers: Application lifecycle events
- Responsibilities:
  - Handles file/URL opening
  - Shows "move to Applications" alert on first launch
  - Coordinates Whisky window closing with bottle termination

**CLI:**
- Location: `WhiskyCmd/main.swift`
- Triggers: `whisky` command-line invocation
- Responsibilities:
  - ArgumentParser-based CLI with subcommands: list, create, add, delete, remove, run, shellenv
  - Each subcommand extends AsyncParsableCommand for async/await support
  - Direct use of WhiskyKit domain models (BottleData, Bottle, Wine)
  - No state management, direct @MainActor execution

**File Provider Extension:**
- Location: `WhiskyThumbnail/`
- Triggers: Finder requests icons for Windows executables
- Responsibilities: Extract and cache icons from PE files for macOS display

## Error Handling

**Strategy:** Typed errors with LocalizedError, logging with os.log, user presentation via alerts

**Patterns:**

**BottleVM Error Handling:**
- BottleCreationError (typed enum with LocalizedError)
- Caught in createBottleTask(), presented via bottleCreationAlert@Published property
- User sees alert with title, message, and diagnostic information

**Wine Process Errors:**
- throws methods propagate AsyncStream construction errors
- Caller wraps in try-catch, typically silent logging (errors are process exit codes)
- Wine operations are fire-and-forget where errors aren't critical

**Validation Errors:**
- isValidEnvKey() returns Bool, invalid keys logged as debug messages
- PE parsing: PEError struct with message
- File operations: macOS FileManager errors propagate as NSError

## Cross-Cutting Concerns

**Logging:**
- Framework: os.log with private Logger per module
- Pattern: `let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ModuleName")`
- Categories: Wine, Bottle, Program, PE, Setup, etc.
- Levels used: info, warning, error (debug filtered in production)

**Validation:**
- Environment keys: POSIX identifier validation before Wine process execution
- PE files: Magic number check before parsing
- Bottles: Directory existence and plist readability checks

**Authentication:**
- Strategy: None required (local file system operations)
- Permissions: macOS user-level access to ~/Library/Application Support, /Applications comparison

**Thread Safety:**
- Core models: @MainActor isolation (Bottle, BottleVM, Program)
- Cross-thread access: nonisolated Bottle.id, AsyncStream for output communication
- No concurrent mutations guaranteed by compiler

---

*Architecture analysis: 2026-02-08*
