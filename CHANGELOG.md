# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Enabling DXVK now removes a stale native dxgi.dll that a previous DXMT
  launch left in the bottle's system directories. The leftover paired
  DXVK's d3d11 with DXMT's dxgi, which cannot create window swapchains,
  leaving Chromium-based launchers such as Steam running with no window
  after a switch from DXMT to DXVK (#163).

## [3.7.0] - 2026-08-29 (App)

### Added
- Failed dependency installs now record the last few KB of winetricks output
  in dependency-history.plist alongside the exit code, so the reason for a
  failure (such as a vc_redist checksum mismatch) is on disk next to the
  attempt instead of lost with the process (#233).
- Ways into a game from outside the window. A whisky:// URL scheme launches a
  Steam game (whisky://launch?steam=<appid>) or a pinned program
  (whisky://launch?pin=<name>), optionally scoped to a bottle. Only games
  installed in one of your bottles and pins that exist resolve; anything
  else is refused before Steam is involved. A URL arrival names what it is
  about to launch and asks first, with a per-target "always allow" so the
  dialog does not nag on repeat. The Dock menu lists your pins and launches
  them without confirming, since you are already in the app, and dropping an
  executable anywhere on the window opens the same run-this-file sheet as
  opening it from Finder (#226, part of #172).
- Discord integration, off by default and per bottle: Whisky can publish the
  running program as your Discord presence, and games that speak Discord's
  IPC themselves are bridged from inside the bottle to the host client, so
  their own rich presence works (#203, fixes #201).
- Metal 4 command encoding can be turned off for a single program. The
  bottle-wide default stays on; a toggle in the program's settings masks it
  for D3D12 titles whose renderer wedges on the Metal 4 submission
  path (#230).
- Whisky now opens onto a library of your games and pinned programs instead
  of a sidebar of bottles. Steam games show their own store artwork from the
  client's cache, other programs get a backdrop derived from their icon, and
  cards show running state and last-played times. Bottles are one click away
  under their own heading (#206).
- D3DMetal now uses its Metal 4 command encoding backend by default, with a
  toggle beside MetalFX for titles it does not suit. The engine ignores the
  setting on macOS versions without Metal 4 and on Direct3D 11 titles, so it
  is inert where it cannot help (#205).
- MetalFX upscaling via the DLSS bridge, on by default for D3DMetal bottles.
  The bridge DLL Apple ships was never deployed, so the MetalFX switch had
  nothing to act on (#204). Apple's NVAPI is deployed alongside it so games
  using NVIDIA Streamline actually offer the DLSS option, with launcher
  helper processes exempted per executable so their embedded browsers stay
  up (#222, fixes #198).
- British English localization, generated from the English strings and kept
  complete by a CI check, so systems set to English (UK) see proper spellings
  instead of raw localization keys (#208).

### Changed
- DLSS frame generation is now its own bottle setting, off by default, instead
  of riding on the MetalFX toggle. Both reach MetalFX through the same bridge,
  but frame generation ended the login session on the machine it was measured
  on: every command buffer carrying MetalFX work failed and WindowServer wedged
  in the GPU driver until its watchdog killed it. Upscaling is unaffected and
  stays on. Some NVIDIA Streamline titles refuse to start with frame generation
  off, Deep Rock Galactic among them, so those need the toggle flipped for that
  bottle (#231).
- The per-bottle Steam library screen has been removed; the library on the
  landing screen does that job for every bottle at once (#206).
- The bottle action bar now emphasizes Run as its primary control, with
  Liquid Glass styling on macOS 26 and bordered buttons on earlier
  releases (#210).
- The Sequoia Compatibility Mode toggle has been removed. The fixes it
  claimed to control ship unconditionally, so the switch changed nothing in
  either position (#216).

### Fixed
- Installing the Visual C++ Runtime no longer stalls on an invisible install
  wizard. winetricks was run without -q, so the vc_redist installer showed
  its setup dialog inside the prefix and waited for a click nothing in the
  Dependencies panel prompts for -- the process never exited, the
  winetricks.log entry was never written, and the panel stayed on "Not
  Installed" even after a successful install. The vcrun verbs now run
  unattended (#233).
- Five labels showed their raw localization key instead of text: the
  "currently using" line on the Recommended graphics card and the helper
  under it, the detected display size next to Virtual Desktop, and the exit
  code badge and footer in the console. Each interpolates a value, and the
  catalog only carried the plain key.
- "Analyze last run" and "View Latest Diagnosis" no longer open a small empty
  sheet that only cmd-period could dismiss. The sheet was presented on a flag
  while its content read a separate optional, which SwiftUI can evaluate
  before the value lands; both are presented from the value itself now.
- The bottle's "Export Diagnostic Report" and "View Latest Diagnosis" buttons
  can enable. A recorded crash diagnosis never stamped the program's last
  diagnosis date, so the buttons stayed disabled forever and the ZIP export
  was unreachable.
- The crash diagnosis sheet has a Done button. It had no control of its own,
  so the only way out was cmd-period or closing the window behind it.
- "Analyze last run" is disabled until the program has a run to analyze.
  Before the first run it clicked through to nothing.
- The crash diagnosis history on a program's page refreshes when a diagnosis
  is recorded while the page is open, instead of waiting for it to be reopened.
- A program pinned in a bottle created during the same session now shows up
  in the library, the Dock menu, and the menu bar extra right away. The
  bottle list was rebuilt at the end of creation, so the bottle page kept
  writing to an instance the rest of the app no longer read.
- "Terminate Wine processes when Whisky closes" (and a bottle's Always Kill
  policy) now actually ends the bottle's processes on quit. Two things kept
  it from working: the setting read as off until the toggle had been touched
  once, because its default was never written to disk, and the kill was
  queued asynchronously from the termination handler, so the app exited
  before it ran.
- "Audio Troubleshooting" no longer opens as a small empty sheet. Same cause
  as the diagnosis sheet: presented on a flag while the content read a
  separate optional; it is presented from the engine itself now.
- The bottle's Terminal button works for bottles whose name contains a space.
  The name was backslash-escaped inside double quotes, so the shell passed
  the backslashes through and WhiskyCmd reported that no such bottle exists.
- Guided troubleshooting no longer dead-ends on a findings card. Info steps
  such as "Missing dependencies found" only carry a Continue transition, and
  nothing followed it; the wizard now shows a Continue button there, and Skip
  moves on as well.
- Guided troubleshooting no longer reports "Problem resolved" when it has
  run out of automated steps. The flows' escalation node shares the export
  phase with the resolved node, and the wizard drew both the same way; a node
  that hands off to the escalation fragment now shows the escalation screen
  with its export and retry options.
- Applying a game configuration now sets the graphics backend it lists. The
  entry's legacy DXVK flag was written after the backend and its "off" value
  meant "back to Recommended", so every apply ended on Recommended while the
  toast said it had applied. The preview also no longer lists Sequoia
  Compatibility Mode, a setting that no longer exists.
- Export as Archive writes the bottle as `<folder>/...` entries instead of
  its absolute path, so the archive no longer carries the user's home
  directory name and extracts where it is opened. Neither export carries
  AppleDouble `._` files any more.
- The Duplicate Bottle sheet's confirm button says Duplicate, not Rename.
- Guided troubleshooting's install step names the verb it will install after
  a resumed session, and its game-database check sees the program the wizard
  was opened from.
- Cancelling a dependency install stops it. Cancel only closed the sheet,
  leaving winetricks and the installer it had spawned running in the bottle;
  it now cancels the install and ends the bottle's Wine processes.
- Diagnostic exports with "Include sensitive details" off no longer carry
  credentials in plain sight. Launch arguments were written to the archive
  verbatim regardless of the toggle, and log redaction only rewrote the home
  path, so a `-token` argument or a bearer token a game logged went out in a
  ZIP the sheet described as scrubbed. Arguments and both log members now
  have common secret shapes removed (`name=value` and `--name value` forms
  for token, password, secret and key style names, Bearer and Basic
  credentials, URL user info, sensitive query parameters, JWTs), and the
  sheet says so. It is best effort by nature; the toggle still exports raw.
- Running a winetricks verb from the bottle's Winetricks screen no longer
  hands the bottle's path to the terminal as shell text. A bottle imported
  from a directory whose name carried `$(...)` or backticks would have had
  that executed in the user's terminal; the command now goes through a temp
  script with every value quoted, the same route as the bottle's own Open
  Terminal, which also means it follows the preferred terminal setting
  (iTerm and Warp) instead of always opening Terminal.
- A Windows executable whose icon declares a bitmap height of exactly
  -2147483648 no longer crashes Whisky while the library renders its icon.
  The parser took the absolute value of that height before checking its
  range, and that value has no absolute value in 32 bits.
- Installing the Visual C++ Runtime from the Dependencies panel no longer
  fails silently on a stale checksum. Microsoft rotates the vc_redist
  binaries in place, so the SHA256 sums pinned in the bundled winetricks go
  stale between releases and the unattended install aborted with exit 1,
  leaving the panel on "Not Installed" with no hint why. The vcrun verbs now
  run with --force; every other verb keeps checksum enforcement (#233).
- A bottle opened on a runtime from the other Wine lineage no longer starts
  with an empty profile. Every Wine build names the profile after your Unix
  user, but CrossOver-lineage builds (the GPTK-capable v4 engines) hardcode
  `users/crossover` for the shell folders, so the same bottle had two profile
  directories depending on the engine and apps in it saw whichever was empty:
  Steam asked for a login again, saves were gone, nothing errored. Whisky now
  makes the profile reachable under both names before every launch, and only
  ever displaces a directory that is an untouched skeleton (moved aside inside
  the bottle, never deleted). Two populated profiles are left alone.
- The launch failure alert from the menu bar extra showed its raw localization
  key as a title instead of "Couldn't launch <name>". The key was looked up
  with the program name baked in, so it never matched the catalog entry; the
  name is now substituted into the translated string. The same alert serves
  Dock menu and whisky:// launches, so it would have shown far more often.
- Games that check the graphics driver version can start. D3DMetal answers the
  DXGI query with success and a version of -1, which reads back as
  65535.65535.65535.65535 and fails every minimum-driver check: Helldivers 2 put
  a modal "GPU drivers are out of date" box in front of the game. A runtime that
  carries the DXGI interposer is now deployed with it, answering the same version
  Wine already publishes for the adapter so the two agree. It has to be its own
  module rather than part of the D3D12 one, because the check happens before a
  game touches D3D12 at all. Runtimes without it are skipped as before (#227).
- DLSS frame generation is offered to games Steam launches. Whisky steers Steam
  itself onto DXVK so its Chromium helper paints, and it was stripping
  CX_ACTIVE_GRAPHICS_BACKEND along with the rest of the DXVK-versus-D3DMetal
  environment. That variable selects no backend: the only thing in the runtime
  that reads it is win32u, and all it does there is answer the hardware
  scheduling query. Steam's games inherit Steam's environment and run on
  D3DMetal, since DXVK has no d3d12, so stripping it left every one of them
  reporting that frame generation needs GPU hardware scheduling turned on. It
  now survives the DXVK and DXMT overrides, and is still dropped for wined3d,
  which is the one path with no D3DMetal behind it. The variable is only set
  at all when the bottle's frame generation toggle is on (#225, #231).
- Games that decode video themselves no longer fall back to a broken
  half-resolution path under D3DMetal: when the runtime ships the D3D12
  video processor interposer, it is installed automatically alongside the
  GPTK payload (#197).
- The Play Test Tone button now actually plays a tone. The test executable
  was never included in any build, so the button silently did nothing and
  then asked whether you heard it. The tone is also gentler: 600ms with
  fades instead of a 100ms full-scale click (#209).
- Audio settings, the console, and program overrides no longer show raw
  localization keys in place of text on English systems: the English source
  strings were missing from the catalog and have been restored (#207).
- Troubleshooting fixes now do what their cards say: the crash banner's
  buttons open the diagnosis they promise, remediation cards actually apply
  (winetricks installs run and report their real outcome, and a fix that
  cannot be performed is recorded as failed rather than applied), and the
  troubleshooting wizard is localized (#213).
- The shader cache toggle now controls the cache DXVK actually reads, and a
  dxvk.conf file placed in the bottle root is picked up at launch. The
  Recommended backend applies the same availability check as the backend
  picker, so it can no longer select a backend whose payload is missing and
  then fail at launch (#216).
- The audio driver and latency settings now actually take effect: they are
  written to the bottle's Wine registry at launch, which nothing did before,
  so the options were recorded but never applied (#214).
- Crash diagnosis now covers games that die later in a session, not just at
  launch: classification runs when the bottle's Wine session actually ends,
  and it reads the start of the log as well as the end, which is where
  missing-DLL and backend failures appear (#217).
- A D3DMetal bottle answers when a game asks whether hardware accelerated GPU
  scheduling is available. Wine only answers that query for a caller that says
  it is running on D3DMetal, and nothing said so, so the answer was always that
  the feature is not implemented. Since #231 the bottle says so only when its
  frame generation toggle is on.
- DirectX 12 games run again in a bottle set to DXVK or DXMT. Neither ships a
  d3d12 of its own and neither said so, so that one DLL quietly fell through to
  D3DMetal while the rest of the stack was not. A DX12 game took its adapter
  from one translation layer into the other and died before it drew anything,
  with no error of its own to show for it. Both now turn d3d12 off, so such a
  game falls back to DirectX 11 rather than half landing on something else, and
  a bottle or a single program set to D3DMetal gets real DirectX 12 back.
- Newly created bottles are now immediately interactive: the inFlight guard
  is reset after a successful creation so that state-dependent actions (move,
  export, duplicate) no longer require an app restart to become available.

## [3.6.1] - 2026-08-13 (App)

### Changed
- With D3DMetal installed, the Recommended graphics backend now resolves
  launchers to DXVK, since their Chromium-based clients cannot render on
  D3DMetal, while the games they start still resolve to D3DMetal. Bottles
  without D3DMetal installed behave exactly as before (#188).
- Interrupted runtime downloads now resume where they left off and retry
  transient failures automatically instead of restarting the full archive
  from zero. Partial downloads survive quitting the app, the Retry button
  continues rather than starts over, and a completed archive left behind by
  an interrupted setup is verified and reused. The SHA-256 integrity check
  before install is unchanged (#174).
- Pressing Play on a Steam game no longer creates settings files for every
  executable near the game's install folder: only the program that actually
  launches is materialized, so Play is snappier for games that ship many
  helper executables and bottles stop accumulating unused settings plists
  (#181).
- Waiting for a cold Steam client no longer spawns a Wine tasklist process
  every two seconds: a host-side process check answers the common
  nothing-running-yet case, so cold starts stop competing with the client
  they are waiting for (#189).

### Added
- Creating a bottle on an external or network volume now checks the location
  up front, while the creation sheet is still open: if macOS is withholding
  Files and Folders access, the sheet says so and offers a direct route to
  the privacy settings instead of failing later with a cryptic prefix error.
  The default location is checked on submit too, and creation stays disabled
  until the location is usable (#190, #191).
- Community translations from Crowdin for the new interrupted-setup message,
  covering all 22 supported languages (#195).

### Fixed
- The external-volume checks above now actually engage on disk images and
  other removable volumes that macOS cannot place on a bus: those volumes
  answer nil rather than false to the internal-volume query, so both the
  consent check and the capacity fallback had classified them as internal
  and never ran (#193).
- Bottles on non-APFS removable drives are no longer refused as "full" when
  the drive has plenty of space: the capacity check now falls back to the
  standard figure on external volumes, where the purgeable-space service
  behind the preferred figure has no backing and reports zero (#192).
- DLL overrides now reach Wine through the prefix registry instead of the
  WINEDLLOVERRIDES environment variable: the bottle's set goes to the prefix
  default and the launched program's resolved set to its own AppDefaults
  entry (helper processes like steamwebhelper.exe included). A launcher's
  graphics backend no longer silently becomes every game's backend, and
  per-program backend overrides now take effect instead of being masked by
  the inherited variable (#184, #185).
- The DLL Overrides section now lists the managed overrides of the graphics
  backend actually in effect: a DXMT bottle shows the four entries it applies
  at launch instead of none, and a stale legacy DXVK flag no longer credits a
  D3DMetal bottle with overrides that are never applied (#186).
- Program override settings now resolve Recommended before reporting: the
  DXVK sub-controls appear for a program that resolves to DXVK, and the
  inherited summary names the backend that actually runs instead of reading
  "Recommended" (#187).
- A bottle no longer shows up twice in the bottle list and `whisky list`
  when the registry holds the same path in two URL forms (with and without
  a trailing slash). The registry now compares canonical paths everywhere
  entries are added, and a registry already carrying duplicates is healed
  on first load (#183).
- `whisky run` now passes options it doesn't recognize through to the
  program, so `whisky run MyBottle app.exe --disable-gpu` works without a
  bare `--` separator. A program option that shares a name with one of
  run's own options still goes after `--`, which the help text now
  explains (#183).
- The command line tool now uses consistent exit codes: 64 with a usage
  block only for malformed invocations, and 1 with a plain error on stderr
  for well-formed commands that fail (no such bottle, game not found). The
  convention is documented in `whisky --help`, and `run` and `launch` still
  pass through the launched program's own exit code (#182).
- Steam game routes are now forgotten when their bottle is deleted instead
  of lingering in the routing store; removing a bottle from the list while
  keeping its files preserves the routes so a re-imported bottle picks them
  back up (#180).
- Output from very short-lived Wine processes is no longer occasionally
  lost: a race between the pipe reader and the termination drain could
  finish the process stream before the final chunk was delivered, dropping
  it from logs and the in-app output view. This was also the cause of the
  long-standing intermittent CI failure in the process stream tests.

## [3.6.0] - 2026-08-04 (App)

### Added
- Settings gains a Game Porting Toolkit section: point it at your own
  download of Apple's evaluation environment (the disk image or a mounted
  volume) and the D3DMetal payload is validated and imported. Imported
  payloads are stored safely across engine updates and deploy automatically
  once an engine capable of running them is installed; the section states
  plainly whether the current engine can (#164).
- Bottles with Steam installed now show a games library: installed games are
  listed with their state (running, downloading, update stalled), and Play
  brings the client up quietly, starts the game, and applies its community
  configuration for that launch only instead of rewriting bottle settings.
  Per-program settings you have tuned yourself still win over the community
  profile (#161).
- The command line tool gains `whisky games` (list a bottle's installed
  Steam games) and `whisky launch <appid>` (launch one), both with `--json`
  output. Launches route through the same pipeline as the app's Play
  button, remember which bottle an App ID last launched from, and need no
  `--bottle` flag for games installed in one place (#169).
- Whisky is now fully translated in all 22 supported languages: Arabic,
  Chinese (Simplified and Traditional), Czech, Danish, Dutch, Finnish,
  French, German, Italian, Japanese, Korean, Polish, Portuguese (Brazil
  and Portugal), Romanian, Russian, Spanish, Swedish, Turkish, Ukrainian,
  and Vietnamese. Translations are managed on Crowdin, where corrections
  and improvements from native speakers are welcome (#177).

### Changed
- Program shortcuts now launch through the live pipeline instead of baking
  the environment in when the shortcut is created: a shortcut made today
  picks up tomorrow's graphics, GameDB, and override changes. Existing
  shortcuts keep working; recreate a shortcut to adopt the new behavior
  (#169).

### Fixed
- The sidebar's running-status check no longer writes a log file per probe:
  at one probe per minute per visible bottle, the old path accumulated
  ~1440 stray log files per idle bottle per day and rescanned the whole log
  folder each time, all on the main thread. The probe now asks wineserver
  directly, with no logging side effects (#153).
- A failed bottle move no longer corrupts the bottle's state. Previously the
  pin and blocklist paths were rewritten (and saved) to point at the new
  location before the move was attempted, and the bottle stayed marked busy
  until the app restarted; both are now rolled back when the move fails
  (#154).
- Bottle actions no longer re-enable mid-operation: a bottle that is
  exporting, duplicating, or moving keeps its busy state even when the
  bottle list reloads (previously any registry reload, such as creating a
  bottle or re-importing an orphan, dropped the guard and let conflicting
  actions run against files still being copied) (#155).
- Games installed in a Steam library are no longer mistaken for the Steam
  client: executables under `steamapps/common` stop inheriting the client's
  compatibility profile and get their own launcher detection instead (a
  Rockstar title bought on Steam now detects the Rockstar launcher).
  Launches from the program list and pins also run launcher detection now,
  matching every other launch path (#160).
- Two programs sharing a filename (the classic `Launch.exe` case) no longer
  share one settings file. Settings are now keyed by the program's location
  inside the bottle, existing settings migrate automatically, and the old
  files are kept so downgrading loses nothing (#162).

## [3.5.2] - 2026-07-30 (App)

### Added
- Bottles on disk that aren't in the library — created by an older version,
  left behind by a reset registry, or restored from a backup of the Bottles
  folder — are now detected at startup and offered for one-click re-import
  (Closes #145).

### Changed
- Engine archive extraction is now staged: the archive is unpacked and its
  symlinks audited in a temporary directory, and only content that passes
  every safety check is moved into place. A rejected archive leaves the
  existing installation completely untouched (Closes #147).

### Fixed
- The backend picker no longer offers D3DMetal when the installed engine
  doesn't include it, and bottles already configured for D3DMetal show a
  warning explaining the WineD3D fallback instead of games failing silently
  at launch (Closes #146).
- The "Recommended" graphics backend now resolves to one the installed
  runtime actually provides: DXMT when the runtime bundles it, otherwise
  DXVK, and D3DMetal only when its payload is present. Previously it always
  chose D3DMetal, which the runtime doesn't ship, so fresh bottles silently
  fell back to wined3d and DirectX 11 games failed to launch out of the box
  (Fixes #141).
- First-run engine setup no longer fails with "Archive contains unsafe path"
  on systems whose language formats dates day-first (e.g. UK or French
  locales). The archive safety check parsed tar's localized listing and
  wrongly rejected every entry; the listing now runs with a pinned locale so
  it reads the same everywhere (Fixes #139).
- An unreadable bottle registry no longer silently wipes the bottle list. On
  startup the corrupt file is moved aside (an alert says where) and, when the
  file is in the older paths-only fallback format, the bottle paths are
  recovered instead of being overwritten with an empty list (Refs #61).
- Bottle creation now fails loudly when the new bottle can't be saved to the
  registry: the save is verified on disk and the existing failure alert (with
  copyable diagnostics) fires. Previously the error case existed but was never
  raised, so the bottle silently vanished on the next launch (Refs #61).
- Creating a bottle while the Wine runtime (WhiskyWine) isn't installed now
  shows a clear "runtime missing" error with a Run Setup button instead of a
  low-level file-not-found failure (Refs #61).
- The Winetricks button now shows an error when the bundled winetricks
  resources can't be found, instead of silently doing nothing (Refs #134).

## [3.5.1] - 2026-07-24 (App)

### Fixed
- Installing bottle dependencies (VC++, .NET, DirectX, fonts) and the Winetricks
  verb browser now work out of the box. `winetricks` was expected inside the
  downloaded Wine runtime but was never shipped there, so dependency installs
  failed with a missing-file error and the verb list showed empty. `winetricks`
  (and its verb catalog) are now bundled in the app itself, so they work on a
  clean install with no extra setup (Closes #134).

## [3.5.0] - 2026-06-14 (App)

### Added
- Bottle configuration options now carry inline descriptions explaining what
  they do. The Wine section (Windows version, build, enhanced sync, DPI, Retina
  mode) and the DXVK section (DXVK, async, HUD) previously had no explanation;
  each now shows a one-line caption so you can make an informed choice without
  hunting through docs (Closes whisky-app/whisky#807).
- Optional menu-bar extra (**Settings → General → "Show Whisky in the menu
  bar"**, off by default). When enabled, a menu-bar item lets you launch a
  bottle's pinned programs, reopen Whisky, or quit without the main window
  focused — and Whisky keeps running after the window is closed, so it stays
  reachable from the menu bar and running Wine processes aren't terminated.
  When disabled, behaviour is unchanged (Closes whisky-app/whisky#571).

### Changed
- Scanning a bottle for installed programs now runs off the main thread —
  walking the `Program Files` trees and parsing each executable's metadata no
  longer blocks the UI, so opening or switching to a bottle with many installed
  programs no longer hitches. The programs list shows a progress indicator while
  the scan runs (Closes whisky-app/whisky#574).
- Update checks are now gentler: a scheduled background check that finds a new
  version no longer interrupts you with a focus-stealing dialog. Instead a Dock
  badge appears and the "Check for Updates" menu item reads "Install Update…",
  so you can apply it when ready. User-initiated checks and the install itself
  are unchanged (Closes whisky-app/whisky#765).

## [3.4.0] - 2026-06-13 (App)

### Added
- DXMT (Direct3D 11 → Metal) as a selectable per-bottle and per-program
  graphics backend, marked Experimental. Deployed per-bottle like DXVK
  (native DLLs in the prefix), so selecting it for one bottle never affects
  others. Requires the matching Wine runtime that bundles the DXMT backend
  (shipped alongside this release); the backend card explains how to update
  when it's unavailable. D3DMetal remains the recommended default.

### Fixed
- Per-program graphics overrides now reliably win over the bottle's
  setting: the override UI's legacy DXVK flag could silently re-enable or
  disable the wrong translation layer when an explicit backend was chosen
  for a program.
- Installing or updating the Wine runtime no longer erases the rest of
  Whisky's Application Support folder. Previously the installer wiped the
  whole folder instead of just the runtime, destroying unrelated app state —
  including the telemetry queue and anonymous ID, which is why a completed
  install could go missing from the opt-in funnel.
- A launch error for a Windows program opened from Finder is no longer
  silently swallowed — it now surfaces as an error notification instead of
  only being logged while the dialog closes.

### Changed
- Wine runtime updated to Libraries v3.1.1, which ships DXMT 0.80 as the
  native per-bottle backend (see Added). Wine 11.0 and DXVK 1.10.3 are
  unchanged from the previous runtime.

## [3.3.0] - 2026-06-11 (App)

### Added
- Optional, **opt-in** anonymous usage telemetry. A checkbox during first-run
  setup (off by default, changeable anytime in Settings → Privacy) enables five
  anonymous events covering the first-run funnel — runtime install
  started/succeeded/failed (with a coarse reason), first bottle created, first
  program launch attempted — so install failures in the field become visible.
  The first-program-launch event now fires from both the programs list and a
  program's detail view, so no real launch path is missed. Nothing is sent
  without explicit consent; no person profile is created, and no personal data,
  paths, or raw error text is ever included. The full event list, the SDK context
  that accompanies it, and the IP/GeoIP handling are documented in the README and
  SECURITY.md.

### Fixed
- The first-run telemetry opt-in is now always reachable: when the Wine runtime
  is missing, setup no longer skips straight past the welcome screen (the only
  place the consent checkbox lives) before you can make a choice.
- Bottle and per-program settings are now written atomically, so a crash
  mid-save can no longer leave a truncated settings file that wipes the
  configuration.
- Every persisted settings choice — graphics backend, performance and resolution
  presets, Windows version, launcher mode/type/locale and spoofed GPU vendor,
  audio driver/latency/output mode, clipboard and process-cleanup policies, and
  the per-program equivalents — now tolerates an unknown value written by a newer
  Whisky. A single unrecognized choice falls back to its default (per-program
  overrides fall back to inheriting the bottle's choice) instead of failing to
  load the entire bottle's settings.
- An unreadable settings file is no longer silently overwritten. When a bottle's
  `Metadata.plist` or a program's settings plist can't be decoded (corruption or
  an unexpected file version), the original is moved aside to a
  `.corrupt-<timestamp>` sibling before defaults are written, so the unreadable
  data is preserved for recovery rather than destroyed.
- Closed several crash vectors when opening a Windows executable with crafted or
  corrupt headers during icon extraction (also reached by the Finder thumbnail
  extension): overflow traps in resource-offset math, unbounded recursion on
  circular or pathologically deep resource directories, and header reads
  straddling the end of a truncated file. Resource offsets are now resolved with
  overflow-checked math, the directory walk is depth-capped, and short reads are
  rejected instead of loading past the buffer.
- Hardened icon and thumbnail extraction against crafted executables that could
  previously hang the parser or render garbage: resource directory entry counts
  are clamped to the file size, the whole resource walk shares a total-entry
  budget so fan-out can't amplify, and icon bitmap dimensions and palette lengths
  are validated before reading pixels. An executable with no usable icon now
  falls back to a generic system icon instead of showing a blank tile.
- The "Failed to Export Diagnostics Report" alert is now localizable instead of
  English-only, matching the rest of the launcher diagnostics UI.

## [3.2.0] - 2026-06-10 (App)

### Added
- The Wine runtime download is now verified against a published SHA-256 before
  installation. A corrupted or truncated download is caught and rejected with a
  clear error and a retry, instead of unpacking a broken runtime. Runtime
  metadata that predates the published checksum still installs unchanged.

### Fixed
- Bottle creation now validates the chosen location before doing any work: if
  the folder isn't writable or the disk is nearly full, you get a clear,
  actionable error up front instead of the bottle silently disappearing after a
  cryptic Wine failure. Builds on the bottle-creation diagnostics added for
  issue #61.
- Runtime installation failures now surface their cause. `install(from:)`
  propagates the underlying error (missing tarball, disk full, archive
  extraction failure) instead of swallowing it, so the setup screen shows the
  specific reason and the diagnostics report captures it.
- A half-installed Wine runtime is no longer mistaken for a working one. The
  install check now requires the `wine64` binary on disk, not just the version
  file, so a partial extraction or removal prompts a clean re-install instead of
  leaving every bottle to fail with cryptic Wine errors.
- Bottle-creation error messages are now localizable instead of English-only,
  so non-English users see translated text when creation fails.

### Documentation
- Landing page (`frankea.github.io/Whisky`) now shows app screenshots, adds an
  honest "Graphics backends" section (D3DMetal default, why DXVK is pinned at
  1.10.3 by design, and the Wine-wide anti-cheat limitation), and bumps the
  advertised version to 3.1.0.
- Replaced the dead "Game Support wiki" links (the wiki page bounced to the repo
  root) across the README, landing page, and issue templates with the bundled
  Game Configurations database.

## [3.1.0] - 2026-06-08 (App)

### Added
- **File → Migrate from the Original Whisky** discovers bottles created by the
  archived original app (`com.isaacmarovitz.Whisky`) and imports them in one
  step, with checkboxes to choose which. Bottles are referenced in place —
  nothing is moved or copied — so the import is non-destructive and the original
  app keeps working, replacing the previous manual export/import dance.
- Bottle creation now copies host fonts (Arial Unicode, Arial, Tahoma) into
  `drive_c/windows/Fonts` so Unity titles render fallback glyphs instead of
  empty boxes (Closes whisky-app/whisky#1050).
- File pickers for "Run" and "Pin Program" now accept `.msix`, `.appx`,
  `.appref-ms`, and `.url` files in addition to `.exe`/`.msi`/`.bat`. Steam
  desktop shortcuts (`.url`) launch correctly via Wine's `start` handler
  (Closes whisky-app/whisky#756, whisky-app/whisky#815, whisky-app/whisky#826).
- Winetricks verb browser is searchable: filter the verb table by name or
  description (Closes whisky-app/whisky#763).
- Wine inherits the host timezone (`TZ`) so games keying off date/time render
  correctly instead of treating the bottle as UTC
  (Closes whisky-app/whisky#1001).
- PE icon extraction returns a generic Windows-executable system icon when
  parsing fails, so program tiles and pins never render blank
  (Closes whisky-app/whisky#687).
- Display sleep / screen saver is now suppressed via an `IOPMAssertion` for
  as long as any Wine process is registered. Controllers don't generate user
  activity events on macOS, so without this, gaming with only a controller
  would still trigger the screen saver
  (Closes whisky-app/whisky#547).
- Bundled GameDB ships 29 new per-game entries with curated configs that
  GAME-02/GAME-03 surface as one-click recommendations:
  - Diablo IV, Skyrim Special Edition, Warhammer 40,000: Space Marine
    (Closes whisky-app/whisky#813, whisky-app/whisky#1125, whisky-app/whisky#1246).
  - AVX-off recipes for Granblue Fantasy: Relink, Turtle WoW
    (Closes whisky-app/whisky#508, whisky-app/whisky#805).
  - DXVK + runtime recipes for Age of Empires II DE, Bannerlord II,
    Warframe, Thunderstore Mod Manager, Animal Well, Supermarket Together,
    Talos Principle 2, Street Fighter 6, PS Plus PC App, Fields of Mistria,
    Horizon Forbidden West, Injustice 2, Monster Hunter Wilds, Trackmania
    2020, Trackmania Nations Forever, Team Fortress 2, Potion Craft,
    TMNT: Shredder's Revenge, Assetto Corsa, Futureport 82
    (Closes whisky-app/whisky#314, whisky-app/whisky#524, whisky-app/whisky#548,
    whisky-app/whisky#594, whisky-app/whisky#647, whisky-app/whisky#679,
    whisky-app/whisky#699, whisky-app/whisky#757, whisky-app/whisky#769,
    whisky-app/whisky#782, whisky-app/whisky#845, whisky-app/whisky#867,
    whisky-app/whisky#880, whisky-app/whisky#891, whisky-app/whisky#982,
    whisky-app/whisky#1026, whisky-app/whisky#1037, whisky-app/whisky#1105,
    whisky-app/whisky#1192, whisky-app/whisky#1236, whisky-app/whisky#1281,
    whisky-app/whisky#1350).
  - D3DMetal-preferred recipe for Among Us (DXVK shadow glitch)
    (Closes whisky-app/whisky#1123).
  - "Broken/unplayable" entries for Cities: Skylines II and Metal Gear Solid
    Master Collection Vol. 1 with diagnostic notes
    (Closes whisky-app/whisky#1032, whisky-app/whisky#1268).
  - Classic-DDraw recipe (wineD3D + WinXP) for Zuma Deluxe
    (Closes whisky-app/whisky#484).
- Input config gains "Map Command Key to Windows Ctrl" toggle (under
  Controller Compatibility Mode). Writes
  `HKCU\Software\Wine\Mac Driver\{Left,Right}CommandIsCtrl` so common
  Cmd+A/C/V/S keystrokes register inside Wine apps as Ctrl+A/C/V/S
  (Closes whisky-app/whisky#1060).
- Setup/Welcome view's "Uninstall" button now offers two options: remove the
  WhiskyWine runtime only (preserves bottles for later reinstall) or remove
  everything (runtime + default bottles directory + BottleData registry).
  Bottles at custom paths outside the default directory are preserved
  (Closes whisky-app/whisky#411).
- The bundled DXVK version is now tracked alongside the runtime version. The
  WhiskyWine version record carries an optional `dxvkVersion`, and the setup
  diagnostics report gained a `[VERSION]` section listing the installed runtime
  and DXVK versions to speed up triage of runtime-mismatch issues. The field is
  backward-compatible: runtime plists without it still load.

### Changed
- Diagnostic reports (WhiskyWine setup and Wine prefix) now link to this fork's issue tracker
  (`frankea/Whisky`) instead of the archived upstream, so reports reach a maintained repo. Internal
  Logger subsystems and notification names also moved off the archived `com.isaacmarovitz.Whisky`
  namespace onto `com.franke.Whisky`.
- Bundled GameDB grows by 4 more entries from the third-pass retriage:
  DJMAX RESPECT V (Korean fonts + DXVK), They Are Billions (vcrun + DXVK),
  SpellForce 3 (corefonts + d3dcompiler), Fallout 4 (Sequoia compat + xact)
  (Closes whisky-app/whisky#748, whisky-app/whisky#890,
  whisky-app/whisky#980, whisky-app/whisky#1312).
- Bundled GameDB gains 20 more entries from the fourth-pass retriage —
  full coverage of the long tail of mainstream titles in the upstream
  backlog: Jusant, Ready or Not, Persona 3 Reload, Binding of Isaac,
  Trackmania Turbo, It Takes Two, Tales of Berseria, Cobalt Core,
  Psychonauts 2, Assassin's Creed Odyssey, killer7, Train Sim World 5,
  Black Mesa, Far Cry 4, Severed Steel, Halo: Master Chief Collection,
  Mortal Kombat Komplete Edition, YS X: Nordics, Slime Rancher 2,
  Monster Hunter: World (Iceborne) (Closes whisky-app/whisky#279,
  whisky-app/whisky#631, whisky-app/whisky#694, whisky-app/whisky#727,
  whisky-app/whisky#829, whisky-app/whisky#1025, whisky-app/whisky#1108,
  whisky-app/whisky#1119, whisky-app/whisky#1124, whisky-app/whisky#1137,
  whisky-app/whisky#1157, whisky-app/whisky#1160, whisky-app/whisky#1162,
  whisky-app/whisky#1180, whisky-app/whisky#1190, whisky-app/whisky#1208,
  whisky-app/whisky#1214, whisky-app/whisky#1235, whisky-app/whisky#1258,
  whisky-app/whisky#1320). The bundled DB now covers 79 titles.
- Diagnostic system-info reports use sysctl-based hardware detection
  (`hw.optional.arm64`) instead of the `#if arch(arm64)` compile-time
  macro, so a universal binary running its x86_64 slice through Rosetta
  no longer misreports the host as Intel
  (Closes whisky-app/whisky#1097).
- Installed-programs list filters out known launcher helpers and crash
  reporters (steamerrorreporter, steamservice, steamwebhelper, GameOverlayUI,
  vc_redist, UEPrereqSetup, the CrossOver HTML engine helper, etc.) so the
  visible list stays clean by default while leaving the user blocklist for
  app-specific filtering
  (Closes whisky-app/whisky#432, whisky-app/whisky#1215).
- WhiskyWine download survives transient Wi-Fi/Ethernet/VPN disconnects via
  `waitsForConnectivity` and bounded request/resource timeouts so a stalled
  download surfaces an error instead of hanging forever
  (Closes whisky-app/whisky#293, whisky-app/whisky#995, whisky-app/whisky#1020, whisky-app/whisky#1070).

### Fixed
- Wine no longer pegs a CPU core when a running process goes quiet. After a
  process closed its stdout/stderr but kept running, the pipe's readability
  handler fired continuously on the permanently-readable EOF condition. The
  handler now removes itself on EOF (the final bytes are still drained when the
  process exits), so an idle Wine process no longer spins
  (Closes whisky-app/whisky#917, whisky-app/whisky#1010).
- Moving a bottle no longer wipes its pinned-program list. The `move()` loop
  was shadowing the bottle's `url` with `pin.url`, causing
  `updateParentBottle` to compare a pin path against itself instead of the
  bottle root. Pin paths are now correctly rewritten to point at the new
  bottle location (Closes whisky-app/whisky#830).
- Right-click "Add to blocklist" no longer creates duplicate entries. The
  context-menu actions dedupe against the existing blocklist before
  appending, both for single-row and multi-selection cases
  (Closes whisky-app/whisky#431).
- DXVK installation no longer stops short when the bundle directory contains a
  non-DLL file. The copy loop returned on the first non-`.dll` entry (e.g. a
  stray `.DS_Store`), which could leave some DXVK DLLs uninstalled; it now skips
  non-DLL entries and continues.
- Pinning start-menu programs no longer stops at the first already-pinned entry.
  The pin loop returned early once it found a program already in the pin list,
  leaving every subsequent start-menu program unpinned; it now skips that entry
  and continues processing the rest.

### Documentation
- Added project governance and support docs: `docs/GOVERNANCE.md` (honest single-maintainer
  continuity stance), `docs/SUPPORT.md` (where to file and what to expect), and
  `docs/DEPENDENCIES.md` (pinned Wine/DXVK/D3DMetal/DXMT runtime components and their sources).
- Documented the reproducible runtime-assembly procedure in `docs/ReleaseWorkflow.md` (previously
  marked "out of scope") and added a weekly `RuntimeTrack` workflow that flags when a bundled runtime
  component falls behind upstream. The bug-report template now asks reporters to confirm they're on
  this fork rather than the archived original.
- `SECURITY.md` now documents how Wine/DXVK runtime vulnerabilities are handled — pinned versions are
  tracked against upstream, and a critical bundled-component CVE triggers an out-of-band runtime rebuild
  and release. Added `FUNDING.md` describing the volunteer, single-maintainer sustainability model.
- Removed the inherited CrossOver affiliate links (`ad=1010`) from the README and funding config; this
  fork has no affiliate or revenue-sharing arrangement, and those links credited the original project.

## [3.0.1] - 2026-05-01 (App)

### Fixed
- WhiskyWine install hung at "Installing WhiskyWine — Almost there" because
  `Tar.validateArchivePaths` waited for the `tar -tvzf` process to exit before
  reading its stdout pipe. With the 313 MB Wine Libraries archive the verbose
  listing easily exceeds the pipe buffer, so tar blocked writing while Whisky
  waited for it to finish — a classic pipe deadlock. The pipe is now drained
  before `waitUntilExit`.

## [3.0.0] - 2026-05-01 (App)

First app release of the active community fork of [whisky-app/whisky](https://github.com/whisky-app/whisky)
(archived April 2025). Resolves all 54 v1.0 milestone requirements covering 10 categories of
upstream issues (#40, #41, #42, #43, #44, #45, #47, #48, #49, #50). Bumps the macOS minimum
to 15 (Sequoia).

### Added
- Guided troubleshooting wizard with step-by-step diagnostic flows for 8 issue categories (Issue #50)
- Terminal application selection: choose between Terminal, iTerm2, or Warp (Refs #47, upstream #911)
- Duplicate bottle feature for cloning bottles without export/import (Refs #47, upstream #822)
- App Nap management: disable macOS process throttling for better game performance (Refs #47, upstream #1297)
- Controller & Input Compatibility settings for game controller detection issues (Issue #42)
- Toast notifications showing launch success/failure feedback (Refs #49)
- Archive progress indicator with toast notifications for bottle export (Refs #49, upstream #827)
- Icon caching for faster program list loading (Refs #49, upstream #941)
- Improved UX for unavailable bottles with warning icon and quick remove button (Refs #49, upstream #1039)
- Retry button for failed config values (Build Version, Retina Mode, DPI) (Refs #49, upstream #967)
- Comprehensive Launcher Compatibility System including detection, diagnostics, and configuration
- Stability diagnostics export for crash/freeze reports (Refs #40)
- WhiskyWine download/install diagnostics with copy-to-clipboard workflow (Issue #63)
- SwiftFormat integration for automated code formatting
- DocC documentation for WhiskyKit public API
- Code coverage reporting and badges
- GitHub Pages and Releases infrastructure
- WhiskyKit test infrastructure and initial test suite
- Dependabot configuration for dependency updates

### Changed
- Refactored shared program launch logic into reusable `LaunchResult` and `launchWithUserMode()` (Issue #68)
- Refactored `BottleSettings` and `Wine` modules into smaller, focused components
- Replaced `print()` statements with `os.log` Logger for better debugging
- Consolidated CI workflows for improved efficiency
- Implemented proper thread safety by removing `@unchecked Sendable` usage
- Raised minimum deployment target from macOS 14 (Sonoma) to macOS 15 (Sequoia)
- AVX toggle and Sequoia compatibility mode are now always visible (no longer gated by OS version)

### Fixed
- Fixed Terminal launch (shift-click) producing malformed commands due to double-escaping (Issue #71)
- Fixed localization fallback showing raw keys to non-English users (Refs #49)
- Fixed WhiskyCmd `run` command not launching programs (now uses Wine directly) (Refs #49, upstream #1088, #1140)
- Corrected Dependabot Swift configuration
- Capped Wine process logs and pruned old logs to prevent excessive disk usage (Issue #46)
- Surface bottle creation failures with diagnostic information (Issue #61)
- Fixed winetricks dependency installs failing when %AppData% is empty (Issue #64)
- Fixed hardcoded "crossover" username in user profile path detection
- Added Wine prefix validation before running winetricks with repair option

### Security
- Process environment logging now records keys only (not values) to avoid persisting secrets in logs

### Removed
- Unmaintained CLI dependencies (SwiftyTextTable, Progress.swift)
- Removed `#available(macOS 15, *)` availability checks as macOS 15 is now the minimum

### Documentation
- Added comprehensive Launcher Troubleshooting and Steam Compatibility guides
- Removed obsolete Markdown files from the root and `docs/` directory
- Updated `README.md` and `CONTRIBUTING.md` to reflect current project state
- Consolidated documentation into the `docs/` directory

## [3.0.0] - 2026-01-18 (Wine Libraries)

### Changed
- Upgraded Wine from 7.7 to 11.0 (Gcenx stable build) for improved application compatibility
- Updated DXVK to macOS-compatible v1.10.3

### Fixed
- Steam "steamwebhelper is not responding" error caused by stubbed WSALookupServiceBegin (Issue #72)
- Improved networking stack for better launcher compatibility

## [2.5.0] - 2026-01-10

### Added
- Initial release of Whisky Wine binaries for this fork
- Wine/GPTK libraries packaged as `Libraries.tar.gz`
- GitHub Pages hosting for version metadata
- Sparkle appcast support for automatic updates
- Release workflow documentation

### Changed
- Fork setup with new distribution infrastructure
- Updated GitHub Pages URLs for the frankea fork

### Documentation
- Added `RELEASE_WORKFLOW.md` for publishing releases
- Added `DOCUMENTATION_AUDIT.md` for tracking documentation status
- Updated `README.md` with fork-specific information

---

## Categories Guide

When adding entries to this changelog, use the following categories:

- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Now removed features
- **Fixed** - Bug fixes
- **Security** - Vulnerability fixes
- **Documentation** - Documentation-only changes

[Unreleased]: https://github.com/frankea/Whisky/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/frankea/Whisky/releases/tag/v3.0.0
[2.5.0]: https://github.com/frankea/Whisky/releases/tag/v2.5.0
