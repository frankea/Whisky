# Whisky Issue Analysis and Prioritization Report

## Executive Summary

**Source Repository:** `Whisky-App/Whisky`  
**Total Open Issues:** 434  
**Analysis Date:** 2026-01-05

---

## Issue Distribution by Category

### Label Distribution
| Label | Count | Description |
|-------|-------|-------------|
| wine-bug | ~45 | Problems with Wine |
| d3dm-bug | ~8 | D3DMetal rendering issues |
| whisky-bug | ~12 | Problems with Whisky app |
| No labels | ~369 | Unlabeled issues |

### Top Categories by Issue Count

1. **Game Compatibility Issues** (~180 issues)
   - Various games not launching or crashing
   - Performance issues
   - Graphics/audio problems

2. **Steam/Platform Issues** (~50 issues)
   - Steam not launching
   - Steam update problems
   - Steam web helper issues

3. **Bottle Management** (~25 issues)
   - Bottles not showing
   - Bottles disappearing
   - Bottle creation failures

4. **Launcher/Platform Specific** (~40 issues)
   - Battle.net issues
   - EA App/Origin issues
   - Epic Launcher issues
   - Ubisoft Connect issues

5. **Audio Issues** (~15 issues)
   - Sound lag
   - No audio
   - Audio stuttering

6. **Controller/Input Issues** (~20 issues)
   - Controllers not detected
   - Controller mapping issues

7. **Download/Installation Issues** (~10 issues)
   - WhiskyWine download failures
   - GPTK installation issues

---

## Critical Priority Issues (Must Fix)

### 🔴 P0 - Core Functionality Broken

| Issue # | Title | Impact | Affected Users |
|---------|-------|--------|----------------|
| **#1347** | Can't create Bottels | CRITICAL - Cannot use app | Multiple |
| **#1311** | After installation, a bottle is not created | CRITICAL | Multiple |
| **#1029** | Can't create Bottels | CRITICAL | Multiple |
| **#760** | Whisky not able to create bottles | CRITICAL | Multiple |
| **#798** | Bottles disappearing on creation | CRITICAL | Multiple |
| **#359** | Bottles disappear | CRITICAL | Multiple |
| **#1364** | The added bottles are not shown | HIGH - UI bug | Multiple |
| **#819** | Bottle created in folder but won't show up in app | HIGH | Multiple |
| **#1306** | my whisky bottle keeps disappearing | HIGH | Multiple |

### 🔴 P0 - macOS Compatibility

| Issue # | Title | macOS Version |
|---------|-------|---------------|
| **#1372** | macOS 15.4.1 breaks Steam | 15.4.1 |
| **#1310** | Whisky version 2.3.4 graphic problems | 15.3 |
| **#1307** | Whiskey not running SteamSetup.exe | 15.3 |
| **#1295** | Unable to open Mihoyo launcher | 15.0.1 |
| **#1020** | Can't download WhiskyWine (Zero KB) | Network/OS |

---

## High Priority Issues

### 🟠 P1 - Major Feature Broken

| Issue # | Title | Category |
|---------|-------|----------|
| **#1361** | PayDay 2 went from 50 FPS to 15 FPS | Performance Regression |
| **#1365** | Applications and apps not working/open | App Launching |
| **#1343** | The Config Keeps Freezing | UI Freeze |
| **#1338** | Steam won't open | Platform |
| **#1335** | Rockstar Games Launcher failed to initialize | Platform |
| **#1322** | Origin Never Loads | Platform |
| **#1321** | No EA App Support | Feature Request |
| **#1267** | steam unsuccessful install and not responding | Installation |

### 🟠 P1 - Common Game Issues

| Issue # | Title | Frequency |
|---------|-------|-----------|
| **#1369** | Genshin Impact 5.5 crash | Common |
| **#1313** | failed to load il2cpp | Common (Unity) |
| **#1312** | Fatal error: "Failed to load il2cpp" | Common (Unity) |
| **#1281** | Graphics error with Fields of Mistria | Multiple reports |
| **#1268** | Cities Skyline2 1.2.0f2 failed to launch | Multiple |
| **#1265** | Honkai star rail crash on open | Multiple |

---

## Medium Priority Issues

### 🟡 P2 - Game Compatibility

| Issue # | Title | Status |
|---------|-------|--------|
| **#1350** | Futureport 82 In game videos display white screen | Visual |
| **#1320** | Monster hunter world iceborne freezes | Game-specific |
| **#1319** | Library of Ruina resolution/text issues | Visual |
| **#1316** | Dying light 2 Crashes after falling into water | Game-specific |
| **#1315** | Oblivion Crashes After a Few Inputs | Game-specific |
| **#1290** | A Steam game has no audio | Audio |
| **#1289** | Apps running in retina mode receive wrong mouse position | Input |
| **#1278** | wine64 file does not exist | Core |
| **#1269** | Age of Empires 2 HD audio skipping | Audio |
| **#1258** | Incorrect work of opened game | General |

