# Security Policy

## Supported Versions

The following versions of Whisky are currently supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < Latest | :x:               |

We recommend always using the latest version of Whisky for the best security and feature support.

## Reporting a Vulnerability

If you discover a security vulnerability in Whisky, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. **Use** GitHub's private vulnerability reporting feature via the **Security** tab of this repository:
   - Navigate to **Security** → **Report a vulnerability**
   - Or use this direct link: [Report a vulnerability](https://github.com/frankea/Whisky/security/advisories/new)
3. **Include** the following information in your report:
   - Description of the vulnerability
   - Steps to reproduce the issue
   - Potential impact assessment
   - Any suggested fixes (optional)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
- **Assessment**: We will assess the vulnerability and determine its severity
- **Timeline**: We aim to address critical vulnerabilities within 7 days, and other issues within 30 days
- **Credit**: With your permission, we will credit you in the security advisory

### Scope

This security policy applies to:
- The Whisky application
- WhiskyKit library
- Related command-line tools (WhiskyCmd)
- Build and release infrastructure

### Out of Scope

The following are generally out of scope:
- Vulnerabilities in Wine itself (report to [WineHQ](https://wiki.winehq.org/Bugs))
- Vulnerabilities in DXVK (report to the respective project)
- Issues in third-party dependencies (report upstream, then notify us)

### Wine / DXVK Vulnerability Response

Whisky bundles a Wine runtime (Wine, DXVK, D3DMetal, and related components) that it does not develop.
A vulnerability in those components is fixed upstream, not here — but it still reaches Whisky users, so
we track it as a runtime-currency concern rather than a closed door:

- Bundled component versions are pinned and checked against their upstream sources, so a new upstream
  build carrying a security fix is surfaced rather than missed.
- A **critical** vulnerability in a bundled component (one exploitable through normal Whisky use) is a
  trigger to rebuild the runtime archive on the patched upstream version and cut a new app release out
  of band, rather than waiting for the next scheduled runtime update.
- Non-critical upstream fixes are picked up as part of the normal runtime-update cadence.

If you believe a bundled-runtime vulnerability is being mishandled or under-prioritized in Whisky's
packaging, report it through the private channel above and say so explicitly.

## Telemetry & Data Collection

Whisky sends no data by default. An **opt-in** (default off) first-run checkbox
— mirrored by a toggle in Settings → Privacy — enables exactly five anonymous
events: `runtime_install_started`, `runtime_install_succeeded`,
`runtime_install_failed` (with a coarse `reason` property:
`download_failed` / `verify_failed` / `tarball_missing` / `extract_failed` /
`runtime_incomplete`), `first_bottle_created`, and
`first_program_launch_attempted`. The install events are per-attempt (retries
are counted); the two `first_…` events fire at most once per install.

Events carry a random per-install anonymous ID and never include personal data,
file names, paths, or raw error text. Every event Whisky can send is the list
above, and all of it — plus the SDK configuration — lives in one file,
[`Whisky/Utils/Telemetry.swift`](Whisky/Utils/Telemetry.swift): all automatic
capture (lifecycle events, screen views, feature flags, swizzling) is disabled,
`personProfiles` is `.never`, and `identify()` is never called, so no person
profile is created. Each event does carry the SDK's standard context (app
version, macOS version, device model, locale), and PostHog's ingestion sees the
connecting IP like any HTTPS request, with GeoIP enrichment disabled
(`$geoip_disable`) — none of it tied to your identity.

Opting out stops all future capture and resets the anonymous ID. Events already
queued at that moment may still be delivered (the SDK has no public queue-purge),
but no new events are captured.

## Security Best Practices for Users

- Only run trusted Windows applications within Whisky
- Keep Whisky and macOS updated to the latest versions
- Be cautious when downloading Windows executables from untrusted sources
- Review application permissions before running unknown software

## Acknowledgments

We thank the security research community for helping keep Whisky secure.
