# ``WhiskyKit``

A Swift framework for managing Wine bottles and running Windows applications on macOS.

## Overview

WhiskyKit provides the core functionality for the Whisky application, enabling macOS users to run Windows applications through Wine. It handles:

- **Bottle Management**: Create, configure, and manage isolated Wine prefixes (bottles)
- **Wine Process Control**: Execute Windows applications and Wine utilities
- **Program Model**: Represent Windows executables in a bottle, with per-program settings and pins
- **Configuration Persistence**: Store and retrieve bottle and program settings
- **PE File Parsing**: Read Windows executable metadata and extract icons

WhiskyKit is designed as a reusable framework that can be integrated into other applications that need Wine management capabilities on macOS.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ArchitectureOverview>

### Managing Bottles

- ``Bottle``
- ``BottleSettings``
- ``PinnedProgram``

### Running Programs

- ``Program``
- ``ProgramSettings``
- ``Locales``

### Wine Integration

- ``Wine``
- ``WhiskyWineInstaller``

### Configuration Types

- ``BottleWineConfig``
- ``BottleMetalConfig``
- ``BottleGraphicsConfig``
- ``GraphicsBackend``
- ``BottleDXVKConfig``
- ``BottlePerformanceConfig``
- ``BottleLauncherConfig``
- ``LauncherType``
- ``WinVersion``
- ``EnhancedSync``
- ``DXVKHUD``

### PE File Parsing

- ``PEFile``
- ``Architecture``
- ``PEError``
- ``PEFile/COFFFileHeader``
- ``PEFile/OptionalHeader``
- ``PEFile/Section``

### Resource Parsing

- ``ResourceDirectoryTable``
- ``ResourceDirectoryEntry``
- ``ResourceDataEntry``
- ``ResourceType``
