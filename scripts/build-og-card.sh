#!/bin/bash
#
# build-og-card.sh
#
# Renders dist/pages/_og-card-source.html to images/og-card.png at 1200x630
# using headless Chrome. The PNG is the OpenGraph/Twitter card image
# referenced by dist/pages/index.html. Edit the source HTML, then re-run.
#
# Usage: scripts/build-og-card.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$PROJECT_DIR/dist/pages/_og-card-source.html"
OUTPUT="$PROJECT_DIR/images/og-card.png"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

[ -x "$CHROME" ] || { echo "Chrome not found at $CHROME (set CHROME=...)"; exit 1; }
[ -f "$SOURCE" ] || { echo "Source HTML not found at $SOURCE"; exit 1; }

cd "$PROJECT_DIR"

# Use a temp profile so Chrome doesn't prompt or pollute the user's profile.
TMPDIR_CHROME="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CHROME"' EXIT

"$CHROME" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --user-data-dir="$TMPDIR_CHROME" \
    --window-size=1200,630 \
    --screenshot="$OUTPUT" \
    "file://$SOURCE"

# Verify dimensions
DIMS=$(sips -g pixelWidth -g pixelHeight "$OUTPUT" | awk '/pixelWidth|pixelHeight/ {print $2}' | xargs echo)
[ "$DIMS" = "1200 630" ] || { echo "Wrong dimensions: $DIMS (expected 1200 630)"; exit 1; }

echo "OK: $OUTPUT (1200x630)"
