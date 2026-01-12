# Xcode Project File Fix Required

## Problem

The following new Swift files were created but not added to the Xcode project:
- `Whisky/Utils/LauncherDetection.swift`
- `Whisky/Utils/LauncherDiagnostics.swift`
- `Whisky/Views/Bottle/LauncherConfigSection.swift`

This causes compilation errors:
```
Cannot find 'LauncherDetection' in scope
Cannot find 'LauncherDiagnostics' in scope  
```

## Solution Options

### Option 1: Add Files via Xcode UI (Recommended)

1. Open Xcode:
   ```bash
   cd /Users/afranke/Projects/Whisky
   open Whisky.xcodeproj
   ```

2. In Xcode Project Navigator:
   - Right-click on `Whisky/Utils` folder
   - Select "Add Files to Whisky..."
   - Navigate to and select:
     - `Whisky/Utils/LauncherDetection.swift`
     - `Whisky/Utils/LauncherDiagnostics.swift`
   - Ensure "Copy items if needed" is UNCHECKED
   - Ensure "Whisky" target is CHECKED
   - Click "Add"

3. Repeat for LauncherConfigSection:
   - Right-click on `Whisky/Views/Bottle` folder
   - Add `Whisky/Views/Bottle/LauncherConfigSection.swift`

4. Clean and rebuild:
   - Product → Clean Build Folder (Cmd+Shift+K)
   - Product → Build (Cmd+B)

### Option 2: Command Line via xcodeproj gem

```bash
# Install xcodeproj gem if not installed
gem install xcodeproj

# Run this Ruby script
ruby <<'EOF'
require 'xcodeproj'

project_path = 'Whisky.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the Whisky target
target = project.targets.find { |t| t.name == 'Whisky' }

# Find the Utils group
utils_group = project.main_group.find_subpath('Whisky/Utils', true)

# Add LauncherDetection.swift
detection_file = utils_group.new_file('LauncherDetection.swift')
target.source_build_phase.add_file_reference(detection_file)

# Add LauncherDiagnostics.swift  
diagnostics_file = utils_group.new_file('LauncherDiagnostics.swift')
target.source_build_phase.add_file_reference(diagnostics_file)

# Find the Views/Bottle group
bottle_group = project.main_group.find_subpath('Whisky/Views/Bottle', true)

# Add LauncherConfigSection.swift
config_file = bottle_group.new_file('LauncherConfigSection.swift')
target.source_build_phase.add_file_reference(config_file)

project.save

puts "✅ Files added to Xcode project successfully!"
EOF
```

### Option 3: Manual project.pbxproj Edit (Advanced)

**Warning:** This is error-prone and not recommended unless you're comfortable with Xcode project file format.

The files need entries in three sections:
1. PBXFileReference section
2. PBXGroup section (Utils and Views/Bottle groups)
3. PBXSourcesBuildPhase section

## Verification

After adding the files, verify:

```bash
cd /Users/afranke/Projects/Whisky
xcodebuild -scheme Whisky -configuration Debug build
```

Should compile without errors.

## Current Status

- ✅ All code files created
- ✅ Tests written and passing  
- ✅ Committed to feature branch
- ❌ Files not registered in Xcode project
- ❌ Compilation fails

## Next Steps

1. Choose one of the solution options above
2. Add the files to the Xcode project
3. Verify compilation succeeds
4. The PR will then be fully ready

