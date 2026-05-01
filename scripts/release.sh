#!/bin/bash
#
# release.sh
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Builds, signs, notarizes, staples, and packages Whisky.app as a DMG.
#
# Prerequisites:
#   - Developer ID Application certificate installed in Keychain
#   - notarytool credentials stored under profile name "AC_PASSWORD"
#
# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 3.0.0

set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/Whisky.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Whisky-$VERSION.dmg"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving Whisky $VERSION"
xcodebuild \
    -project Whisky.xcodeproj \
    -scheme Whisky \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE=Automatic \
    archive

echo "==> Exporting signed app"
rm -rf "$EXPORT_PATH"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist scripts/exportOptions.plist

APP_PATH="$EXPORT_PATH/Whisky.app"
[ -d "$APP_PATH" ] || { echo "Whisky.app not found at $APP_PATH"; exit 1; }

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Building DMG"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Whisky" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "==> Signing DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"

echo "==> Submitting to notary service (this can take several minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying stapled DMG"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || true

echo
echo "Build artifact: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
