# How to contribute

Thanks for your interest! First, make a fork of Whisky, make a new branch for your changes, and get coding!

# Build environment

Whisky is built using Xcode 15 on macOS Sonoma. All external dependencies are handled through the Swift Package Manager.

# Code style

## Linting with SwiftLint

Every Whisky commit is automatically linted using SwiftLint. You can run these checks locally simply by building in Xcode, violations will appear as errors or warnings. For your pull request to be merged, you must meet all the requirements outlined by SwiftLint and have no violations.

Generally, it is not advised to disable a SwiftLint rule, but there are certain situations where it is necessary. Please use your discretion when disabling rules temporarily.

## Formatting with SwiftFormat

We use [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) to maintain consistent code formatting across the project. This is enforced in CI alongside SwiftLint.

### Installation

```bash
brew install swiftformat
```

### Usage

To format all Swift files in the project:

```bash
swiftformat .
```

To check formatting without making changes:

```bash
swiftformat --lint .
```

### Pre-commit Hook (Recommended)

To automatically check formatting before each commit, install the pre-commit hook:

```bash
cp .github/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

This will warn you if any staged Swift files have formatting issues and prevent the commit until they're fixed.

### Configuration

The project's formatting rules are defined in `.swiftformat` at the repository root. Key settings include:
- 4-space indentation
- 120 character max line width
- LF line endings

## General Guidelines

All added strings must be properly localised and added to the EN strings file. Do not add keys for other languages or translate within your PR. All translations should be handled on [Crowdin](https://crowdin.com/project/whisky).

# Changelog

We maintain a [CHANGELOG.md](CHANGELOG.md) following the [Keep a Changelog](https://keepachangelog.com/) format. When making changes, please update the changelog under the `[Unreleased]` section:

1. Open `CHANGELOG.md`
2. Add your changes under the appropriate category in the `[Unreleased]` section:
   - **Added** - New features
   - **Changed** - Changes in existing functionality
   - **Deprecated** - Soon-to-be removed features
   - **Removed** - Now removed features
   - **Fixed** - Bug fixes
   - **Security** - Vulnerability fixes
   - **Documentation** - Documentation-only changes
3. Use clear, concise descriptions of what changed

Example entry:
```markdown
## [Unreleased]

### Fixed
- Fixed Steam crashes on macOS 15.4.1 (#123)
```

Note: Not every PR needs a changelog entry. Skip the changelog for:
- Documentation fixes (typos, clarifications)
- CI/build configuration changes
- Test-only changes
- Refactoring with no user-facing impact

# Making your PR

Please provide a detailed description of your changes in your PR. If your commits contain UI changes, we ask that you provide screenshots.

# Review

Once your pull request passes CI checks (SwiftLint, SwiftFormat, and builds), it will be ready for review. You may receive feedback on code that should be changed. Once you have received an approval, your code will be merged!
