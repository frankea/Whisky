# Runtime dependencies

Whisky's app code is built from this repo, but the **Wine runtime** it downloads on first launch
(`Libraries.tar.gz`) is assembled from third-party binaries. This file is the single source of truth
for *what versions are bundled* and *where they come from*, so the runtime can't silently go stale and
any future maintainer can reproduce a build. Update it whenever a runtime release is cut.

See [`ReleaseWorkflow.md`](ReleaseWorkflow.md) for the assembly + publish procedure, and
[`.github/workflows/RuntimeTrack.yml`](../.github/workflows/RuntimeTrack.yml) for the automation that
flags when a bundled component falls behind upstream.

## Bundled in runtime `v4.8.3` (default for app 3.10.0 and later)

Built from source by CI on [frankea/winecx-gptk](https://github.com/frankea/winecx-gptk) (a mirror of
dappermint/winecx-gptk carrying Whisky's macOS 15 floor and winebus SDL build change, plus the fiber
fix from dappermint/winecx-gptk#25), commit `12af865`, from upstream `58b27bf`
(the tree behind upstream's `runtime-v4.8.1`). Served by `dist/pages/WhiskyWineVersion-v4.plist`.

| Component | Bundled version | Upstream source | Notes |
|-----------|-----------------|-----------------|-------|
| **Wine** | 11.19, CrossOver-based winecx `9f3f644` | [dappermint/winecx-gptk](https://github.com/dappermint/winecx-gptk) | Tracks upstream Wine releases with CrossOver's macOS patches rebased on top. Built at `MACOSX_DEPLOYMENT_TARGET=15.0` on a hosted macos-15 runner. Carries the fiber fix from dappermint/winecx-gptk#25 until it lands upstream. |
| **DXVK (macOS)** | 1.10.3 | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases) | Same frozen 1.10.x line as the 3.x engine. The runtime also ships DXVK's 32-bit `dxgi.dll`, but the app keeps Wine's builtin dxgi in `syswow64` (DXVK's d3d11 runs on it), so that file goes unused. No `d3d9` on purpose (Wine's builtin d3d9 is used). |
| **DXMT** | 0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt/releases) | Frozen at the last MIT release, as below. |
| **MoltenVK** | 1.4.2 | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK/releases) | |
| **SDL2** | 2.32.10 | [libsdl-org/SDL](https://github.com/libsdl-org/SDL/releases) | Built from the pinned release for winebus's controller bus (nixpkgs' `sdl2` is sdl2-compat, which loads SDL3). |
| **gstreamer / Wine Gecko / Wine Mono** | 1.26.3 / 2.47.4 / 11.3.0 | Wine's media stack and its HTML and .NET runtimes | |
| **msync** | winecx rewrite | [dappermint/winecx-gptk](https://github.com/dappermint/winecx-gptk) | On by default. |
| **D3DMetal** | not bundled | [Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/) | The runtime is GPTK-capable (`gptkCapable`); the user imports Apple's payload, which the app deploys into the runtime. The runtime ships the `lib/gptk-video` interposers (`d3d12shim.dll`, `dxgishim.dll`). |

## Bundled in runtime `v3.1.1` (frozen, for apps before 3.10.0)

Served by `dist/pages/WhiskyWineVersion.plist`, which apps before 3.10.0 read. It stays on this
engine; only a security fix should change it.

| Component | Bundled version | Upstream source | Notes |
|-----------|-----------------|-----------------|-------|
| **Wine** | 11.0 (Gcenx `11.0_1` repack) | [Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds/releases) | Wine ships a new stable each January; 11.0 = Jan 2026. The Gcenx tag is `11.0_1` (a repack of the same Wine 11.0; the bare `11.0` tag was retired). This engine is frozen, so `RuntimeTrack.yml` no longer tracks it. |
| **DXVK (macOS)** | 1.10.3 | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS/releases) | Frozen at 1.10.x **by design** — the DXVK 2.x line needs Vulkan 1.3 features MoltenVK/macOS don't expose. Not stale; do not "upgrade" to upstream 2.x. |
| **DXMT** | 0.80 | [3Shain/dxmt](https://github.com/3Shain/dxmt/releases) | Direct3D 11 → Metal. Bundled from the project's prebuilt v0.80 release, the **last MIT-licensed** build (everything after the v0.80 tag is LGPL). **Whisky stays on 0.80 permanently** (decided November 2026, see #138): later DXMT releases are not adopted, including fixes made upstream after 0.80, and `RuntimeTrack.yml` reports DXMT as frozen instead of filing drift. The release ships only the `wine_builtin_dll=true` asset (trio carries winebuild's "Wine builtin DLL" header marker, meant for a *global* `lib/wine` install). For **per-bottle** selection, `scripts/assemble-runtime.sh` strips that marker from `d3d11`/`dxgi`/`d3d10core` (x64+x32), deterministically reproducing the project's `wine_builtin_dll=false` (native) variant, and stages them in `Libraries/DXMT/{x64,x32}`. The app then copies the native trio into each bottle's `system32`/`syswow64` with `dxgi,d3d11,d3d10core=n,b`, exactly like DXVK. When Steam `-applaunch` carries a game whose plan is DXMT, `system32` keeps DXVK for Steam and the native trio for the game's architecture is also copied beside the game's executables, which Wine's loader searches first; the copies are tracked by SHA-256 in the bottle's `.dxmt-game-folder-copies.plist` and removed once the game's plan moves to another backend, on its next launch from Whisky or the next start of Steam (#378). `winemetal` stays a builtin: its `winemetal.dll` is synced into both Wine windows trees (paired with `winemetal.so` in the unix tree) and the app copies it into the prefix as the import redirect. Selectable per-bottle/per-program in app ≥ 3.4.0 (Experimental); requires a runtime assembled by the current script (the older builtin-variant payload is gated off, since it would silently redirect to wined3d). |
| **D3DMetal** | from Apple Game Porting Toolkit | [Apple GPTK](https://developer.apple.com/games/game-porting-toolkit/) | **Apple-proprietary. Extracted, never built.** Redistribution is governed by Apple's GPTK license; review terms before bumping. Not bundled in the published runtime, and this engine cannot run it: a GPTK payload imported in Settings is stored but only deployed once a GPTK-capable engine (4.x) is installed. Since app 3.5.2 the "Recommended" backend resolves to DXMT (or DXVK) when the payload is absent, and the picker greys D3DMetal out rather than offering a silent wined3d fallback. |
| **MoltenVK** | (confirm against published archive) | [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK/releases) | Vulkan→Metal; underpins the DXVK path. |
| **msync** | not included | n/a | This engine's Wine reads neither `WINEMSYNC` nor `WINEESYNC`, so the Enhanced Sync setting has no effect on Wine here. The 4.x engine implements msync. |

> The exact MoltenVK version lives inside the published `Libraries.tar.gz`, not this repo. When
> you cut a runtime release, read it off the build and fill it in here so this table is authoritative.

### Archive integrity

| Artifact | SHA-256 |
|----------|---------|
| `Libraries.tar.gz` (`v4.8.3`) | `08ffabd7b7c352470faee2b1d51061b341316e401439ca805c5302acc2fb8818` |
| `Libraries.tar.gz` (`v3.1.1`) | `01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3` |
| `Libraries.tar.gz` (`v3.1.0`) | `86e2d54a60736f27e6ce82cacf2a91e500c20f6d32ae959a16afd912e6b03096` |
| `Libraries.tar.gz` (`v3.0.0`) | `9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025f8` |

The same digest is published under the `sha256` key of the feed that serves that engine:
[`dist/pages/WhiskyWineVersion-v4.plist`](../dist/pages/WhiskyWineVersion-v4.plist) for 4.x, and
[`dist/pages/WhiskyWineVersion.plist`](../dist/pages/WhiskyWineVersion.plist) for 3.1.1.
The app verifies the downloaded archive against it before installing and **fails closed** on a
mismatch (a corrupted or truncated download is the common cause). This is an integrity check, not a
substitute for HTTPS transport trust. When cutting a runtime release, compute the digest of the exact
published asset (`shasum -a 256 Libraries.tar.gz`) and update **both** this table and the plist — an
incorrect value will block every fresh install.

## Bundled in the app

These ship **inside the app bundle** (`Whisky.app/Contents/Resources/`), committed to this repo under
[`Libraries/`](../Libraries) and copied in by the app target's "Embed WhiskyCmd" build phase. They are
**not** part of the downloaded `Libraries.tar.gz` runtime — bundling them in the app means a fix reaches
every install through a normal app update, with no runtime re-download.

| Component | Pinned version | Upstream source | Notes |
|-----------|----------------|-----------------|-------|
| **winetricks** | `20260125` | [Winetricks/winetricks](https://github.com/Winetricks/winetricks/releases/tag/20260125) | Self-contained POSIX shell script (LGPL-2.1+). Drives dependency installs (VC++, .NET, DirectX, fonts) and verb queries. Invoked as `bash winetricks <verb>` with the bundled `cabextract` and the runtime's `Wine/bin` on `PATH`. Bump by re-fetching `src/winetricks` at a newer release tag and regenerating `verbs.txt`. |
| **verbs.txt** | generated from winetricks `20260125` | produced by `winetricks list-all` | Verb catalog shown in the Winetricks browser. Regenerate whenever winetricks is bumped: `sh Libraries/winetricks list-all` (drop the leading platform-warning line so the file starts at the first `=====` category header). |
| **cabextract** | prebuilt arm64 binary | [cabextract.org.uk](https://www.cabextract.org.uk/) | Extracts Microsoft `.cab` archives; a hard dependency of many winetricks verbs. Committed as a code-signed-on-copy Mach-O executable. |

## Swift packages

Resolved in `Whisky.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Dependabot
watches only `WhiskyKit/Package.swift`, so the packages the Xcode project adds (Sparkle, posthog-ios,
swift-argument-parser) are bumped by hand.

| Package | Version | Used for |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.10.1 | In-app updates (includes the fixes for GHSA-g3hp-f6mg-559v and GHSA-hg88-v3cw-3qrh, first patched in 2.9.2; stay at 2.9.2 or later) |
| [posthog-ios](https://github.com/PostHog/posthog-ios) | 3.59.3 | Opt-in telemetry (see [SECURITY.md](../SECURITY.md)) |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.5.0 | The WhiskyCmd command line tool |
| [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) | 0.4.0 | Version comparison (a WhiskyKit dependency, so Dependabot tracks it) |

## Tracking cadence

- **Wine (4.x engine):** `RuntimeTrack.yml` polls dappermint/winecx-gptk's `runtime-v*` releases weekly
  and opens an issue when upstream is ahead of the tree the current engine was built from. Rebuild on
  the mirror, publish a beta, test, then promote (see `ReleaseWorkflow.md`).
- **DXVK-macOS:** polled weekly the same way. Triage; bumping is a deliberate, tested decision, not automatic.
- **DXMT:** frozen at 0.80, the last MIT-licensed release. `RuntimeTrack.yml` still lists the latest
  upstream release in its summary but never files drift for it.
- **D3DMetal (GPTK):** Apple ships it as a Game Porting Toolkit download with no GitHub release feed, so
  it is **tracked manually** — check Apple's GPTK page when a new GPTK lands.
- **Security:** a critical Wine/DXVK CVE should trigger an out-of-band runtime rebuild + app release.
  See `SECURITY.md`.
- **winetricks:** releases roughly monthly; tracked manually (no feed in `RuntimeTrack.yml`). Bump when a
  needed verb's download URL breaks or a new component is required — it rides an app release, not a runtime one.

## Why we consume rather than build

Building and maintaining the macOS Wine runtime is the single most specialized, fragile job in this
ecosystem — it is effectively Gcenx's entire role and CodeWeavers' paid team's. On a deliberately
solo-maintained project (see [`GOVERNANCE.md`](GOVERNANCE.md)), taking that on would
*deepen* the bus-factor risk it was meant to reduce. So we consume upstream binaries and invest instead
in **discipline**: pinned versions, automated staleness detection, and a documented, reproducible assembly.
