# Distribution & discoverability playbook

The hard part of "becoming the main release" isn't code — it's that someone who googles *"Whisky
mac"* today lands on the **archived original** (getwhisky.app, `whisky-app/whisky`, and the default
`brew install --cask whisky` cask), not this fork. These are the concrete, mostly-external steps to
close that gap. Most require a real account or a third-party PR, so they're listed here as ready-to-run
actions rather than automated.

## 1. Homebrew (highest leverage)

The default `brew install --cask whisky` installs the archived `IsaacMarovitz/Whisky` v2.3.5 and will
forever unless the **homebrew-cask** maintainers change it. The fork can't rename its own tap into that
slot, but because the upstream is **archived**, there's a real case to repoint the core cask.

**Action — open a PR against [homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask)** that
either deprecates the `whisky` cask or repoints it at this fork. Draft for the PR description:

> The upstream `whisky-app/whisky` was archived on 2025-04-09 and the cask has pointed at an unmaintained
> v2.3.5 since. `frankea/Whisky` is an actively maintained fork (signed + notarized DMGs, in-app Sparkle
> updates). Proposing to update the `whisky` cask's `homepage`/`url` to the fork's releases, or
> `deprecate!`/`disable!` the cask with a note pointing users to `brew install --cask frankea/whisky/whisky`.

Expect pushback (renaming a cask's source is sensitive). If repointing is rejected, ask for a
`deprecate!` with a `caveats` note naming the fork — that alone fixes the "silent dead install" problem.

Until then, keep the README's "Getting the right Whisky" warning prominent and the qualified tap
(`frankea/whisky/whisky`) as the documented path.

## 2. Search & domain

- The GitHub Pages landing page (`dist/pages/`) already has solid on-page SEO (title, description,
  OpenGraph/Twitter cards, JSON-LD). The ceiling is **domain authority** — `frankea.github.io` shares
  authority across all of GitHub Pages.
- **Action:** consider a custom domain (e.g. `whisky.frankea.dev` or a `.app`) with a `CNAME` in
  `dist/pages/` and the Pages custom-domain setting. Marginal alone (~5-10%), meaningful **only** paired
  with backlinks below.
- **Action:** ask the archived `whisky-app` org (Isaac) whether the archived repo's README / getwhisky.app
  can carry a one-line "no longer maintained — see frankea/Whisky" pointer. A single backlink from the
  canonical domain is worth more than any on-page tweak.

## 3. Community presence (backlinks + word of mouth)

The macOS-gaming audience lives in a few places. Seeding them is the cheapest real discoverability win:

- **AppleGamingWiki** — Whisky is referenced on game pages but has no dedicated, fork-aware page.
  Create/claim one that names this fork as the maintained Whisky.
- **r/macgaming, r/macapps** — a single honest "the original Whisky was archived; I've been maintaining a
  fork" post (link the migration wizard — `File → Migrate from the Original Whisky` makes switching one
  click). Don't spam; one good post + answering replies.
- **A Discord** (or a pinned GitHub Discussion) as the support hangout, linked from the README.

## 4. Lower the switching cost (done / ongoing)

- ✅ One-click **File → Migrate from the Original Whisky** imports the original app's bottles in place.
- Lead with that in any launch post — "keep your existing bottles, one click" is the message that
  converts archived-app users.

## What's explicitly *not* in scope here

- App Store distribution is impossible — Wine needs JIT, full process control, and unsandboxed file
  access, all blocked by the App Store sandbox. GitHub Releases + Homebrew tap is the ceiling.
