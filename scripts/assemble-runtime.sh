#!/bin/bash
# Assembles a Wine Libraries runtime release from the previous published
# release plus the locally archived DXMT payload. Produces Libraries.tar.gz
# and prints its SHA-256 plus the follow-up checklist.
#
# Usage: scripts/assemble-runtime.sh <new-version>   e.g. 3.1.0
#
# The base release is downloaded from GitHub and digest-verified before use;
# the DXMT payload is verified against the archive's SHA256SUMS. Both checks
# fail closed.
set -euo pipefail

NEW_VERSION="${1:?usage: assemble-runtime.sh <new-version>, e.g. 3.1.0}"

# ---- pinned inputs ----------------------------------------------------------
BASE_TAG="v3.0.0"
BASE_SHA256="9c3d2a7d9bb682ae8398d8bae458e3cb52bb9f5a3345fb0830a64d9b6a1025f8"
DXMT_VERSION="0.80"
DXMT_ARCHIVE_DIR="${DXMT_ARCHIVE_DIR:-$HOME/Projects/Whisky-runtime-archive/dxmt-v$DXMT_VERSION}"
DXVK_VERSION="1.10.3"   # carried over unchanged from the base runtime
REPO="frankea/Whisky"
# -----------------------------------------------------------------------------

# DXMT ships only the `wine_builtin_dll=true` release asset, whose
# d3d11/dxgi/d3d10core carry winebuild's "Wine builtin DLL" header signature
# (the 16 bytes at offset 0x40, immediately after the DOS header) and are meant
# to live GLOBALLY in lib/wine. The only difference from the project's
# `wine_builtin_dll=false` source build — the same binaries deployed NATIVE into
# the prefix for per-bottle selection — is that one signature
# (src/d3d11/meson.build runs `winebuild --builtin` only for the builtin
# variant). Removing it reproduces the native variant deterministically, so the
# app can deploy the trio per-bottle like DXVK. winemetal is left untouched: it
# must stay a builtin (its `__wine_unix_call` bridge to winemetal.so only works
# builtin-loaded).
strip_builtin_marker() {
  perl -e '
    my $f = $ARGV[0];
    open my $h, "+<", $f or die "$f: $!";
    binmode $h;
    seek $h, 0x40, 0; read $h, my $sig, 16;
    if ($sig eq "Wine builtin DLL") {
      seek $h, 0x40, 0;
      # Standard DOS stub program (never executed under Wine); anything other
      # than the signature makes Wine classify the PE as native.
      print $h "\x0e\x1f\xba\x0e\x00\xb4\x09\xcd\x21\xb8\x01\x4c\xcd\x21\x90\x90";
    } else {
      die "$f: expected builtin marker at 0x40, found \x22$sig\x22 — DXMT layout changed?";
    }
    close $h;
  ' "$1"
}

IFS='.' read -r MAJOR MINOR PATCH <<< "$NEW_VERSION"
[[ "${MAJOR}${MINOR}${PATCH}" =~ ^[0-9]+$ ]] || { echo "error: version must be X.Y.Z" >&2; exit 1; }

WORKDIR="$(mktemp -d /tmp/whisky-runtime-XXXXXX)"
echo "Workdir: $WORKDIR"

# 1. Verify and unpack the DXMT payload first — it's the cheap local check,
#    so a bad archive fails fast before the multi-hundred-MB base download.
( cd "$DXMT_ARCHIVE_DIR" && shasum -a 256 -c SHA256SUMS --ignore-missing ) \
  || { echo "error: DXMT archive digest mismatch" >&2; exit 1; }
mkdir -p "$WORKDIR/dxmt"
tar -xzf "$DXMT_ARCHIVE_DIR/dxmt-v$DXMT_VERSION-builtin.tar.gz" -C "$WORKDIR/dxmt"
DXMT_SRC="$WORKDIR/dxmt/v$DXMT_VERSION"
[ -d "$DXMT_SRC/x86_64-windows" ] || { echo "error: unexpected DXMT payload layout" >&2; exit 1; }

# 2. Fetch and verify the base runtime.
gh release download "$BASE_TAG" --repo "$REPO" --pattern 'Libraries.tar.gz' --dir "$WORKDIR"
echo "$BASE_SHA256  $WORKDIR/Libraries.tar.gz" | shasum -a 256 -c - \
  || { echo "error: base runtime digest mismatch" >&2; exit 1; }

# 3. Unpack the base runtime.
tar -xzf "$WORKDIR/Libraries.tar.gz" -C "$WORKDIR"
LIB="$WORKDIR/Libraries"
[ -x "$LIB/Wine/bin/wine64" ] || { echo "error: base runtime missing Wine/bin/wine64" >&2; exit 1; }

