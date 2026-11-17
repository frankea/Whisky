# Launcher Troubleshooting Guide

**Feature:** Launcher Compatibility System (frankea/Whisky#41)
**Last Updated:** November 16, 2026

> **Note:** This documentation references issue numbers from both this fork (frankea/Whisky) and the original upstream project (whisky-app/whisky). Upstream references are kept for historical context. Please report new issues to [frankea/Whisky](https://github.com/frankea/Whisky/issues).

---

## Quick Start

If you're experiencing launcher issues:

1. Open your bottle → **Bottle Configuration**
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
   - Open bottle → Bottle Configuration → Launcher Compatibility
   - Toggle "Launcher Compatibility Mode" ON

2. **Check Configuration:**
   - Expand **Active Environment Overrides** in the same section
   - Verify `STEAM_DISABLE_CEF_SANDBOX=1` is listed

**About Locale:**
Earlier versions forced `LC_ALL=en_US.UTF-8` for Steam to avoid this crash. That crash did not reproduce in current testing (steamwebhelper started and the login page loaded under German and Japanese locales on both the older 3.1.1 engine and a 4.8 beta of the current engine), so the Steam preset now sets no locale. With Locale Override on **Auto**, Steam and the games it starts get your Mac's language and region as their Windows locale; pick another locale there to change that. Steam's own interface language is a Steam setting (Steam > Settings > Interface). If Steam's window fails to load under your locale, set Locale Override to English (en_US) and please report it.

**Related Upstream Issues:**
- whisky-app/whisky#946 (steamwebhelper crash)
- whisky-app/whisky#1224 (UI unusable)
- whisky-app/whisky#1241 (Earlier locale workaround)

---

### Issue: Steam Downloads Stall at 99%

**Symptoms:**
- Downloads appear to complete but never finish
- Progress bar stuck at 99%
- Requires Steam restart to continue
- Affects multiple games

**Solution:**

The fix is in Steam's own settings; Whisky has no setting that affects Steam downloads.

1. **Clear Download Cache:**
   - In Steam, Settings → Downloads → Clear Download Cache

2. **Change Download Region:**
   - In the same pane, pick a different download region close to you

3. **Restart Steam** and resume the download. Check it is not just paused or queued in Steam → Downloads.

**Why This Happens:**
Stalls usually come from a damaged download cache or a busy content server. Steam's content downloads do not go through Wine's WinHTTP or WinINet, and Wine reads no environment variable or registry value for network timeouts.

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

Current Whisky handles this by itself. On every launch of the Rockstar Games Launcher (from the Programs tab, or when Steam or a Rockstar game on Steam starts it), Whisky runs `Launcher.exe` on Wine's own Direct3D with the OpenGL renderer, the only setup its window draws on, and runs Social Club's `SocialClubHelper.exe` on DXVK. Direct3D 12 and the NVIDIA bridges are kept away from both.

1. **Update Whisky** to 3.10.2 or later.
2. **With Game Porting Toolkit imported** (Settings > Game Porting Toolkit): Whisky puts Wine's own `d3d11.dll` in the bottle's system folder and gives Steam and Social Club their own copies of DXVK. The **Wine Direct3D for Rockstar Games Launcher** setting in the bottle's Launcher Compatibility section controls this, and the line under it says whether it is active or why it is not applied. It is not applied while every program in the bottle runs on DXVK. In a bottle whose launcher is Rockstar's, **Use DXVK for Rockstar Games Launcher** switches the bottle to DXVK, so turn that off and set the bottle's Graphics Backend back to Recommended, or keep the launcher in a Steam bottle.
3. **In a Steam bottle:** starting the launcher no longer switches the bottle to DXVK. If an earlier version left a Steam bottle on DXVK after you started the Rockstar launcher in it, set its Graphics Backend back to Recommended.

**Why This Happens:**
The launcher draws its window with Direct2D on a Direct3D 10.1 device, which DXVK, DXMT and D3DMetal cannot create. Only Wine's own Direct3D on the OpenGL renderer draws it.

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
   - Open bottle → Bottle Configuration → Launcher Compatibility
   - Enable Launcher Compatibility Mode
   - Toggle "GPU Spoofing" ON
   - GPU Spoofing is on by default, and Whisky turns it on when it detects EA App. The GPU Vendor choice does not change the result.

2. **Verify GPU Spoofing:**
   - Check that the GPU Spoofing toggle is on

3. **Check Locale:**
   - Leave Locale Override on **Auto** (EA App gets US English by default) or set it to **English**
   - Another locale can break EA App's Chromium UI

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

1. **Check the graphics backend:**
   - Bottle Configuration > Graphics: keep Graphics Backend on **Recommended**, which runs Epic Games Launcher on DXVK while games keep the bottle's backend. A bottle or program set to D3DMetal or DXMT leaves the launcher's Chromium window blank.

2. **Enable Launcher Compatibility:**
   - Bottle Configuration > Launcher Compatibility > Launcher Compatibility Mode on
   - Locale Override: Auto or English

3. **Verify CEF Sandbox:**
   - Expand **Active Environment Overrides** in the Launcher Compatibility section
   - Check `CEF_DISABLE_SANDBOX=1` is listed under Platform Fixes

**Why This Happens:**
Epic's Chromium Embedded Framework conflicts with Wine's threading model. Disabling the CEF sandbox resolves the conflicts.

---

### Issue: Ubisoft Connect Can't Update or Launch Games

**Symptoms:**
- Ubisoft Connect launches but games won't start
- Update progress bar doesn't move
- "Failed to initialize" errors
- Anno 1800 or other games crash immediately

**Solution:**

1. **Use DXVK with DXVK Async:**
   - With Launcher Compatibility Mode on, Whisky sets this up when it detects Ubisoft Connect
   - To check: Bottle Configuration > Graphics, set Graphics Backend to DXVK, switch to Advanced, and make sure **DXVK Async** under DXVK Configuration is on

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
   - Full compatibility mode, with Locale Override on Auto or English

**Why This Happens:**
Battle.net's web-based authentication requires proper Chromium rendering.

---

### Issue: Paradox Launcher Shows "Recursive Resource Lookup" Error

**Symptoms:**
- Installation fails with cryptic error
- "Recursive resource lookup" message
- Launcher doesn't complete initialization

**Solution:**

1. **Enable Launcher Compatibility:**
   - Detect as Paradox Launcher (Auto or Manual)

Whisky has no Paradox-specific environment fix. The `WINE_DISABLE_FAST_PATH`
workaround earlier versions set is read by no shipped runtime, so it was removed.

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

1. **No setting is needed:** Whisky applies its macOS 15.4 fixes (`WINEFSYNC=0`, `STEAM_RUNTIME=0`, and `WINEESYNC=1` when no sync mode is set) on every launch.

2. **Verify the fixes are applied:**
   - Bottle Configuration > Launcher Compatibility (with Launcher Compatibility Mode on, which shows the list) > Active Environment Overrides > Platform Fixes
   - Check `WINEFSYNC=0`

**Why This Happens:**
Apple changed threading and mach port behavior in macOS 15.4. Whisky applies Wine environment fixes for these changes.

**Related Upstream Issues:**
- whisky-app/whisky#1372 (macOS 15.4.1 breaks Steam)
- whisky-app/whisky#1310 (Graphics corruption)
- whisky-app/whisky#1307 (Sequoia compatibility)

---

## Diagnostic Report Usage

### Checking What Whisky Applies

1. Open the bottle, then **Bottle Configuration** > **Launcher Compatibility**, with **Launcher Compatibility Mode** on.
2. Expand **Active Environment Overrides**. It lists each environment variable the detected launcher's preset sets (for example `STEAM_DISABLE_CEF_SANDBOX=1` for Steam) and the **Platform Fixes** Whisky applies on your macOS version (for example `WINEFSYNC=0` on macOS 15.4 and later), each with the reason.
3. Click **View Diagnostics** to open the latest crash diagnosis for the bottle, or the Stability Diagnostics Report when no crash has been diagnosed. The Stability Diagnostics Report window has **Copy to Clipboard** and **Export to File**.

---

## Configuration Warnings Explained

### ⚠️ "GPU spoofing helps with game compatibility checks" (Steam)
**Solution:** Turn GPU Spoofing back on in Launcher Compatibility.

### ❌ "GPU spoofing REQUIRED for EA App"
**Impact:** Black screen, "GPU not supported"  
**Solution:** Turn GPU Spoofing on.

### ⚠️ "en_US locale recommended for EA App launcher UI" / "...for Epic Games launcher" / "...for Battle.net"
**Solution:** Set Locale Override to Auto or English.

### ❌ "DXVK REQUIRED for Rockstar Launcher"
Shown when neither the backend nor Use DXVK for Rockstar Games Launcher gives the launcher DXVK. Since 3.10.2 Whisky runs the launcher's own window on Wine's Direct3D by itself; see the Rockstar section above.

---

## Advanced Troubleshooting

### Reset Launcher Configuration

If launchers become misconfigured:

1. In Launcher Compatibility, set **Detection Mode** to **Manual**, pick **None** as Launcher Type, then set it back to **Automatic** and start the launcher again so Whisky detects it fresh.
2. Or use **Start Guided Troubleshooting** (Bottle Configuration > Diagnostics), whose launcher steps can reapply the launcher's fixes.
3. Deleting the bottle's `Metadata.plist` resets every bottle setting (name, pins, graphics backend and more), not only launcher settings. Back it up first if you try it.

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
   - Terminal: `"$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wine64" --version`
   - The default engine (Wine Libraries 4.8.3) prints `wine-11.19`

2. **Verify WhiskyWine:**
   - Check `~/Library/Application Support/com.franke.Whisky/Libraries/`
   - It should contain `Wine/` (with `bin/`, `lib/`, `share/`), `DXVK/`, `DXMT/` and `WhiskyWineVersion.plist`

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

**Recommended:**
- ✅ Graphics Backend: Recommended when Game Porting Toolkit is imported (Whisky runs Steam and its web helper on DXVK by itself, and games keep D3DMetal). Without Game Porting Toolkit, Whisky switches a Steam bottle to DXVK itself
- ✅ Locale: Auto (your Mac's language and region; the Steam preset sets no locale)

**Critical Settings:**
- `STEAM_DISABLE_CEF_SANDBOX=1` (Wine compatibility)

---

### Rockstar Games Launcher
**Must Have:**
- ✅ Whisky 3.10.2 or later (it runs `Launcher.exe` on Wine's own Direct3D with the OpenGL renderer, and `SocialClubHelper.exe` on DXVK, on every launch)
- ✅ Launcher Compatibility Mode

**Recommended:**
- ✅ Locale: Auto (the Rockstar preset already uses US English)
- ✅ With Game Porting Toolkit imported: **Wine Direct3D for Rockstar Games Launcher** on (the default). In a bottle whose launcher is Rockstar's, turn **Use DXVK for Rockstar Games Launcher** off and keep Graphics Backend on Recommended

**Critical Settings:**
- In a Steam bottle with Game Porting Toolkit imported, keep Graphics Backend on Recommended so Steam games keep D3DMetal

---

### EA App / Origin
**Must Have:**
- ✅ GPU Spoofing (prevents black screen)
- ✅ Launcher Compatibility Mode

**Recommended:**
- ✅ Locale: Auto or English

**Critical Settings:**
- GPU Spoofing enabled

---

### Epic Games Store
**Must Have:**
- ✅ Launcher Compatibility Mode
- ✅ Locale: Auto or English

**Recommended:**
- ✅ GPU Spoofing

**Critical Settings:**
- `CEF_DISABLE_SANDBOX=1` (UI rendering)

---

### Ubisoft Connect
**Must Have:**
- ✅ Launcher Compatibility Mode

**Recommended:**
- ✅ DXVK + DXVK Async

**Critical Settings:**
- `DXVK_ASYNC=1` (game compatibility)

---

### Battle.net
**Must Have:**
- ✅ Launcher Compatibility Mode
- ✅ Locale: Auto or English

**Recommended:**
- ✅ DXVK

**Critical Settings:**
- `CEF_DISABLE_SANDBOX=1` (authentication)

---

### Paradox Launcher
**Must Have:**
- ✅ Launcher Compatibility Mode

**Critical Settings:**
- None beyond Launcher Compatibility Mode

---

### RSI Launcher (Star Citizen)
**Must Have:**
- ✅ Graphics backend: Recommended or DXVK (the launcher's window stays blank white on D3DMetal and DXMT)

**Critical Settings:**
- None bottle-wide. On Recommended, Whisky runs `RSI Launcher.exe` (and the Chromium processes it starts as the same executable) on DXVK
- Star Citizen launched from Whisky keeps the bottle's backend. Started from the launcher, it keeps D3DMetal when Game Porting Toolkit is imported; without it, the game runs on DXVK, because the launcher's DXVK files replace DXMT's in the bottle until a game is next launched from Whisky

---

### Chromium apps (3DMark and other front ends)
Some programs that are not launchers draw their own window with Chromium (CEF or Electron), and that window stays black on D3DMetal and DXMT, while the benchmarks or games they start run fine there.

**Must Have:**
- ✅ Graphics backend: Recommended (the default). Whisky runs a known front end on DXVK by itself

**How it works:**
- Known front ends are listed by executable name: today `3DMark.exe` (3DMark, Steam App 223850). On Recommended, the front end gets DXVK in its own registry entry (`AppDefaults\3DMark.exe`), and its benchmarks keep the bottle's backend, D3DMetal when Game Porting Toolkit is imported
- This applies when 3DMark is launched from the Programs tab, from the Whisky Library (`-applaunch 223850`), and when Steam's own Play button or a shortcut starts it: any launch in a bottle with 3DMark installed writes its entry ahead of time
- The program's settings page says why Recommended picked DXVK. An explicit backend on the program, or on the bottle, is never changed. Setting the program itself to Recommended steers it the same way in a bottle set to D3DMetal or DXMT
- A DXVK override set on `3DMark.exe` stays on the front end and no longer becomes the backend of 3DMark's benchmarks on Steam launches
- In a bottle without Game Porting Toolkit (DXMT), DXVK and DXMT share system files, so what the front end starts also runs on DXVK until a DXMT program is next started from Whisky

**3DMark's window draws but stays on its background:**
- That is 3DMark's SystemInfo hardware scan, which does not finish under Wine. It is not a graphics problem: the window is already drawing on DXVK
- Turn the scan off in 3DMark's settings file, `%LOCALAPPDATA%\UL\3DMark\app-settings.json` inside the bottle (`drive_c/users/crossover/AppData/Local/UL/3DMark/app-settings.json`): set `SCAN_SYSTEM_INFO` and `HARDWARE_MONITORING` to `false` while 3DMark is closed, then start it again. The full interface loads, though it can be slow to respond. The benchmarks themselves are separate programs and are not affected

**Electron and NW.js apps:**
- An Electron app (its folder holds `resources/app.asar` or `resources/app/package.json`, `icudtl.dat`, and a V8 snapshot, and the executable imports `ffmpeg.dll`) or an NW.js app (`nw.dll` and `icudtl.dat` beside it, and the executable imports `nw.dll` or `nw_elf.dll`) runs on DXVK under Recommended, the same way as a known front end. Its settings page names the file that identified it
- An executable that imports Direct3D, DXGI, Vulkan or OpenGL itself is never matched, nor is anything under `drive_c/windows` or in a folder with more than 2,000 files. The uninstaller and helper programs beside an Electron app keep the bottle's backend
- A Squirrel install (`Update.exe` beside the app, the app itself in an `app-x.y.z` folder) is matched through the app the stub starts
- The entry is written when Whisky launches the app, from the Programs tab or with Play in the Whisky Library, and stays in the registry for later starts from elsewhere. Wine keys it on the file name alone, so a generic name such as `Game.exe` also reaches another `Game.exe` started outside Whisky, until Whisky launches that one and writes its own entry

**Other Chromium apps:**
- If a program's settings page finds `libcef.dll` beside it, and the program loads `libcef.dll` itself without importing a graphics API, it offers **Use DXVK** for that program only. Whisky never switches such a program by itself: games ship CEF too, for overlays and in-game browsers, and DXVK has no Direct3D 12 on macOS
- If a program's window stays black and it is a Chromium app, set its graphics backend to DXVK on its settings page, and please report it so it can be added to the list

---

## Getting Help

### Before Reporting Issues

1. **Collect diagnostics:**
   - After a crash: Bottle Configuration > Diagnostics > **Export Diagnostic Report…** (or **View Latest Diagnosis**)
   - Otherwise: Bottle Configuration > Stability > **Generate Stability Diagnostics**, then **Export to File**
   - **Start Guided Troubleshooting** in the Diagnostics section, or Help > Troubleshoot…, walks through checks for common problems, launcher problems included

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

Whisky disables the Chromium (CEF) sandbox for every program it runs, because the sandbox cannot work under Wine. Launcher Compatibility Mode does not change this.

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

2. **Enable Shader Cache:**
   - Bottle Configuration → Performance
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
   - Screenshot the Bottle Configuration page
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
**A:** Launcher fixes apply to the whole bottle. Individual programs can override the graphics backend, DXVK and Metal options, locale, DLL overrides, environment variables and more on their own settings page in the Programs tab.

### Q: Why do some launchers use an English locale?
**A:** The Rockstar, EA App, Epic Games, and Battle.net presets set en_US.UTF-8 to avoid locale problems reported for those launchers. Steam's preset sets no locale, so with Locale Override on Auto, Steam and the games it starts get your Mac's language and region. Launcher bottles that older versions of Whisky set to English are put back on Auto once. Locale Override can pick a specific locale for any launcher.

---

## Version Compatibility

| macOS Version | Compatibility Level | Notes |
|---------------|-------------------|--------------|
| 15.0-15.2 | ✅ Full | None known |
| 15.3 | ✅ Full | Metal validation turned off (handled automatically) |
| 15.4 and later, including macOS 26 | ✅ Full | Sync mode and Steam Runtime fixes (handled automatically) |

Whisky requires macOS 15.0 or later.

---

## Additional Resources

- **Issue Tracking:** frankea/Whisky#41
- **Pull Request:** #53
- **Security Notes:** [LauncherSecurityNotes.md](LauncherSecurityNotes.md)
- **Implementation Details:** [LauncherCompatibilityImplementation.md](LauncherCompatibilityImplementation.md)

---

**Last Updated:** November 16, 2026  
**Feature Version:** 1.0.0  
**Covers:** Steam, Rockstar, EA App, Epic, Ubisoft, Battle.net, Paradox, RSI Launcher, Chromium apps
