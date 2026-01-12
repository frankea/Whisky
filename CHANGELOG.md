# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Raised minimum deployment target from macOS 14 (Sonoma) to macOS 15 (Sequoia)
- AVX toggle and Sequoia compatibility mode are now always visible (no longer gated by OS version)

### Removed
- Removed `#available(macOS 15, *)` availability checks as macOS 15 is now the minimum

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

[Unreleased]: https://github.com/frankea/Whisky/compare/v2.5.0...HEAD
[2.5.0]: https://github.com/frankea/Whisky/releases/tag/v2.5.0
