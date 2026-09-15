#!/bin/bash
#
# Build an unsigned local Whisky MultiWine app without overwriting an installed
# /Applications/Whisky.app.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
OUTPUT_DIR="${1:-$PROJECT_DIR/../outputs}"
APP_OUTPUT="$OUTPUT_DIR/Whisky MultiWine.app"
CLANG_CACHE="$BUILD_DIR/ModuleCache"
SWIFTPM_CACHE="$BUILD_DIR/SwiftPMModuleCache"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$CLANG_CACHE" "$SWIFTPM_CACHE"

export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE"
export SDKROOT="${SDKROOT:-macosx}"

xcodebuild \
    -project Whisky.xcodeproj \
    -scheme Whisky \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
    -disableAutomaticPackageResolution \
    CODE_SIGNING_ALLOWED=NO \
    SKIP_SWIFTLINT_BUILD_PHASE=YES \
    PRODUCT_BUNDLE_IDENTIFIER=com.franke.Whisky.MultiWine \
    INFOPLIST_KEY_CFBundleDisplayName="Whisky MultiWine" \
    INFOPLIST_KEY_CFBundleName="Whisky MultiWine" \
    build

ditto "$DERIVED_DATA/Build/Products/Release/Whisky.app" "$APP_OUTPUT"

echo "Built $APP_OUTPUT"
echo "Bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_OUTPUT/Contents/Info.plist")"
