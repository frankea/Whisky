# How to Contribute

Thanks for your interest! First, make a fork of Whisky, create a new branch for your changes, and get coding!

## Build Environment

Whisky is built using **Xcode 16** on **macOS Sequoia 15.0** or later. All external dependencies are handled through the Swift Package Manager.

## Code Style

### Linting with SwiftLint

Every Whisky commit is automatically linted using SwiftLint. You can run these checks locally by building in Xcode; violations will appear as errors or warnings. For your pull request to be merged, you must meet all requirements outlined by SwiftLint and have no violations.

### Formatting with SwiftFormat

We use [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to maintain consistent code formatting. This is enforced in CI alongside SwiftLint.

**Required Version: 0.58.7**

Using a different version may produce different formatting results. CI uses this exact version.

#### Installation

**Option 1: Homebrew (latest version)**
```bash
brew install swiftformat
swiftformat --version  # Verify version matches 0.58.7
```

**Option 2: Download specific version (recommended)**
```bash
curl -LO https://github.com/nicklockwood/SwiftFormat/releases/download/0.58.7/swiftformat.zip
unzip swiftformat.zip
sudo mv swiftformat /usr/local/bin/
```

#### Usage

To format all Swift files in the project:
```bash
swiftformat .
```

To check formatting without making changes:
```bash
swiftformat --lint .
```

#### Pre-commit Hook (Recommended)

To automatically check formatting before each commit:
```bash
cp .github/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## General Guidelines

All added strings must be properly localised and added to the EN strings file. Do not add keys for other languages or translate within your PR.

> **Note:** Translations are managed via Crowdin for the upstream project. This fork inherits existing translations but does not currently manage Crowdin directly. New strings will be in English only until a translation workflow is established.

## Changelog

We maintain a [CHANGELOG.md](CHANGELOG.md) following the [Keep a Changelog](https://keepachangelog.com/) format. When making user-facing changes, please update the changelog under the `[Unreleased]` section.

## Testing

### Running Tests

Whisky uses Swift's built-in testing framework. To run the full test suite:

```bash
# Test the WhiskyKit framework
swift test --package-path WhiskyKit
```

All tests must pass before your PR can be merged.

### Testing Launcher Compatibility Features

If your changes affect launcher compatibility (Issue #41), please perform the following tests:

1.  **Unit Tests**: Ensure coverage for launcher detection, environment generation, and settings persistence.
2.  **Manual Testing**:
    -   Create a test bottle (Windows 10).
    -   Enable Launcher Compatibility Mode.
    -   Verify detection and configuration for the target launcher.
    -   Check that settings persist after restart.

### Regression Testing

Before submitting a PR, verify no regressions:

```bash
# Run full test suite
swift test --package-path WhiskyKit

# Build Whisky app
xcodebuild -scheme Whisky -configuration Debug build

# Check formatting
swiftformat --lint .
```

## Review Process

Once your pull request passes CI checks (SwiftLint, SwiftFormat, and builds), it will be ready for review.

### Review Checklist

- [ ] All tests pass (`swift test --package-path WhiskyKit`)
- [ ] Build succeeds (`xcodebuild -scheme Whisky build`)
- [ ] SwiftFormat clean (`swiftformat --lint .`)
- [ ] SwiftLint clean (build shows no violations)
- [ ] Documentation updated (if adding features)
- [ ] Changelog updated (if user-facing changes)

Thank you for contributing to Whisky!
