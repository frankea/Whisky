# Governance & continuity

This fork exists because the original [whisky-app/whisky](https://github.com/whisky-app/whisky) was
archived in April 2025 when its maintainer stepped away. It's worth being honest about the fact that
this project carries the same structural risk.

## Who maintains this

Whisky (this fork) is maintained by **one person**, [@frankea](https://github.com/frankea), who holds
final authority over the repository, releases, and the signing identity. Since August 2026,
[@dappermint](https://github.com/dappermint) serves as **project member (triage)**: they triage issues,
review pull requests, and help manage the tracker, but hold no commit access and no release capability.
There is still no team and no company. "Active community fork" describes the development pace and the
openness to contributions; it does not imply a staffed organization.

This is a deliberate choice, not an oversight. Maintaining a Wine wrapper well is mostly steady,
low-drama work, and a small project moves faster without coordination overhead. But it means the
**bus factor for releases is one**, and you should weigh that before depending on this fork for
anything critical.

## Trust is granted in stages

Roles here expand with track record:

1. **Contributor**: pull requests, reviewed and merged by the maintainer.
2. **Project member (triage)**: issue triage, labels, and pull request review. No commit access.
3. **Co-maintainer (commit)**: direct commit and merge rights. Considered only after a sustained
   record at the previous stage, and only alongside branch protection requiring review on `main`.

Regardless of stage, **release signing stays with the maintainer**: the Developer ID certificate, the
Sparkle update key, and the notarization credentials exist only on the maintainer's machines and are
never shared. Nothing reaches users through the release or update channel without the maintainer
building and signing it.

## What that means for you

- **Releases depend on one person's availability.** If @frankea is unavailable for a stretch, expect
  no new releases until they're back. Existing installs keep working.
- **Bug triage is best-effort.** See [`SUPPORT.md`](SUPPORT.md) for what to realistically expect.
- **The runtime is consumed, not owned.** Whisky's runtime bundles Wine, DXVK, DXMT and MoltenVK from
  upstream projects (see [`DEPENDENCIES.md`](DEPENDENCIES.md)); D3DMetal is not bundled and comes from
  Apple's Game Porting Toolkit, which you import yourself. The Wine engine is built by CI from a mirror
  of dappermint/winecx-gptk with a few Whisky patches, not developed here, so if those upstreams stall,
  Whisky's runtime currency is affected.

## If you want to reduce that risk

The most useful thing a contributor could do is **become a second maintainer**. If you have macOS +
Swift + Wine-packaging experience and want to share the load (or be a backstop), open an issue or reach
out. This path is real: it is how the current project member role came to be (see issue #194), and it
follows the staged model above.

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

There is intentionally **no shared key escrow** today: the project member role does not carry release
responsibilities, so there is still nobody to escrow to. That is the honest state of things; it will
change if the project gains a co-maintainer with release duties.
