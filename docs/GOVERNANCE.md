# Governance & continuity

This fork exists because the original [whisky-app/whisky](https://github.com/whisky-app/whisky) was
archived in April 2025 when its maintainer stepped away. It's worth being honest about the fact that
this project carries the same structural risk.

## Who maintains this

Whisky (this fork) is maintained by **one person**, [@frankea](https://github.com/frankea). There is no
team, no company, and no co-maintainer. "Active community fork" describes the development pace and the
openness to contributions — it does not imply a staffed organization.

This is a deliberate choice, not an oversight. Maintaining a Wine wrapper well is mostly steady,
low-drama work, and a small project moves faster without coordination overhead. But it means the
**bus factor is one**, and you should weigh that before depending on this fork for anything critical.

## What that means for you

- **Releases depend on one person's availability.** If @frankea is unavailable for a stretch, expect
  no new releases until they're back. Existing installs keep working.
- **Bug triage is best-effort.** See [`SUPPORT.md`](SUPPORT.md) for what to realistically expect.
- **The runtime is consumed, not owned.** Whisky bundles Wine/DXVK/D3DMetal/DXMT binaries from upstream
  projects (see [`DEPENDENCIES.md`](DEPENDENCIES.md)). If those upstreams stall,
  Whisky's runtime currency is affected — this fork does not build Wine itself.

## If you want to reduce that risk

The most useful thing a contributor could do is **become a second maintainer**. If you have macOS +
Swift + Wine-packaging experience and want to share the load (or be a backstop), open an issue or reach
out — this section will be updated if and when that happens.

## Maintainer continuity (operational)

So that a lapse doesn't silently break things, the maintainer keeps these minimums:

- **Off-machine backup** of the signing material — the Apple Developer ID Application certificate and
  the Sparkle EdDSA private key — so a lost or dead machine doesn't mean a lost release identity. The
  export, encryption, and restore-test procedure is documented in
  [`ReleaseWorkflow.md`](ReleaseWorkflow.md#credential-continuity-backup--recovery); the Sparkle key
  backup is restore-tested against a published appcast signature when the backup is made.
- A **certificate-expiry reminder**: the Developer ID cert and Apple account must not be allowed to
  lapse, or notarized releases stop building with no obvious cause.
- The full release procedure is documented in [`ReleaseWorkflow.md`](ReleaseWorkflow.md) so it is
  reproducible rather than living only in one person's head.

There is intentionally **no shared key escrow** today, because there is no second maintainer to escrow
to. That is the honest state of things; it will change if the project gains a co-maintainer.