### 🟡 P2 - Platform Launchers

| Issue # | Title |
|---------|-------|
| **#1332** | Controller working on Whisky but not detected by steam |
| **#1331** | My AC Unity download is stuck |
| **#1329** | Meta Editor 5 Navigator didn't show the ui |
| **#1327** | Rainbow Six doesn't run |
| **#1325** | WhiskyCmd run: what path should I use? |
| **#1323** | Nobunaga's Ambition crashes |

---

## Feature Requests (Nice to Have)

### 🟢 P3

| Issue # | Title | Votes/Similarity |
|---------|-------|------------------|
| **#1297** | Add App Nap Management | Stability |
| **#1302** | Ability to change resolution | UI |
| **#1287** | Special K | Gaming tools |
| **#1266** | Voice chat/Microphone support | Audio |
| **#1225** | Ability to run .exe as admin | Feature |
| **#1201** | Dark mode for winetricks | UI |
| **#1198** | Add keyboard shortcuts | UI |
| **#1165** | HDR support | Graphics |
| **#1146** | Add search in winetricks | UI |
| **#1136** | Discord RPC | Integration |
| **#1098** | Game Mode when playing | Gaming |
| **#1060** | Show GPU info in settings | UI |

---

## Recommended Implementation Order

### Phase 1: Core Stability (Week 1-2)
1. **Fix bottle creation** (#1347, #1311, #1029, #760)
   - Priority: CRITICAL
   - Root cause: Likely macOS 15.x sandbox/API changes
   
2. **Fix bottles not showing** (#1364, #798, #359, #1306)
   - Priority: CRITICAL
   - Root cause: Persistence layer issue

3. **Fix macOS 15.4.1 Steam compatibility** (#1372)
   - Priority: HIGH
   - Workaround: Investigate wine-preloader changes

### Phase 2: Performance (Week 3)
4. **Investigate PayDay 2 regression** (#1361)
   - Bisect to find which change caused 50→15 FPS drop
   - Check wine version changes

### Phase 3: Common Issues (Week 4-6)
5. **Fix il2cpp errors** (#1313, #1312)
   - Unity game crashes
   - DLL dependencies

6. **Fix Genshin Impact** (#1369)
   - Popular game, multiple reports

### Phase 4: Platform Support (Week 7-8)
7. **EA App support** (#1321)
   - Feature request, high demand

8. **Battle.net fixes** (#682, #666, #813)
   - Ongoing issues

---

## Dependencies Between Issues

```
Bottle Issues (Critical Path)
├── #1347 → #1029 → #760 (duplicate chain)
├── #1311 → #1306 → #798 → #359 (disappearing bottles)
└── #1364 → #819 (UI display issues)

macOS 15.x Compatibility
├── #1372 (Steam on 15.4.1)
├── #1310 (Graphics on 15.3)
├── #1307 (Steam on 15.3)
└── #1295 (Mihoyo on 15.0.1)

Unity il2cpp Issues
├── #1313 (Pantheon)
├── #1312 (DJMAX)
└── #1276 (Farming Simulator 25)
```

---

## Label Analysis

### wine-bug Issues (Need Wine Upstream Fix)
Issues requiring changes to the Wine/WhiskyWine layer:
- #336, #335, #301, #267, #262, #252, #251, #445, #547, #546, #541, #548, #557, #647, etc.

### whisky-bug Issues (Fix in Whisky)
Issues that can be fixed in Whisky codebase:
- #293, #470, #359, #431, #1010, #1005, #1261

### d3dm-bug Issues (GPTK/D3DMetal)
- #336, #548, #982, #370

---

## Next Steps

1. **Start with bottle creation issues** - blocks all usage
2. **Reproduce on macOS 15.x** - get environment details
3. **Check WhiskyWine version** - if upstream has fixes
4. **Create test cases** for each fix
5. **Implement fixes incrementally**

## Files to Investigate

For bottle creation issues:
- `WhiskyKit/Sources/WhiskyKit/Whisky/Bottle.swift`
- `Whisky/Views/Bottle/BottleCreationView.swift`

For bottle display issues:
- `WhiskyKit/Sources/WhiskyKit/Whisky/BottleData.swift`
- `Whisky/Views/Bottle/BottleListEntry.swift`

For Steam compatibility:
- `WhiskyKit/Sources/WhiskyKit/WhiskyWine/WhiskyWineInstaller.swift`
- `Whisky/Utils/WhiskyCmd.swift`
