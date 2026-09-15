# Multi-Wine Runtimes

This branch adds per-bottle Wine runtime selection without adding an in-app
runtime downloader.

## Why there is no Wine runtime downloader

Whisky's own update flow downloads Whisky runtime packages, not arbitrary Wine
versions. Those package versions, such as `3.1.1`, are not the same thing as
Wine versions like `7.7`, `9.0`, or `11.0`. Showing them next to a bottle's
Wine runtime selection made the UI misleading.

The app now only lists runtimes that are already available locally or have been
registered manually. A download UI should only be added after choosing a stable
source with direct archive URLs, checksums, and a known unpack layout.

## Runtime Selection

Existing bottles without a runtime setting continue to use:

```text
Default (Wine 11.0)
```

Per-bottle selection is stored in the bottle's `Metadata.plist` under the Wine
configuration.

## Local Runtime Discovery

The runtime picker includes the default Whisky runtime plus usable external
Wine runtimes found in these local locations:

```text
~/Library/Application Support/WhiskyLegacy/Wine-7.7
~/Library/Application Support/com.franke.Whisky/Runtimes/*
~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries
```

For manually added old Wine builds, the preferred location is:

```text
~/Library/Application Support/com.franke.Whisky/Runtimes/<runtime-name>/
```

For the verified local Wine 7.7 runtime, unpack or copy it so the final layout
is:

```text
~/Library/Application Support/com.franke.Whisky/Runtimes/Wine-7.7/bin/wine64
~/Library/Application Support/com.franke.Whisky/Runtimes/Wine-7.7/bin/wineserver
~/Library/Application Support/com.franke.Whisky/Runtimes/Wine-7.7/lib
~/Library/Application Support/com.franke.Whisky/Runtimes/Wine-7.7/share
```

Whisky MultiWine also auto-detects the existing local legacy path:

```text
~/Library/Application Support/WhiskyLegacy/Wine-7.7
```

A runtime is considered usable when it has executable `wine64` or `wine` and
`wineserver` binaries in one of these layouts:

```text
<runtime>/bin/wine64
<runtime>/bin/wineserver

<runtime>/Wine/bin/wine64
<runtime>/Wine/bin/wineserver

<app>.app/Contents/Resources/wine/bin/wine64
<app>.app/Contents/Resources/wine/bin/wineserver
```

You can also register another local runtime manually from Settings by choosing
the folder that contains either `bin/` or `Wine/bin/`.

## Creating a Local Wine 7.7 Archive

This repo includes `scripts/archive-local-runtime.sh` to package a local runtime
without touching any bottle or backup:

```bash
scripts/archive-local-runtime.sh
```

By default it reads:

```text
~/Library/Application Support/WhiskyLegacy/Wine-7.7
```

and writes:

```text
../outputs/runtimes/Wine-7.7.tar.zst
../outputs/runtimes/Wine-7.7.tar.zst.sha256
```

To unpack it on another machine:

```bash
mkdir -p "$HOME/Library/Application Support/com.franke.Whisky/Runtimes"
tar -I zstd -xf Wine-7.7.tar.zst -C "$HOME/Library/Application Support/com.franke.Whisky/Runtimes"
```

After unpacking, open Whisky MultiWine and use either Settings > Wine Runtimes >
Refresh, or the bottle's Wine > Wine Runtime picker.

The verified local Wine 7.7 archive is about 180 MB compressed. GitHub rejects
normal git files larger than 100 MB, so publish that archive as a release asset,
store it with Git LFS, or split it into parts before pushing to a fork. The
local 7.7 runtime contains the GPTK `D3DMetal.framework` payload, so only share
the archive where you are allowed to redistribute those files.

## Building Whisky MultiWine

Use the dedicated build script:

```bash
scripts/build-multiwine.sh
```

It writes:

```text
../outputs/Whisky MultiWine.app
```

If Xcode was just updated, run the script once from a normal Terminal window.
Xcode/SwiftPM may need to write fresh manifest diagnostics and module-cache
files under `~/Library/Caches/org.swift.swiftpm` and `~/.cache/clang`:

```bash
cd /Users/msarychau/Documents/Codex/2026-09-14/referenced-chatgpt-conversation-this-is-an/Whisky-MultiWine
scripts/build-multiwine.sh
```

The app uses bundle id `com.franke.Whisky.MultiWine` and display name
`Whisky MultiWine`, but maps its Application Support folder back to
`com.franke.Whisky` so existing bottles and the Default Wine 11.0 runtime are
shared.

Sparkle auto-update is disabled for this separate MultiWine bundle. The official
updater only ships upstream Whisky; installing that over this app would remove
the MultiWine changes. To keep this branch current, pull/rebase the official
fork and rebuild `Whisky MultiWine.app`.

## Pushing to a Fork

Keep `origin` pointed at the maintained upstream and add a second remote for a
personal fork:

```bash
git remote add personal git@github.com:maksimsarychau/Whisky.git
```

Then push this branch:

```bash
git push -u personal feature/multi-wine-runtime
```

Do not add `../outputs/runtimes/Wine-7.7.tar.zst` to a normal git commit.
GitHub rejects single files larger than 100 MB. Attach it to a release, use Git
LFS, or split it if you decide to distribute the archive.

## Sources Investigated

These sources were investigated as possible download providers:

- Gcenx macOS Wine builds:
  <https://github.com/Gcenx/macOS_Wine_builds/releases>

- Gcenx Wine 7.7 release mirror/index:
  <https://newreleases.io/project/github/Gcenx/macOS_Wine_builds/release/7.7>

- Porting Kit / Wineskin engine index:
  <https://igiteam.github.io/wine_engines/>

- Sikarugir, the maintained Wineskin successor:
  <https://github.com/Sikarugir-App/Sikarugir>

- Apple Game Porting Toolkit notes mentioning Wine 7.7:
  <https://gist.github.com/Frityet/448a945690bd7c8cff5fef49daae858e?permalink_comment_id=5106813>

- CodeWeavers CrossOver 22 announcement mentioning Wine 7.7:
  <https://www.codeweavers.com/support/forums/announce/?t=24%3Bmsg%3D266857>

- WineHQ/Wine source archive for Wine 7.7:
  <https://sourceforge.net/projects/wine/files/Source/wine-7.7.tar.xz/download>

None of these was added as a one-click downloader in this branch. Some are
source-only, some are paid/proprietary, some use a Wineskin engine layout that
needs an adapter, and the old Wine 7.7 macOS release needs verification before
it is safe to expose as an app-managed download.

## Heroes 3 ERA

The local runtime below was verified separately:

```text
~/Library/Application Support/WhiskyLegacy/Wine-7.7
```

It reports `wine-7.7` and can launch the Heroes 3 ERA executable from the
existing bottle. That bottle should keep using `WhiskyLegacy Wine 7.7`.
