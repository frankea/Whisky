# Support

Whisky is a community fork maintained by one person (see [`GOVERNANCE.md`](GOVERNANCE.md)). Support is
best-effort and free. This page sets honest expectations and points you at the fastest path to a fix.

## Before opening an issue

Most problems already have an answer:

1. **Make sure you're running this fork.** The default `brew install --cask whisky` installs the
   **archived original** (last updated April 2025), *not* this fork. This fork is
   `brew install --cask frankea/whisky/whisky`, or the DMG from
   [Releases](https://github.com/frankea/Whisky/releases/latest). Check **Whisky → About** — bugs in
   the archived original can't be fixed here.
2. **Search [existing issues](https://github.com/frankea/Whisky/issues?q=is%3Aissue).**
3. **Check the troubleshooting docs:**
   [Launcher](LauncherTroubleshooting.md) · [Steam](SteamCompatibility.md) · [Stability](StabilityTroubleshooting.md).
4. **For a specific game**, check the [Game Support wiki](https://github.com/frankea/Whisky/wiki/Game-Support)
   and use the **Game Compatibility Report** template.

## Where to go

| You have… | Go to |
|-----------|-------|
| A reproducible app bug | [New issue → Bug Report](https://github.com/frankea/Whisky/issues/new/choose) |
| A game that won't run right | [New issue → Game Compatibility Report](https://github.com/frankea/Whisky/issues/new/choose) |
| An idea | [New issue → Feature Request](https://github.com/frankea/Whisky/issues/new/choose) |
| A security report | See [`SECURITY.md`](../SECURITY.md) — **do not** open a public issue |
| A "how do I…" question | The troubleshooting docs and the Game Support wiki first |

**Do not open issues on the archived [whisky-app/whisky](https://github.com/whisky-app/whisky) repo** —
it is read-only and no one will see them.

## What to expect

This is a volunteer, single-maintainer project, so please calibrate accordingly:

- **Triage:** new issues are looked at as time allows — think days-to-weeks, not hours. There is no SLA.
- **A good report gets a faster fix.** Always include: Whisky version (**Whisky → About**), macOS
  version, the graphics backend, and — for crashes/freezes — the diagnostic export from
  **Bottle Configuration → View Diagnostics**. Reports missing these usually stall waiting on info.
- **Wine-layer limits:** Whisky configures and wraps Wine; it can't patch Wine itself. Some
  incompatibilities (anti-cheat, kernel drivers, and certain OS-version regressions) are genuinely
  outside what this app can fix — those get documented rather than "fixed."
- **English, please:** so any maintainer or contributor can read and act on the report.
