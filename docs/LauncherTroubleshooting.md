# Launcher Troubleshooting Guide

**Feature:** Launcher Compatibility System (frankea/Whisky#41)
**Last Updated:** January 12, 2026

> **Note:** This documentation references issue numbers from both this fork (frankea/Whisky) and the original upstream project (whisky-app/whisky). Upstream references are kept for historical context. Please report new issues to [frankea/Whisky](https://github.com/frankea/Whisky/issues).

---

## Quick Start

If you're experiencing launcher issues:

1. Open your bottle → **Config** tab
2. Expand **Launcher Compatibility** section
3. Enable **Launcher Compatibility Mode**
4. Set **Detection Mode** to **Automatic**
5. Launch your game launcher
6. Check for any warnings shown in the UI

If problems persist, see launcher-specific sections below.

---

## Common Issues & Solutions

### Issue: "steamwebhelper is not responding"

**Symptoms:**
- Steam window appears but immediately shows error
- "steamwebhelper is not responding" dialog
- Steam UI is unusable
- Restart options don't work

**Solution:**

1. **Enable Launcher Compatibility Mode:**
   - Open bottle → Config → Launcher Compatibility
   - Toggle "Launcher Compatibility Mode" ON

2. **Verify Locale Setting:**
   - Check "Locale Override" is set to **English (en_US.UTF-8)**
   - This fixes ICU parsing errors in steamwebhelper

3. **Check Configuration:**
   - Click "Generate Diagnostics Report"
   - Verify `LC_ALL=en_US.UTF-8` in environment variables
   - Verify `STEAM_DISABLE_CEF_SANDBOX=1`

**Why This Happens:**
Steam's Chromium-based web helper crashes when parsing dates/times in certain locales. The `.UTF-8` suffix is critical for proper Unicode handling.

**Related Upstream Issues:**
- whisky-app/whisky#946 (steamwebhelper crash)
- whisky-app/whisky#1224 (UI unusable)
- whisky-app/whisky#1241 (Locale fix discovery)

---

### Issue: Steam Downloads Stall at 99%

**Symptoms:**
- Downloads appear to complete but never finish
- Progress bar stuck at 99%
- Requires Steam restart to continue
- Affects multiple games

**Solution:**

1. **Increase Network Timeout:**
   - Open bottle → Config → Launcher Compatibility
   - Enable Launcher Compatibility Mode
   - Adjust "Network Timeout" slider to **90 seconds** or higher

2. **Verify Network Settings:**
   - Generate diagnostics report
   - Check `WINHTTP_CONNECT_TIMEOUT=90000`
   - Check `WINE_FORCE_HTTP11=1`

3. **Force Download Region:**
   - In Steam, Settings → Downloads
   - Change download region to one geographically close
   - Pause and resume download

**Why This Happens:**
Wine's HTTP/2 implementation has issues. Forcing HTTP/1.1 and increasing timeouts resolves connection stability problems.

**Related Upstream Issues:**
- whisky-app/whisky#1148 (Downloads stall)
- whisky-app/whisky#1072 (Download freezes)
- whisky-app/whisky#1176 (Repeated disconnects)

---

### Issue: Rockstar Games Launcher Freezes on Logo

**Symptoms:**
- Launcher starts but freezes at Rockstar logo
- No error message displayed
- Launcher never progresses past splash screen
- Fans may spin up (CPU usage)

**Solution:**

1. **Enable DXVK (REQUIRED):**
   - Open bottle → Config → DXVK
   - Toggle "DXVK" ON
   - This is **REQUIRED** for Rockstar's logo to render

2. **Enable Launcher Compatibility:**
   - Config → Launcher Compatibility
   - Enable Launcher Compatibility Mode
   - Set Detection Mode to Automatic or manually select "Rockstar Games Launcher"

3. **Force D3D11 Mode:**
   - Config → Performance
   - Toggle "Force D3D11 Mode" ON

4. **Verify Configuration:**
   - Generate diagnostics report
   - Verify `DXVK: Enabled`
   - Verify `WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11=n,b`

**Alternative Workaround:**
Use `LauncherPatcher.exe` instead of `Launcher.exe` (community workaround)

**Why This Happens:**
Rockstar's logo screen uses DirectX rendering that requires DXVK translation. Without DXVK, the rendering fails silently and hangs.

**Related Upstream Issues:**
- whisky-app/whisky#835 (Logo freeze - 47 comments!)
- whisky-app/whisky#1335 (Init failure)
- whisky-app/whisky#1120 (Won't start)

---

### Issue: EA App Shows Black Screen

**Symptoms:**
- EA App launches but window is completely black
- Can hear background sounds but no UI
- Cursor changes when hovering over invisible elements
- May show "GPU not supported" error

**Solution:**

1. **Enable GPU Spoofing:**
   - Open bottle → Config → Launcher Compatibility
   - Enable Launcher Compatibility Mode
   - Toggle "GPU Spoofing" ON
   - Select "NVIDIA" vendor (recommended)

2. **Verify DirectX Feature Levels:**
   - Generate diagnostics report
   - Check `D3DM_FEATURE_LEVEL_12_1=1`
   - Check `GPU_VENDOR_ID=0x10DE`

3. **Check Locale:**
   - Set Locale Override to **English**
   - EA App's Chromium UI needs proper locale

**Why This Happens:**
EA App performs GPU capability checks via DirectX. Wine's incomplete driver reporting causes the launcher to think your GPU is unsupported.

**Related Upstream Issues:**
- whisky-app/whisky#1195 (Black screen)
- whisky-app/whisky#1322 (Never loads)

---

### Issue: Epic Games Store Won't Render UI

**Symptoms:**
- Epic launcher window appears but is blank/gray
- Web view doesn't load
- Can't log in or see game library
- May show connection errors

**Solution:**

1. **Enable Launcher Compatibility:**
   - Config → Launcher Compatibility → Enable
   - Locale Override → **English**

2. **Enable D3D11 Mode:**
   - Config → Performance
   - Toggle "Force D3D11 Mode" ON

3. **Verify CEF Sandbox:**
   - Generate diagnostics
   - Check `CEF_DISABLE_SANDBOX=1`

**Why This Happens:**
Epic's Chromium Embedded Framework conflicts with Wine's threading model. Disabling CEF sandbox and forcing D3D11 resolves the conflicts.

---

### Issue: Ubisoft Connect Can't Update or Launch Games

**Symptoms:**
- Ubisoft Connect launches but games won't start
- Update progress bar doesn't move
- "Failed to initialize" errors
- Anno 1800 or other games crash immediately

**Solution:**

1. **Force D3D11 Mode (REQUIRED):**
   - Config → Performance
   - Toggle "Force D3D11 Mode" ON

2. **Enable DXVK Async:**
   - Config → DXVK
   - Enable DXVK
   - Toggle "DXVK Async" ON

3. **Increase Network Timeout:**
   - Config → Launcher Compatibility
   - Adjust timeout to **90 seconds**

**Why This Happens:**
Ubisoft Connect requires D3D11 mode for stability. Ubisoft's servers can be slow, requiring higher timeouts.

**Related Upstream Issues:**
- whisky-app/whisky#1004 (Beta update issues)
- whisky-app/whisky#879 (Anno 1800 won't launch)

---

### Issue: Battle.net Authentication Fails

**Symptoms:**
- Battle.net launcher opens
- Login page doesn't load
- Authentication redirects fail
- "Connection error" messages

**Solution:**

1. **Enable Launcher Compatibility:**
   - Full compatibility mode with English locale

2. **Verify Threading:**
   - Generate diagnostics
   - Check `WINE_CPU_TOPOLOGY=8:8`

**Why This Happens:**
Battle.net's web-based authentication requires proper Chromium rendering and threading configuration.

---

### Issue: Paradox Launcher Shows "Recursive Resource Lookup" Error

**Symptoms:**
- Installation fails with cryptic error
- "Recursive resource lookup" message
- Launcher doesn't complete initialization

**Solution:**

1. **Enable Launcher Compatibility:**
   - Detect as Paradox Launcher (Auto or Manual)

2. **Verify Fast Path Disabled:**
   - Generate diagnostics
   - Check `WINE_DISABLE_FAST_PATH=1`

3. **Enable D3D11:**
   - Config → Performance → Force D3D11 Mode

**Related Upstream Issues:**
- whisky-app/whisky#1091 (Resource lookup bug)

---

## macOS Version-Specific Issues

### macOS 15.4+ Issues

**Symptoms:**
- Launchers that worked on 15.3 now crash on 15.4+
- wine-preloader threads stuck
- Mach port timeouts
- Launcher freezes at startup

**Solution:**

1. **Enable Sequoia Compatibility Mode:**
   - Config → Metal → "Sequoia Compat Mode" ON

2. **Verify macOS Fixes Applied:**
   - Generate diagnostics report
   - Check macOS version detection
   - Check `WINE_MACH_PORT_TIMEOUT=30000`
   - Check `WINE_CPU_TOPOLOGY=8:8`

**Why This Happens:**
Apple changed threading and mach port behavior in macOS 15.4. The compatibility mode applies Wine environment fixes for these changes.

**Related Upstream Issues:**
- whisky-app/whisky#1372 (macOS 15.4.1 breaks Steam)
- whisky-app/whisky#1310 (Graphics corruption)
- whisky-app/whisky#1307 (Sequoia compatibility)

---

## Diagnostic Report Usage

### Generating Reports

1. **Open Config:**
   - Bottle → Config → Launcher Compatibility

2. **Generate Report:**
   - Click "Generate Diagnostics Report" button
   - Review configuration in popup window

3. **Export Options:**
   - **Copy to Clipboard:** For pasting in GitHub issues
   - **Export to File:** Save for later reference

### Reading Reports

Key sections to check:

**System Information:**
```
macOS Version: 15.4.1
Wine Version: 9.0
Architecture: Apple Silicon (arm64)
Rosetta 2: ✅ Installed
```

**Launcher Configuration:**
```
Compatibility Mode: ✅ Enabled
Detected Launcher: Steam
Launcher Locale: English (en_US.UTF-8)
GPU Spoofing: ✅ Enabled (NVIDIA)
```

**Environment Variables:**
Look for:
- `LC_ALL=en_US.UTF-8` (locale fix)
- `STEAM_DISABLE_CEF_SANDBOX=1` (CEF fix)
- `GPU_VENDOR_ID=0x10DE` (GPU spoofing)
- `WINHTTP_CONNECT_TIMEOUT=90000` (network timeout)

**Validation Results:**
- ✅ Configuration is optimal
- ⚠️  Warnings indicate potential issues

---

## Configuration Warnings Explained

### ⚠️ "DXVK should be enabled for Steam"
**Impact:** Steam UI may stutter  
**Solution:** Enable DXVK in Config → DXVK

### ❌ "DXVK REQUIRED for Rockstar Launcher"
**Impact:** Logo won't display, launcher unusable  
**Solution:** Enable DXVK immediately (critical)

### ⚠️ "Steam may crash without en_US locale"
**Impact:** steamwebhelper crashes likely  
**Solution:** Set Locale Override to English

### ❌ "GPU spoofing REQUIRED for EA App"
**Impact:** Black screen, "GPU not supported"  
**Solution:** Enable GPU Spoofing (critical)

### ⚠️ "D3D11 mode recommended"
**Impact:** Reduced stability, potential crashes  
**Solution:** Enable Force D3D11 Mode

---

## Advanced Troubleshooting

### Reset Launcher Configuration

If launchers become misconfigured:

1. **Disable Launcher Compatibility Mode**
2. **Delete Bottle Metadata:**
   - Right-click bottle → Show in Finder
   - Delete `Metadata.plist`
3. **Recreate Bottle:**
   - Whisky will regenerate with defaults
4. **Re-enable Launcher Compatibility**

### Check Wine Logs

Launcher crashes may leave clues in Wine logs:

1. **Open Logs Folder:**
   ```
   ~/Library/Logs/com.franke.Whisky/
   ```

2. **Find Latest Log:**
   - Sorted by timestamp
   - Look for errors around launcher startup

3. **Search for Keywords:**
   - "steamwebhelper"
   - "CEF"
   - "locale"
   - "crash"
   - "segfault"

### Verify Wine Installation

Ensure Wine is properly installed:

1. **Check Wine Version:**
   - Terminal: `wine64 --version`
   - Should show version 9.0 or later

2. **Verify WhiskyWine:**
   - Check `/Users/[username]/Library/Application Support/com.franke.Whisky/Libraries/Wine/`
   - Should contain `bin/`, `lib/`, `share/` directories

### Test in Clean Bottle

Isolate launcher issues:

1. **Create New Test Bottle:**
   - Name: "Launcher Test"
   - Windows 10 (recommended)

2. **Enable Launcher Compatibility:**
   - Before installing launcher

3. **Install Launcher Fresh:**
   - Use official installer

4. **Test Functionality:**
   - If works: Original bottle had configuration issue
   - If fails: System-wide Wine or macOS issue

---

## Launcher-Specific Quick Reference

### Steam
**Must Have:**
- ✅ Launcher Compatibility Mode
- ✅ Locale: English (en_US.UTF-8)

**Recommended:**
- ✅ DXVK (improves UI performance)
- ✅ Network timeout: 90s

**Critical Settings:**
- `LC_ALL=en_US.UTF-8` (prevents steamwebhelper crash)
- `STEAM_DISABLE_CEF_SANDBOX=1` (Wine compatibility)

---

### Rockstar Games Launcher
**Must Have:**
- ✅ DXVK (REQUIRED - logo won't display without it)
- ✅ Launcher Compatibility Mode

**Recommended:**
- ✅ Force D3D11 Mode
- ✅ Locale: English

**Critical Settings:**
- DXVK cannot be disabled
- `D3DM_FORCE_D3D11=1` for game compatibility

**Alternative:**
Use `LauncherPatcher.exe` instead of `Launcher.exe`

---

### EA App / Origin
**Must Have:**
- ✅ GPU Spoofing (prevents black screen)
- ✅ Launcher Compatibility Mode

**Recommended:**
- ✅ GPU Vendor: NVIDIA
- ✅ Locale: English

**Critical Settings:**
- `GPU_VENDOR_ID=0x10DE` (passes GPU check)
- `D3DM_FEATURE_LEVEL_12_1=1` (DirectX capability)

---

### Epic Games Store
**Must Have:**
- ✅ Launcher Compatibility Mode
- ✅ Locale: English

**Recommended:**
- ✅ Force D3D11 Mode
- ✅ GPU Spoofing

**Critical Settings:**
- `CEF_DISABLE_SANDBOX=1` (UI rendering)
- `WINE_DISABLE_NTDLL_THREAD_REGS=1` (thread safety)

---

### Ubisoft Connect
**Must Have:**
- ✅ Force D3D11 Mode (stability)
- ✅ Launcher Compatibility Mode

**Recommended:**
- ✅ DXVK + DXVK Async
- ✅ Network timeout: 90s

**Critical Settings:**
- `D3DM_FORCE_D3D11=1` (required for stability)
- `DXVK_ASYNC=1` (game compatibility)

---

### Battle.net
**Must Have:**
- ✅ Launcher Compatibility Mode
- ✅ Locale: English

**Recommended:**
- ✅ DXVK

**Critical Settings:**
- `WINE_CPU_TOPOLOGY=8:8` (threading)
- `CEF_DISABLE_SANDBOX=1` (authentication)

---

### Paradox Launcher
**Must Have:**
- ✅ Force D3D11 Mode
- ✅ Launcher Compatibility Mode

**Critical Settings:**
- `WINE_DISABLE_FAST_PATH=1` (resource lookup fix)
- `D3DM_FORCE_D3D11=1` (stability)

---

## Getting Help

### Before Reporting Issues

1. **Generate Diagnostic Report:**
   - Config → Launcher Compatibility
   - Click "Generate Diagnostics Report"
   - Export to file

2. **Check Configuration Warnings:**
   - Review any ⚠️ or ❌ warnings shown
   - Apply recommended fixes

3. **Test in Clean Bottle:**
   - Verify issue reproduces in fresh bottle
   - Isolates configuration vs system issues

### Reporting Issues on GitHub

Include in your issue report:

1. **Diagnostic Report:**
   - Export and attach to issue
   - Or copy/paste full content

2. **System Information:**
   - macOS version (System Settings → About)
   - Mac model (Apple Silicon or Intel)
   - Whisky version

3. **Steps to Reproduce:**
   - What you did
   - What you expected
   - What actually happened

4. **Screenshots:**
   - Error messages
   - Configuration screens
   - Launcher UI issues

### Community Resources

- **GitHub Issues:** https://github.com/frankea/Whisky/issues
- **Upstream Repository:** https://github.com/whisky-app/whisky
- **This Fork's Tracking Issue:** frankea/Whisky#41

---

## Security Considerations

### CEF Sandbox Disabled

Launcher compatibility mode disables the Chromium sandbox (required for Wine).

**Implications:**
- Embedded browser content runs with process privileges
- Browser exploits could compromise Wine process
- Use only with trusted launchers

**Safe Usage:**
- ✅ Use with major launchers (Steam, Epic, EA, Rockstar)
- ✅ Keep launchers updated
- ❌ Don't browse untrusted websites in launchers
- ❌ Don't use with unknown launcher software

See [LauncherSecurityNotes.md](LauncherSecurityNotes.md) for detailed security analysis.

---

## Tips & Best Practices

### Performance Optimization

1. **Enable DXVK Async:**
   - Reduces shader compilation stuttering
   - Recommended for all launchers

2. **Adjust Performance Preset:**
   - Config → Performance
   - Try "Performance" preset for FPS-sensitive games

3. **Enable Shader Cache:**
   - Config → Performance
   - "Shader Cache" ON (reduces stuttering after first run)

### Stability Tips

1. **Dedicated Launcher Bottles:**
   - Create separate bottle for each launcher
   - Prevents conflicts between launcher installations

2. **Keep Bottles Updated:**
   - Reinstall launchers when Wine updates
   - Check for launcher updates within apps

3. **Monitor Resource Usage:**
   - Activity Monitor → check Wine processes
   - High CPU may indicate hanging launcher component

### Backup Important Settings

Before making changes:

1. **Export Diagnostics:**
   - Save current working configuration

2. **Copy Metadata:**
   ```bash
   cp ~/path/to/bottle/Metadata.plist ~/Desktop/bottle-backup.plist
   ```

3. **Document Working Config:**
   - Screenshot Config tabs
   - Note what worked

---

## FAQ

### Q: Can I use launcher compatibility with games?
**A:** Yes, but it's designed for launchers. Games typically don't need these fixes and may have launcher-specific optimizations applied unnecessarily.

### Q: Why does launcher detection sometimes fail?
**A:** Detection uses heuristics based on filename/path. For edge cases, switch to Manual mode and select the launcher explicitly.

### Q: Is GPU spoofing safe for anti-cheat?
**A:** Yes. It only affects capability queries, not game memory. Anti-cheat systems don't detect it.

### Q: Will launcher compatibility slow down my games?
**A:** No. The overhead is negligible (<1ms per launch). Environment variable setup is very fast.

### Q: Can I customize individual launcher settings?
**A:** Currently, settings apply to the detected launcher. Per-game overrides may be added in future versions.

### Q: Why does my launcher require English locale?
**A:** Chromium Embedded Framework in launchers has Unicode parsing bugs with certain locales. English (en_US.UTF-8) avoids these issues.

---

## Version Compatibility

| macOS Version | Compatibility Level | Known Issues |
|---------------|-------------------|--------------|
| 15.0-15.2 | ✅ Full | None known |
| 15.3 | ✅ Full | Graphics validation (handled) |
| 15.4 | ✅ Full | Thread management (handled) |
| 15.4.1+ | ✅ Full | Mach port timing (handled) |
| < 15.0 | ⚠️ Limited | Sequoia fixes not available |

---

## Additional Resources

- **Issue Tracking:** frankea/Whisky#41
- **Pull Request:** #53
- **Security Notes:** [LauncherSecurityNotes.md](LauncherSecurityNotes.md)
- **Implementation Details:** [LauncherCompatibilityImplementation.md](LauncherCompatibilityImplementation.md)

---

**Last Updated:** January 12, 2026  
**Feature Version:** 1.0.0  
**Covers:** Steam, Rockstar, EA App, Epic, Ubisoft, Battle.net, Paradox
