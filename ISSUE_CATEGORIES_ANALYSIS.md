# Upstream Issue Analysis - whisky-app/whisky

**Analysis Date:** 2026-01-12  
**Total Open Issues:** 435  
**Issues Analyzed:** 150 (representative sample)

## Category Breakdown

### 1. **Bug - Critical System Issues** (Priority: HIGH)
- System crashes/reboots
- Kernel panics  
- Application freezes requiring force quit
- **Examples:** #1164 (CS2 kernel panic), #1014 (system restart), #835 (Rockstar freezes)

### 2. **Bug - Steam/Launcher Issues** (Priority: HIGH)
- steamwebhelper not responding (#946, #1224, #1241)
- Steam connection/download problems (#991, #1123)  
- Rockstar/EA/Epic launcher failures (#835, #1195, #1113)
- Steam overlay issues (#1252)

### 3. **Bug - Game-Specific Compatibility** (Priority: MEDIUM)
- Individual game launch failures
- Game-specific rendering issues
- Performance problems in specific titles
- **Major titles affected:** Genshin Impact, GTA V, Tekken 8, Horizon, Cyberpunk

### 4. **Bug - Graphics/Rendering** (Priority: MEDIUM)
- Texture glitches (#1163 - Genshin Natlan textures)
- Black screens (#1113, #1169)
- Pink/rainbow artifacts (#1162)
- Flickering issues

### 5. **Bug - Controller/Input** (Priority: MEDIUM)  
- Controller detection failures (#1227, #1239, #1284, #1288)
- Button mapping issues  
- Mouse cursor sync problems (#1145, #1289)
- Microphone not working (#1049, #1266)

### 6. **Bug - Audio** (Priority: MEDIUM)
- Audio crackling/stuttering (#1067, #1269, #903)
- No sound output
- Audio sync issues

### 7. **Bug - Installation/Setup** (Priority: MEDIUM)
- WhiskyWine download stuck (#1020, #995)
- Bottle creation failures (#1231, #1237, #1306)
- Dependency installation errors (#1115, #1193)

### 8. **Bug - Performance** (Priority: LOW)
- Low FPS
- Frame pacing issues  
- Resource usage problems (#1010 - 100% CPU)

### 9. **Bug - Compatibility** (Priority: LOW)
- .NET applications (#1317)
- DirectX installation (#1015)
- Windows version compatibility

### 10. **Feature Requests** (Priority: VARIES)
- VR/OpenXR support (#1044)
- HDR support (#875)
- App Nap management (#1297)
- UI improvements (#911, #823, #1247)
- Export/import enhancements

### 11. **Bug - File Operations** (Priority: LOW)
- File path issues (#1325)
- Save file access
- Temp file cleanup (#1251)

### 12. **Bug - Networking** (Priority: LOW)  
- Connection timeouts
- Multiplayer issues (#1146)

## Priority Distribution

- **High Priority:** ~80 issues (18%)
  - System stability
  - Major launcher failures  
  - Widespread compatibility problems

- **Medium Priority:** ~280 issues (64%)
  - Game-specific issues
  - Graphics/audio bugs
  - Controller problems

- **Low Priority:** ~75 issues (17%)
  - Feature requests
  - Minor bugs
  - Edge cases

## Common Patterns Identified

1. **Steam Issues** - Largest category (~100 issues)
   - steamwebhelper crashes
   - Download problems
   - Connection issues

2. **Controller Support** - Consistent problem area (~30 issues)
   - Detection failures
   - Mapping problems
   - Periodic disconnects

3. **Launcher Compatibility** - Major pain point (~50 issues)
   - Rockstar Games Launcher
   - EA App
   - Epic Games

4. **macOS Version Specific** - Some issues tied to Sequoia/Sonoma updates

5. **Graphics API Issues** - Mix of DXVK and D3DMetal problems

## Recommended Label Structure

### Type Labels:
- `bug` - General bugs
- `bug-critical` - System crashes, data loss
- `bug-graphics` - Rendering issues
- `bug-audio` - Sound problems
- `bug-input` - Controller/mouse/keyboard
- `bug-network` - Connection issues
- `enhancement` - Feature requests
- `documentation` - Docs improvements

### Priority Labels:
- `priority-critical` - System instability, data loss
- `priority-high` - Major functionality broken
- `priority-medium` - Specific games/features affected
- `priority-low` - Minor issues, edge cases

### Component Labels:
- `steam` - Steam-related
- `launcher` - Game launchers (Rockstar, EA, Epic)
- `controller` - Input devices
- `performance` - FPS, optimization
- `macos-version` - OS-specific issues
- `wine` - Wine/WhiskyWine core issues
- `dxvk` - DXVK-specific
- `d3dmetal` - D3DMetal-specific

### Status Labels:
- `needs-info` - Awaiting user response
- `upstream` - Tracked from whisky-app/whisky
- `workaround-available` - Has known workaround

## Next Steps

1. Create label structure in frankea/whiskey
2. Create consolidated tracking issues per category
3. Link to relevant upstream issues
4. Document migration mapping
