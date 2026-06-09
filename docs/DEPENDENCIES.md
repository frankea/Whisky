# Runtime dependencies

Whisky's app code is built from this repo, but the **Wine runtime** it downloads on first launch
(`Libraries.tar.gz`) is assembled from third-party binaries. This file is the single source of truth
for *what versions are bundled* and *where they come from*, so the runtime can't silently go stale and
any future maintainer can reproduce a build. Update it whenever a runtime release is cut.

See [`ReleaseWorkflow.md`](ReleaseWorkflow.md) for the assembly + publish procedure, and
[`.github/workflows/RuntimeTrack.yml`](../.github/workflows/RuntimeTrack.yml) for the automation that
flags when a bundled component falls behind upstream.

## Bundled in runtime `v3.0.0`

| Component | Bundled version | Upstream source | Notes |
|-----------|-----------------|-----------------|-------|
| **Wine** | 11.0 (Gcenx stable) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds/releases) | Wine ships a new stable each January; 11.0 = Jan 2026. |
| **DXVK (macOS)** | 1.10.3 | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases) | Frozen at 1.10.x **by design** — the DXVK 2.x line needs Vulkan 1.3 features MoltenVK/macOS don't expose. Not stale; do not "upgrade" to upstream 2.x. |
| **D3DMetal** | from Apple Game Porting Toolkit | [Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/) | **Apple-proprietary. Extracted, never built.** Redistribution is governed by Apple's GPTK license — review terms before bumping. The default backend for most titles. |
| **MoltenVK** | (confirm against published archive) | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK/releases) | Vulkan→Metal; underpins the DXVK path. |
| **msync** | (confirm against published archive) | [marzent/wine-msync](https://github.com/marzent/wine-msync) | Mach-based synchronization patch in the Gcenx build. |

> The exact MoltenVK/msync versions live inside the published `Libraries.tar.gz`, not this repo. When
> you cut a runtime release, read them off the build and fill them in here so this table is authoritative.

### Archive integrity

| Artifact | SHA-256 |
|----------|---------|
| `Libraries.tar.gz` (`v3.0.0`) | `9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025f8` |

The same digest is published in
[`dist/pages/WhiskyWineVersion.plist`](../dist/pages/WhiskyWineVersion.plist) under the `sha256` key.
The app verifies the downloaded archive against it before installing and **fails closed** on a
mismatch (a corrupted or truncated download is the common cause). This is an integrity check, not a
substitute for HTTPS transport trust. When cutting a runtime release, compute the digest of the exact
published asset (`shasum -a 256 Libraries.tar.gz`) and update **both** this table and the plist — an
incorrect value will block every fresh install.

## Planned additions

| Component | Target version | Upstream source | Notes |
|-----------|----------------|-----------------|-------|
| **DXMT** | 0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt/releases) | Direct3D→Metal, production-stable as of Apr 2026 and shipping in CrossOver 26. Bundle the project's **prebuilt release** (no from-source build) and expose as a per-game graphics backend. Benchmark vs. DXVK 1.10.3 on lower-spec Macs before defaulting. |

## Tracking cadence

- **Wine:** check each January for the new stable (next: **Wine 12, ~Jan 2027**). Test before bundling.
- **Wine / DXVK-macOS / DXMT:** `RuntimeTrack.yml` polls these GitHub release feeds weekly and opens an
  issue when a bundled version is behind. Triage; bumping is a deliberate, tested decision, not automatic.
- **D3DMetal (GPTK):** Apple ships it as a Game Porting Toolkit download with no GitHub release feed, so
  it is **tracked manually** — check Apple's GPTK page when a new GPTK lands.
- **Security:** a critical Wine/DXVK CVE should trigger an out-of-band runtime rebuild + app release.
  See `SECURITY.md`.

## Why we consume rather than build

Building and maintaining the macOS Wine runtime is the single most specialized, fragile job in this
ecosystem — it is effectively Gcenx's entire role and CodeWeavers' paid team's. On a deliberately
solo-maintained project (see [`GOVERNANCE.md`](GOVERNANCE.md)), taking that on would
*deepen* the bus-factor risk it was meant to reduce. So we consume upstream binaries and invest instead
in **discipline**: pinned versions, automated staleness detection, and a documented, reproducible assembly.
