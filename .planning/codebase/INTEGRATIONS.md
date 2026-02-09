# External Integrations

**Analysis Date:** 2026-02-08

## APIs & External Services

**GitHub:**
- Purpose: Host distribution files, releases, and appcast feed
- Configuration file: `WhiskyKit/Sources/WhiskyKit/Utils/DistributionConfig.swift`
- Base URLs defined:
  - Releases: `https://github.com/frankea/Whisky/releases/download`
  - GitHub Pages: `https://frankea.github.io/Whisky`
  - Issues/Help links: `https://github.com/frankea/Whisky` and `/issues`

**Sparkle Update Framework:**
- Purpose: Automatic app updates with signature verification
- SDK/Client: Sparkle 2.6.0+
- Appcast feed URL: `https://frankea.github.io/Whisky/appcast.xml`
- Config location: `Whisky/Info.plist` (SUFeedURL, SUPublicEDKey)
- Implementation: `Whisky/Views/SparkleView.swift` uses `SPUStandardUpdaterController`
- Auth: EdDSA public key configured in Info.plist (key: SUPublicEDKey)

## Data Storage

**Local Filesystem Only:**
- Application Support: `~/Library/Application Support/com.franke.Whisky/`
- Bottle Configuration: Plist files at `{bottle-directory}/Metadata.plist`
  - Format: Archivable Swift structures serialized as property list
  - Mechanism: `PropertyListEncoder`/`PropertyListDecoder`
  - Implementation: `WhiskyKit/Sources/WhiskyKit/Whisky/Bottle.swift` and related config types

**Wine Runtime Files:**
- Location: `~/Library/Application Support/com.franke.Whisky/Libraries/`
- Contains: Wine binaries, DXVK, shader caches
- Downloaded as: `Libraries.tar.gz` from GitHub Releases
- Extraction: Handled by `WhiskyKit/Sources/WhiskyKit/Tar.swift`

**Temporary Files:**
- Tracked by: `WhiskyKit/Sources/WhiskyKit/TempFileTracker.swift`
- Purpose: Download caches, temporary extractions during setup
- Cleanup: Automatic via TempFileTracker

**Log Files:**
- Location: `~/Library/Logs/Whisky/` (or system-determined)
- Format: Text logs from Wine process output
- Management: Auto-cleanup of logs older than 7 days (see `WhiskyApp.deleteOldLogs()`)

**Caching:**
- Icon Cache: In-memory cache in `WhiskyKit/Sources/WhiskyKit/PE/IconCache.swift`
- No persistent cache database; icons re-extracted from PE files as needed

## Authentication & Identity

**Auth Provider:**
- None - Application is standalone, no user authentication required
- Sparkle signature verification uses EdDSA public key (not OAuth/API auth)

## Monitoring & Observability

**Error Tracking:**
- None - No external error tracking service integrated
- Errors logged to system console via os.log

**Logs:**
- System logging via `os.log` with subsystem: `com.franke.Whisky`
- Categories: BottleVM, WhiskyApp, WhiskyWineInstaller, WhiskyWineDownloadView, etc.
- Console access: Menu → Logs (command+L) opens `~/Library/Logs/Whisky/`
- Log levels: default, info, warning, error

**Network Activity:**
- No analytics or telemetry
- Only outbound connections: GitHub (releases, appcast) and user-configured Wine APIs

## CI/CD & Deployment

**Hosting:**
- macOS application distributed via:
  - Direct download from GitHub Releases
  - Sparkle auto-update mechanism
  - Mac App Store (if approved)

**CI Pipeline:**
- GitHub Actions (configured in `.github/workflows/`)
- Runs: swift test, SwiftFormat lint, SwiftLint checks
- Enforces: Swift 6.0 strict concurrency, GPL headers, no force unwrapping

**Distribution:**
- Sparkle appcast: `https://frankea.github.io/Whisky/appcast.xml`
- File format: XML feed with Sparkle schema
- Updated manually via repository pushes to `frankea.github.io` repo

## Environment Configuration

**Required Runtime Files:**
- Wine runtime (WhiskyWine) - auto-downloaded from GitHub Releases
- No environment variables required for typical operation

**Download URLs - Configured in Code:**
- `WhiskyWineVersion.plist` URL: `{baseURL}/WhiskyWineVersion.plist`
- Libraries archive URL: `{releasesBaseURL}/v{version}/Libraries.tar.gz`
- Appcast URL: `{baseURL}/appcast.xml`

**No External Configuration Files:**
- No `.env` files required
- No API keys or credentials needed for standard operation
- Sparkle public key embedded in Info.plist (public, not secret)

## Webhooks & Callbacks

**Incoming:**
- None - Application does not expose HTTP endpoints

**Outgoing:**
- None - Application does not make webhook callbacks
- Only standard HTTP/HTTPS GET requests for downloads and version checks

## File Format Integrations

**Windows PE Parsing:**
- Implementation: `WhiskyKit/Sources/WhiskyKit/PE/` module
- Formats handled: PE/COFF executables (.exe, .dll)
- Purpose: Architecture detection, icon extraction
- Related types: `PortableExecutable.swift`, `ResourceDirectoryTable.swift`, `COFFFileHeader.swift`

**Windows Registry Parsing:**
- Implementation: `WhiskyKit/Sources/WhiskyKit/Wine/WineRegistry.swift`
- Format: Wine registry files in binary format
- Purpose: Access Windows registry data within bottles

**Shell Links (.lnk files):**
- Implementation: `WhiskyKit/Sources/WhiskyKit/ShellLink.swift`
- Purpose: Parse Windows shortcut files

**TAR Archive Extraction:**
- Implementation: `WhiskyKit/Sources/WhiskyKit/Tar.swift`
- Used for: Extracting WhiskyWine runtime from `Libraries.tar.gz`

## Network Behavior

**On Application Launch:**
- Sparkle checks appcast feed for updates: `https://frankea.github.io/Whisky/appcast.xml`
- No blocking network calls; updates checked asynchronously

**Wine Runtime Setup:**
- Downloads version manifest: `https://frankea.github.io/Whisky/WhiskyWineVersion.plist`
- Downloads Wine runtime if needed: `https://github.com/frankea/Whisky/releases/download/v{version}/Libraries.tar.gz`
- Progress tracking via URLSessionDownloadTask with KVO observation

**User Initiated:**
- Help menu links to GitHub repository (opens in default browser)
- Programmatic Wine execution (no network, local process execution)

---

*Integration audit: 2026-02-08*
