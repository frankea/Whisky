#!/bin/bash
#
# Package a local Wine runtime for manual installation on another machine.

set -euo pipefail

USER_HOME="$(cd ~ && pwd)"
SOURCE_RUNTIME="${1:-$USER_HOME/Library/Application Support/WhiskyLegacy/Wine-7.7}"
OUTPUT_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/../outputs/runtimes}"
RUNTIME_NAME="$(basename "$SOURCE_RUNTIME")"
ARCHIVE="$OUTPUT_DIR/$RUNTIME_NAME.tar.zst"

if [[ ! -x "$SOURCE_RUNTIME/bin/wine64" && ! -x "$SOURCE_RUNTIME/bin/wine" ]]; then
    echo "Runtime is missing bin/wine64 or bin/wine: $SOURCE_RUNTIME" >&2
    exit 1
fi

if [[ ! -x "$SOURCE_RUNTIME/bin/wineserver" ]]; then
    echo "Runtime is missing bin/wineserver: $SOURCE_RUNTIME" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

COPYFILE_DISABLE=1 tar -c -f - -C "$(dirname "$SOURCE_RUNTIME")" "$RUNTIME_NAME" | zstd -19 -T0 -o "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

echo "Created $ARCHIVE"
cat "$ARCHIVE.sha256"
echo
echo "Unpack with:"
echo "mkdir -p \"\$HOME/Library/Application Support/com.franke.Whisky/Runtimes\""
echo "tar -I zstd -xf \"$ARCHIVE\" -C \"\$HOME/Library/Application Support/com.franke.Whisky/Runtimes\""
