# Runtime dependencies

Whisky's app code is built from this repo, but the **Wine runtime** it downloads on first launch
(`Libraries.tar.gz`) is assembled from third-party binaries. This file is the single source of truth
for *what versions are bundled* and *where they come from*, so the runtime can't silently go stale and
any future maintainer can reproduce a build. Update it whenever a runtime release is cut.

See [`ReleaseWorkflow.md`](ReleaseWorkflow.md) for the assembly + publish procedure, and
[`.github/workflows/RuntimeTrack.yml`](../.github/workflows/RuntimeTrack.yml) for the automation that
flags when a bundled component falls behind upstream.

## Bundled in runtime `v3.1.1`

| Component | Bundled version | Upstream source | Notes |
|-----------|-----------------|-----------------|-------|
| **Wine** | 11.0 (Gcenx `11.0_1` repack) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds/releases) | Wine ships a new stable each January; 11.0 = Jan 2026. The Gcenx tag is `11.0_1` (a repack of the same Wine 11.0; the bare `11.0` tag was retired) — `RuntimeTrack.yml` pins that exact tag. |
| **DXVK (macOS)** | 1.10.3 | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases) | Frozen at 1.10.x **by design** — the DXVK 2.x line needs Vulkan 1.3 features MoltenVK/macOS don't expose. Not stale; do not "upgrade" to upstream 2.x. |
| **DXMT** | 0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt/releases) | Direct3D 11 → Metal. Bundled from the project's prebuilt v0.80 release — the **last MIT-licensed** build (v1.0+ is LGPL; bumping past 0.80 is a deliberate relicensing decision, not routine drift). The release ships only the `wine_builtin_dll=true` asset (trio carries winebuild's "Wine builtin DLL" header marker, meant for a *global* `lib/wine` install). For **per-bottle** selection, `scripts/assemble-runtime.sh` strips that marker from `d3d11`/`dxgi`/`d3d10core` (x64+x32) — deterministically reproducing the project's `wine_builtin_dll=false` (native) variant — and stages them in `Libraries/DXMT/{x64,x32}`. The app then copies the native trio into each bottle's `system32`/`syswow64` with `dxgi,d3d11,d3d10core=n,b`, exactly like DXVK. `winemetal` stays a builtin: its `winemetal.dll` is synced into both Wine windows trees (paired with `winemetal.so` in the unix tree) and the app copies it into the prefix as the import redirect. Selectable per-bottle/per-program in app ≥ 3.4.0 (Experimental); requires a runtime assembled by the current script (the older builtin-variant payload is gated off, since it would silently redirect to wined3d). |
| **D3DMetal** | from Apple Game Porting Toolkit | [Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/) | **Apple-proprietary. Extracted, never built.** Redistribution is governed by Apple's GPTK license — review terms before bumping. The default backend for most titles. |
| **MoltenVK** | (confirm against published archive) | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK/releases) | Vulkan→Metal; underpins the DXVK path. |
| **msync** | (confirm against published archive) | [marzent/wine-msync](https://github.com/marzent/wine-msync) | Mach-based synchronization patch in the Gcenx build. |

> The exact MoltenVK/msync versions live inside the published `Libraries.tar.gz`, not this repo. When
> you cut a runtime release, read them off the build and fill them in here so this table is authoritative.

### Archive integrity

| Artifact | SHA-256 |
|----------|---------|
| `Libraries.tar.gz` (`v3.1.1`) | `01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3` |
| `Libraries.tar.gz` (`v3.1.0`) | `86e2d54a60736f27e6ce82cacf2a91e500c20f6d32ae959a16afd912e6b03096` |
| `Libraries.tar.gz` (`v3.0.0`) | `9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025f8` |

The same digest is published in
[`dist/pages/WhiskyWineVersion.plist`](../dist/pages/WhiskyWineVersion.plist) under the `sha256` key.
The app verifies the downloaded archive against it before installing and **fails closed** on a
mismatch (a corrupted or truncated download is the common cause). This is an integrity check, not a
substitute for HTTPS transport trust. When cutting a runtime release, compute the digest of the exact
published asset (`shasum -a 256 Libraries.tar.gz`) and update **both** this table and the plist — an
incorrect value will block every fresh install.

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
