#!/bin/bash
# Script to add LauncherDetection.swift and LauncherDiagnostics.swift to Xcode project
# This adds the files that were created but not registered with Xcode

set -e

PROJECT_FILE="Whisky.xcodeproj/project.pbxproj"

echo "Adding LauncherDetection.swift and LauncherDiagnostics.swift to Xcode project..."

# Generate UUIDs for the new files (Xcode uses 24-character hex strings)
UUID_LAUNCHER_DETECTION_REF=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | tr '[:lower:]' '[:upper:]')
UUID_LAUNCHER_DIAGNOSTICS_REF=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | tr '[:lower:]' '[:upper:]')
UUID_LAUNCHER_DETECTION_BUILD=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | tr '[:lower:]' '[:upper:]')
UUID_LAUNCHER_DIAGNOSTICS_BUILD=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | tr '[:lower:]' '[:upper:]')

echo "Generated UUIDs:"
echo "  LauncherDetection ref: $UUID_LAUNCHER_DETECTION_REF"
echo "  LauncherDiagnostics ref: $UUID_LAUNCHER_DIAGNOSTICS_REF"
echo "  LauncherDetection build: $UUID_LAUNCHER_DETECTION_BUILD"
echo "  LauncherDiagnostics build: $UUID_LAUNCHER_DIAGNOSTICS_BUILD"

# Backup the project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"
echo "Created backup at $PROJECT_FILE.backup"

# Find the Constants.swift line in Utils group and add our files after it
# Pattern: 6763D8F52BC6314100651D27 /* Constants.swift */,
CONSTANTS_LINE=$(grep "Constants.swift \*/," "$PROJECT_FILE")
CONSTANTS_UUID=$(echo "$CONSTANTS_LINE" | awk '{print $1}')

echo "Found Constants.swift with UUID: $CONSTANTS_UUID"

# Add PBXFileReference entries
# Find the Constants.swift PBXFileReference and add ours near it
sed -i.tmp "/6763D8F52BC6314100651D27 .*Constants.swift.*isa = PBXFileReference/a\\
		$UUID_LAUNCHER_DETECTION_REF /* LauncherDetection.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LauncherDetection.swift; sourceTree = \"<group>\"; };\\
		$UUID_LAUNCHER_DIAGNOSTICS_REF /* LauncherDiagnostics.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LauncherDiagnostics.swift; sourceTree = \"<group>\"; };
" "$PROJECT_FILE"

# Add to Utils group
sed -i.tmp "/6763D8F52BC6314100651D27 .*Constants.swift \*\/,/a\\
				$UUID_LAUNCHER_DETECTION_REF /* LauncherDetection.swift */,\\
				$UUID_LAUNCHER_DIAGNOSTICS_REF /* LauncherDiagnostics.swift */,
" "$PROJECT_FILE"

# Add to Sources build phase (find the PBXSourcesBuildPhase section for Whisky target)
# Look for the line with Constants.swift in Sources and add ours
sed -i.tmp "/6763D8F62BC6314100651D27.*in Sources/a\\
				$UUID_LAUNCHER_DETECTION_BUILD /* LauncherDetection.swift in Sources */ = {isa = PBXBuildFile; fileRef = $UUID_LAUNCHER_DETECTION_REF /* LauncherDetection.swift */; };\\
				$UUID_LAUNCHER_DIAGNOSTICS_BUILD /* LauncherDiagnostics.swift in Sources */ = {isa = PBXBuildFile; fileRef = $UUID_LAUNCHER_DIAGNOSTICS_REF /* LauncherDiagnostics.swift */; };
" "$PROJECT_FILE"

# Add the buildfile references to the sources section
# Find the Whisky target's sources and add our build files
sed -i.tmp "/\/\* Constants.swift in Sources \*\//a\\
				$UUID_LAUNCHER_DETECTION_BUILD /* LauncherDetection.swift in Sources */,\\
				$UUID_LAUNCHER_DIAGNOSTICS_BUILD /* LauncherDiagnostics.swift in Sources */,
" "$PROJECT_FILE"

# Clean up temp files
rm -f "$PROJECT_FILE.tmp"

echo ""
echo "✅ Files added to Xcode project successfully!"
echo ""
echo "Next steps:"
echo "1. Open Whisky.xcodeproj in Xcode"
echo "2. Verify the files appear in the Utils folder"
echo "3. Clean build folder (Cmd+Shift+K)"
echo "4. Build the project (Cmd+B)"
echo ""
echo "If there are any issues, restore from backup:"
echo "  mv $PROJECT_FILE.backup $PROJECT_FILE"