# 4. Place DXMT. The D3D translation trio (d3d11/dxgi/d3d10core) goes into
#    Libraries/DXMT/{x64,x32} as NATIVE PEs (builtin marker stripped above) —
#    the app copies these into each bottle's system32/syswow64 with the
#    `dxgi,d3d11,d3d10core=n,b` override, so DXMT is selectable PER-BOTTLE
#    without disturbing the shared lib/wine builtins that D3DMetal/wined3d use.
#    winemetal is the exception: it must be a builtin (its winemetal.so unixlib
#    bridge only binds for builtin-loaded modules), so the matching winemetal.dll
#    is synced into BOTH windows trees here (replacing the Gcenx stub) and left
#    builtin-marked. wined3d does not import winemetal, so this global pairing is
#    inert for non-DXMT bottles. The app also copies winemetal.dll into the
#    prefix system32 at enable time so the trio's `winemetal.dll` import resolves
#    and redirects to this builtin.
UNIXLIB="$LIB/Wine/lib/wine/x86_64-unix"
[ -d "$UNIXLIB" ] || { echo "error: $UNIXLIB not found; Wine layout changed?" >&2; exit 1; }
mkdir -p "$LIB/DXMT/x64" "$LIB/DXMT/x32"
cp "$DXMT_SRC/x86_64-windows/"*.dll "$LIB/DXMT/x64/"
cp "$DXMT_SRC/i386-windows/"*.dll   "$LIB/DXMT/x32/"

# Reproduce the wine_builtin_dll=false (native) variant: strip the trio only.
for arch in x64 x32; do
  for dll in d3d11.dll dxgi.dll d3d10core.dll; do
    strip_builtin_marker "$LIB/DXMT/$arch/$dll"
  done
done

# winemetal builtin: pair the .so with its matching .dll in both windows trees.
cp "$DXMT_SRC/x86_64-unix/winemetal.so" "$UNIXLIB/winemetal.so"
cp "$LIB/DXMT/x64/winemetal.dll" "$LIB/Wine/lib/wine/x86_64-windows/winemetal.dll"
I386_BUILTIN="$LIB/Wine/lib/wine/i386-windows"
[ -d "$I386_BUILTIN" ] && cp "$LIB/DXMT/x32/winemetal.dll" "$I386_BUILTIN/winemetal.dll"

cp "$DXMT_ARCHIVE_DIR/LICENSE" "$LIB/DXMT/LICENSE"   # MIT: text must ship with the binaries
xattr -rc "$LIB/DXMT" "$UNIXLIB/winemetal.so" \
  "$LIB/Wine/lib/wine/x86_64-windows/winemetal.dll" "$I386_BUILTIN/winemetal.dll" 2>/dev/null || true

# 5. Rewrite the inner version plist. No sha256 key inside the archive —
#    only the published Pages plist advertises the digest.
PLIST="$LIB/WhiskyWineVersion.plist"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :version:major $MAJOR" -c "Set :version:minor $MINOR" -c "Set :version:patch $PATCH" "$PLIST"
"$PB" -c "Delete :dxvkVersion" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :dxvkVersion string $DXVK_VERSION" "$PLIST"
"$PB" -c "Delete :dxmtVersion" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :dxmtVersion string $DXMT_VERSION" "$PLIST"
"$PB" -c "Delete :sha256" "$PLIST" 2>/dev/null || true
plutil -lint "$PLIST"

# 6. Repack. COPYFILE_DISABLE avoids ._ AppleDouble entries; --no-xattrs keeps
#    quarantine and other xattrs out of the shipped archive.
OUT="$WORKDIR/Libraries-v$NEW_VERSION.tar.gz"
rm -f "$WORKDIR/Libraries.tar.gz"
( cd "$WORKDIR" && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$OUT" Libraries )

DIGEST="$(shasum -a 256 "$OUT" | awk '{print $1}')"
cat <<SUMMARY

Assembled: $OUT
SHA-256:   $DIGEST

Follow-ups (see docs/ReleaseWorkflow.md "Wine Libraries release"):
  1. Smoke test: install this archive locally, verify bottles + DXVK still work,
     AND set a bottle to DXMT and launch a D3D11 title (the trio must load
     'native' and winemetal 'builtin' — check the run log). Sanity:
       grep -aL 'Wine builtin DLL' Libraries/DXMT/x64/d3d11.dll   # trio = native
       grep -al 'Wine builtin DLL' Libraries/Wine/lib/wine/x86_64-windows/winemetal.dll  # winemetal = builtin
  2. cp "$OUT" "$WORKDIR/Libraries.tar.gz" && \\
     gh release create v$NEW_VERSION --repo $REPO --title "Wine Libraries v$NEW_VERSION" \\
       --notes "..." "$WORKDIR/Libraries.tar.gz"
     # The asset FILENAME must be exactly Libraries.tar.gz — the app downloads
     # releases/download/vX.Y.Z/Libraries.tar.gz by name. gh's "path#label"
     # syntax only sets a display label and keeps the wrong filename.
  3. Update dist/pages/WhiskyWineVersion.plist: version $NEW_VERSION, sha256 $DIGEST, dxmtVersion $DXMT_VERSION.
  4. Update docs/DEPENDENCIES.md (bundled table + integrity row) and RuntimeTrack DXMT_PINNED.
SUMMARY
