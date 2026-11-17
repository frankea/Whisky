# How to Contribute

Thanks for your interest! First, make a fork of Whisky, create a new branch for your changes, and get coding!

## Build Environment

Whisky is built with **Xcode 26** or later; CI uses the latest stable Xcode on macOS 26. The app uses macOS 26 SDK features (Liquid Glass controls and an Icon Composer app icon), so Xcode 16 cannot build it, and if the asset compiler crashes on the app icon, update Xcode (Xcode 26.3 on macOS 15 is known to fail, see #310). The built app runs on Apple Silicon Macs with **macOS Sequoia 15.0** or later. All external dependencies are handled through the Swift Package Manager.

## Code Style

### Linting with SwiftLint

Every Whisky commit is automatically linted using SwiftLint in strict mode, so warnings fail CI just like errors. Install SwiftLint first with `brew install swiftlint`, because the app's SwiftLint build phase looks for it on the default PATH and in /opt/homebrew/bin and stops the build if it is missing (the `nix develop` shell also provides SwiftLint, but only for `xcodebuild` and `swiftlint` run from that shell, not for Xcode.app). Building in Xcode then runs `swiftlint --strict`, and you can also run `swiftlint lint --strict` from the repository root. For your pull request to be merged, you must have no SwiftLint violations.

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

**Option 3: Nix**

If you use Nix, the repository flake provides a dev shell with SwiftFormat
pinned to exactly the version above (plus SwiftLint):
```bash
nix develop
swiftformat --version  # 0.58.7
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

## Localization

All user-facing strings must be localized. Add every new string to the
English (source) entries in `Whisky/Localizable.xcstrings`. **Do not add
other-language translations, and do not edit another language's entries, in a
PR** — hand-editing the string catalog tends to re-serialize the whole file
(producing huge, unreviewable diffs) and can silently drop existing
translations.

Strings used from the app target are picked up by Xcode when you build.
Strings used from WhiskyKit are not: add each WhiskyKit key to
`Whisky/Localizable.xcstrings` by hand with `"extractionState" : "manual"` and
an English value, placed at its alphabetical position. Don't re-sort or
regenerate the whole catalog with a script.

After adding or changing English strings, run `./scripts/british-english.py`
and commit the result. It regenerates only the en-GB entries from English, and
CI's Localization check fails if they are out of date. This generated en-GB
update is the one exception to the rule about not editing other languages.

Translations are managed through Crowdin and synced automatically: the
[`Crowdin`](.github/workflows/Crowdin.yml) workflow uploads new English strings
to the project's Crowdin whenever a push to `main` changes the string catalog,
and once a week (or when run manually) opens or updates a `New translations
from Crowdin` pull request with any new translations. To help translate, contribute
through the [Whisky Crowdin project](https://crowdin.com/project/frankea-whisky)
rather than opening a PR here. If Crowdin asks you to join, use the access
request prompt on the project page.

## Changelog

We maintain a [CHANGELOG.md](CHANGELOG.md) following the [Keep a Changelog](https://keepachangelog.com/) format. For user-facing changes, you can describe the change in your pull request and the maintainer will add the entry under `[Unreleased]` when merging, or add it yourself. If you add one, run `scripts/changelog-links.py` afterwards so `#123` references become links.

### Citing upstream issues

When a change closes or addresses an issue from the archived upstream
repository [whisky-app/whisky](https://github.com/whisky-app/whisky),
cite it in the CHANGELOG entry **and** the commit message using the
fully-qualified form:

```
(Closes whisky-app/whisky#1234, whisky-app/whisky#1235)
```

The per-issue audit (`scripts/audit_upstream.py`, see
[docs/AUDIT.md](docs/AUDIT.md)) greps the source tree and `git log` for
this exact pattern. Bare `#1234` doesn't count — the audit needs the
`whisky-app/whisky` prefix on each number to disambiguate from this
fork's own issue numbers.

For per-game compatibility fixes that are config-only, add or update the
matching entry in
`WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json` and
include the upstream issue URL in the entry's `provenance.referenceURL`
field — the audit picks up that URL form too.

## Secret scanning

CI runs [TruffleHog](https://github.com/trufflesecurity/trufflehog) against
every PR and every push to `main`, configured to **only fail on verified
secrets** (i.e., the credential is real and currently active). Compiled
binaries in the bundled Wine libraries trigger false positives on byte
patterns that match Box/Eraser/NPM token formats, but those are unverified
and ignored.

To scan locally before pushing:

```bash
brew install trufflehog
./scripts/scan-secrets.sh        # scans HEAD vs origin/main
./scripts/scan-secrets.sh main   # scans HEAD vs local main
```

If the scan fails on a real secret, **rotate the credential first** (treat
it as compromised), then remove it from history with
[`git filter-repo`](https://github.com/newren/git-filter-repo) or
[BFG](https://rtyley.github.io/bfg-repo-cleaner/) and force-push the fix
through a coordinated rewrite.

## Testing

### Running Tests

Whisky has two test layers:

**WhiskyKit unit tests** — the framework's pure-Swift logic, runnable
without launching the app:

```bash
swift test --package-path WhiskyKit
```

**WhiskyUITests** — XCUITest end-to-end coverage of the SwiftUI surface,
runnable from Xcode or via `xcodebuild`:

```bash
xcodebuild -project Whisky.xcodeproj \
  -scheme Whisky \
  -destination 'platform=macOS' \
  -only-testing:WhiskyUITests test
```

Tests that need bottle fixtures call `requireBottleFixture()`, which
`XCTSkip`s them when the user container has no bottles (always true on a
fresh CI runner). The fixture-free tests — the create-bottle sheet flow
and toolbar checks — run for real on every CI run. To exercise the
fixture-dependent tests locally, create at least one bottle in Whisky
before running the suite.

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

# Run UI tests (skip-aware on fresh containers)
xcodebuild -project Whisky.xcodeproj -scheme Whisky \
  -destination 'platform=macOS' \
  -only-testing:WhiskyUITests test

# Check formatting
swiftformat --lint .
```

## Review Process

Once your pull request passes CI (SwiftLint, SwiftFormat, the Localization check, the Whisky, WhiskyCmd and WhiskyThumbnail builds, WhiskyKit tests, WhiskyUITests, CodeQL, and the secret scan), it will be ready for review.

### Review Checklist

- [ ] All tests pass (`swift test --package-path WhiskyKit`)
- [ ] Build succeeds (`xcodebuild -scheme Whisky build`)
- [ ] SwiftFormat clean (`swiftformat --lint .`)
- [ ] SwiftLint clean (build shows no violations)
- [ ] Documentation updated (if adding features)
- [ ] User-facing change described in the PR, or a changelog entry added

Thank you for contributing to Whisky!
