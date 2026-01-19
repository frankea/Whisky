# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Terminal application selection: choose between Terminal, iTerm2, or Warp (Refs #47, upstream #911)
- Duplicate bottle feature for cloning bottles without export/import (Refs #47, upstream #822)
- App Nap management: disable macOS process throttling for better game performance (Refs #47, upstream #1297)
- Controller & Input Compatibility settings for game controller detection issues (Issue #42)
- Toast notifications showing launch success/failure feedback (Refs #49)
- Archive progress indicator with toast notifications for bottle export (Refs #49, upstream #827)
- Icon caching for faster program list loading (Refs #49, upstream #941)
- Improved UX for unavailable bottles with warning icon and quick remove button (Refs #49, upstream #1039)
- Comprehensive Launcher Compatibility System including detection, diagnostics, and configuration
- Stability diagnostics export for crash/freeze reports (Refs #40)
- WhiskyWine download/install diagnostics with copy-to-clipboard workflow (Issue #63)
- SwiftFormat integration for automated code formatting
- DocC documentation for WhiskyKit public API
- Code coverage reporting and badges
- GitHub Pages and Releases infrastructure
- WhiskyKit test infrastructure and initial test suite
- Dependabot configuration for dependency updates

### Changed
- Refactored shared program launch logic into reusable `LaunchResult` and `launchWithUserMode()` (Issue #68)
- Refactored `BottleSettings` and `Wine` modules into smaller, focused components
- Replaced `print()` statements with `os.log` Logger for better debugging
- Consolidated CI workflows for improved efficiency
- Implemented proper thread safety by removing `@unchecked Sendable` usage
- Raised minimum deployment target from macOS 14 (Sonoma) to macOS 15 (Sequoia)
- AVX toggle and Sequoia compatibility mode are now always visible (no longer gated by OS version)

### Fixed
- Fixed Terminal launch (shift-click) producing malformed commands due to double-escaping (Issue #71)
- Fixed localization fallback showing raw keys to non-English users (Refs #49)
- Corrected Dependabot Swift configuration
- Capped Wine process logs and pruned old logs to prevent excessive disk usage (Issue #46)
- Surface bottle creation failures with diagnostic information (Issue #61)
- Fixed winetricks dependency installs failing when %AppData% is empty (Issue #64)
- Fixed hardcoded "crossover" username in user profile path detection
- Added Wine prefix validation before running winetricks with repair option

### Security
- Process environment logging now records keys only (not values) to avoid persisting secrets in logs

### Removed
- Unmaintained CLI dependencies (SwiftyTextTable, Progress.swift)
- Removed `#available(macOS 15, *)` availability checks as macOS 15 is now the minimum

### Documentation
- Added comprehensive Launcher Troubleshooting and Steam Compatibility guides
- Removed obsolete Markdown files from the root and `docs/` directory
- Updated `README.md` and `CONTRIBUTING.md` to reflect current project state
- Consolidated documentation into the `docs/` directory

## [3.0.0] - 2026-01-18 (Wine Libraries)

### Changed
- Upgraded Wine from 7.7 to 11.0 (Gcenx stable build) for improved application compatibility
- Updated DXVK to macOS-compatible v1.10.3

### Fixed
- Steam "steamwebhelper is not responding" error caused by stubbed WSALookupServiceBegin (Issue #72)
- Improved networking stack for better launcher compatibility

## [2.5.0] - 2026-01-10

### Added
- Initial release of Whisky Wine binaries for this fork
- Wine/GPTK libraries packaged as `Libraries.tar.gz`
- GitHub Pages hosting for version metadata
- Sparkle appcast support for automatic updates
- Release workflow documentation

### Changed
- Fork setup with new distribution infrastructure
- Updated GitHub Pages URLs for the frankea fork

### Documentation
- Added `RELEASE_WORKFLOW.md` for publishing releases
- Added `DOCUMENTATION_AUDIT.md` for tracking documentation status
- Updated `README.md` with fork-specific information

---

## Categories Guide

When adding entries to this changelog, use the following categories:

- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Now removed features
- **Fixed** - Bug fixes
- **Security** - Vulnerability fixes
- **Documentation** - Documentation-only changes

[Unreleased]: https://github.com/frankea/Whisky/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/frankea/Whisky/releases/tag/v3.0.0
[2.5.0]: https://github.com/frankea/Whisky/releases/tag/v2.5.0
