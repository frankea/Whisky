# Runtime Archives

This directory is reserved for optional local Wine runtime archives.

Do not commit large runtime binaries directly to git unless the repository uses
Git LFS or the archive is split into files below GitHub's limit. The verified
local Wine 7.7 runtime is about 180 MB compressed and includes GPTK/D3DMetal
payload files, so only redistribute it where the licenses allow that.

To create the local Wine 7.7 archive:

```bash
scripts/archive-local-runtime.sh
```

The script writes the archive and checksum to:

```text
../outputs/runtimes/Wine-7.7.tar.zst
../outputs/runtimes/Wine-7.7.tar.zst.sha256
```

To install a runtime archive for Whisky MultiWine:

```bash
mkdir -p "$HOME/Library/Application Support/com.franke.Whisky/Runtimes"
tar -I zstd -xf Wine-7.7.tar.zst -C "$HOME/Library/Application Support/com.franke.Whisky/Runtimes"
```

After unpacking, the runtime should look like this:

```text
~/Library/Application Support/com.franke.Whisky/Runtimes/Wine-7.7/bin/wine64
~/Library/Application Support/com.franke.Whisky/Runtimes/Wine-7.7/bin/wineserver
```
