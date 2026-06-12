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

# 4. Place DXMT: Windows DLLs mirror the DXVK x64/x32 convention; the unix
#    bridge is additive in Wine's own lib tree (no builtin collision, inert
#    until the app activates the DXMT DLLs per-bottle).
UNIXLIB="$LIB/Wine/lib/wine/x86_64-unix"
[ -d "$UNIXLIB" ] || { echo "error: $UNIXLIB not found; Wine layout changed?" >&2; exit 1; }
mkdir -p "$LIB/DXMT/x64" "$LIB/DXMT/x32"
cp "$DXMT_SRC/x86_64-windows/"*.dll "$LIB/DXMT/x64/"
cp "$DXMT_SRC/i386-windows/"*.dll   "$LIB/DXMT/x32/"
cp "$DXMT_SRC/x86_64-unix/winemetal.so" "$UNIXLIB/winemetal.so"
cp "$DXMT_ARCHIVE_DIR/LICENSE" "$LIB/DXMT/LICENSE"   # MIT: text must ship with the binaries
xattr -rc "$LIB/DXMT" "$UNIXLIB/winemetal.so"

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
  1. Smoke test: install this archive locally, verify bottles + DXVK still work.
  2. gh release create v$NEW_VERSION --repo $REPO --title "Wine Libraries v$NEW_VERSION" \\
       --notes "Adds DXMT $DXMT_VERSION (inert until enabled per-bottle)." "$OUT#Libraries.tar.gz"
  3. Update dist/pages/WhiskyWineVersion.plist: version $NEW_VERSION, sha256 $DIGEST, dxmtVersion $DXMT_VERSION.
  4. Update docs/DEPENDENCIES.md (bundled table + integrity row) and RuntimeTrack DXMT_PINNED.
SUMMARY
