# Architecture Overview

Understand how WhiskyKit components work together to manage Wine bottles and Windows applications.

## Overview

WhiskyKit is organized into several logical layers, each responsible for a specific aspect of Wine management on macOS.

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│                 (Whisky.app, WhiskyCmd)                      │
├─────────────────────────────────────────────────────────────┤
│                      WhiskyKit                               │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │   Bottle    │  │    Wine      │  │ WhiskyWineInstaller│  │
│  │  Management │  │  Execution   │  │                   │  │
│  └─────────────┘  └──────────────┘  └───────────────────┘  │
│  ┌─────────────┐  ┌──────────────┐                         │
│  │   Program   │  │   PE File    │                         │
│  │    Model    │  │   Parsing    │                         │
│  └─────────────┘  └──────────────┘                         │
├─────────────────────────────────────────────────────────────┤
│                     Wine Runtime                             │
│              (WhiskyWine / Wine64 Binary)                   │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### Bottle Management

The bottle management layer handles the lifecycle of Wine prefixes:

| Component | Responsibility |
|-----------|----------------|
| ``Bottle`` | Represents an isolated Wine environment |
| ``BottleSettings`` | Stores configuration for a bottle |
| ``BottleWineConfig`` | Wine-specific settings (Windows version, sync mode) |
| ``BottleMetalConfig`` | Metal and graphics settings |
| ``BottleDXVKConfig`` | DXVK configuration for DirectX translation |
| ``BottlePerformanceConfig`` | Performance optimization settings |

Each bottle is stored as a directory containing:

```
MyBottle/
├── Metadata.plist          # BottleSettings serialized
├── drive_c/                # Windows C: drive
│   ├── windows/
│   ├── Program Files/
│   └── users/
├── Program Settings/       # Per-program plist files
│   ├── game-1a2b3c4d.plist      # Settings for game.exe (name + hash of its path)
│   └── launcher-5e6f7a8b.plist  # Settings for launcher.exe
└── ...                     # Wine registry and other files
```

### Wine Execution

The ``Wine`` class provides the interface to the Wine runtime:

- **Process Management**: Start and monitor Wine processes
- **Environment Setup**: Configure environment variables for DirectX, Metal, and performance
- **Logging**: Capture output and errors from Wine processes
- **Graphics Backends**: Resolve the launch's backend (Recommended, D3DMetal, DXVK, DXMT or WineD3D), copy its files into the prefix, and write per-executable DLL overrides into the prefix registry

Key execution flow:

```
runProgram(url, bottle)
       │
       ▼
┌──────────────────┐
│ Resolve graphics │
│ backend, deploy  │
│ its files        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Construct Wine   │
│ environment vars │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Write DLL        │
│ overrides to the │
│ registry         │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Execute wine64   │
│ start /unix      │
└────────┬─────────┘
         │
         ▼
   AsyncStream<ProcessOutput>
```

### Program Model

Programs represent Windows executables in a bottle (WhiskyKit does not scan for them; the app fills `Bottle.programs`):

- ``Program`` represents an executable (.exe) file
- ``ProgramSettings`` stores per-program configuration
- Programs can be pinned for quick access via ``PinnedProgram``

### PE File Parsing

WhiskyKit includes a complete Windows PE (Portable Executable) file parser:

- ``PEFile`` - Main parser for .exe and .dll files
- ``PEFile/COFFFileHeader`` - COFF header parsing
- ``PEFile/OptionalHeader`` - PE optional header with magic number
- ``PEFile/Section`` - PE section table parsing
- Resource parsing for icon extraction

This enables:
- Detecting 32-bit vs 64-bit executables
- Extracting application icons
- Reading executable metadata

### Other Subsystems

- **Steam/**: finds Steam installs and games in a bottle and launches them through the Steam client (``SteamLauncher``, `SteamClientOrchestrator`, `GameRouting`)
- **Launcher compatibility**: ``LauncherType`` detection and `LauncherFixes` profiles for Steam, Rockstar, EA App, Epic and others
- **GameDatabase/**: bundled per-game configurations and their applicator
- **Troubleshooting/** and **Diagnostics/**: guided troubleshooting flows, crash classification and diagnostic export
- **WhiskyWine/**: runtime install and update (``WhiskyWineInstaller``) and GPTK import (`GPTKImporter`)
- **Process tracking**: `ProcessRegistry` for processes Whisky starts, and `AppSessionStore` so a launch after a crash stops only what the crashed run left behind

## Thread Safety

WhiskyKit uses Swift's actor isolation for thread safety:

- ``Bottle`` and ``Program`` are `@MainActor` isolated
- Cross-thread access is provided via `nonisolated` properties like `id`
- Wine execution methods require `@MainActor` context

```swift
// Must be called from MainActor
@MainActor
func runGame() async throws {
    try await Wine.runProgram(at: gameURL, bottle: bottle)
}
```

## Data Flow

### Settings Persistence

Settings are automatically persisted when modified:

```
bottle.settings.dxvk = true
       │
       ▼
┌──────────────────┐
│ didSet observer  │
│ triggers save    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Encode to        │
│ PropertyList     │
└────────┬─────────┘
         │
         ▼
  Metadata.plist
```

### Environment Construction

When running a program, WhiskyKit builds the environment with ``EnvironmentBuilder`` from ordered layers; a later layer wins when two set the same key:

1. Base (WINEPREFIX, default WINEDEBUG)
2. Platform (macOS compatibility fixes, host time zone)
3. Bottle-managed settings (graphics backend, DXVK, Metal, sync, performance, input)
4. Launcher compatibility overrides
5. GameDB profile for this launch
6. Bottle user variables (reserved, not set today)
7. Program settings and the environment passed to `Wine.runProgram(environment:)`
8. Launch-time feature injectors (diagnostic WINEDEBUG presets)
9. Call-site overrides (reserved for direct callers)

## Extension Points

WhiskyKit is extended through several mechanisms:

- **Extensions**: Additional functionality on core types in `Extensions/`
- **Configuration Types**: Modular settings in separate config structs
- **Wine Registry**: Direct registry manipulation via methods on ``Wine`` (e.g., `retinaMode`, `changeDpiResolution`, `changeWinVersion`)

## See Also

- <doc:GettingStarted>
- ``Bottle``
- ``Wine``
- ``WhiskyWineInstaller``
