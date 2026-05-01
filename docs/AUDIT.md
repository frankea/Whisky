# Upstream Issue Audit

This fork tracks per-issue evidence of how it addresses the open issues
from the archived upstream
[whisky-app/whisky](https://github.com/whisky-app/whisky) (archived
2025-04-09). A small Python tool re-runs the classification on demand and
produces a diffable per-issue index.

## Why this exists

The fork shipped 54 v1.0 requirements covering 13 categories of upstream
issues. Until the audit existed, the honest answer to "have we fixed the
upstream issues?" was "categorically yes, individually unverified." The
audit replaces that with a per-issue table.

## How to read the numbers

Every classification carries a confidence level. Read carefully — "fixed"
means different things in different buckets.

| Status | What it really means |
|---|---|
| `addressed-direct` | The issue number is cited in CHANGELOG, code, docs, or a commit message. **High confidence.** |
| `addressed-categorical` | The issue's symptom class maps to a shipped v1.0 requirement category. **Infrastructure exists** (e.g. the troubleshooting wizard, dependency installer, crash classifier) — but for any specific user, that infrastructure still has to surface the right remediation in their specific case. Not equivalent to "verified fixed for this issue." |
| `wont-fix-out-of-scope` | Wine internals, anti-cheat, kernel, mobile, niche corporate apps. Not addressable from the app side. |
| `unverified` | Body too incoherent to triage, or genuinely needs reproduction. **Honest bucket.** |
| `upstream-fixed` / `upstream-declined` / `upstream-closed` | Already closed in upstream before archival. Listed for context, not work-in-progress. |

## GameDB entries: educated recipes vs. playtested configs

Most of the bundled `GameDB.json` entries that ship per-game configs are
rated `unverified`. They're community-recommended recipes inferred from
the engine, error pattern, and known-good Wine practice — **not** configs
that maintainers have personally validated by running the game.

The in-app Game DB UI surfaces this with:
- A `Community-suggested config` banner above the recommended config.
- The `Unverified` rating badge in gray.

When a recipe doesn't work for you, please file an issue against this
fork (not the archived upstream) so we can refine the entry.

## Running the tool

The tool is a single Python 3.12 script that fetches the upstream issue
list, runs heuristics, applies overrides, and produces a per-issue index.

```sh
# Install Python 3.12 from mise.toml (one-time)
mise install

# Heuristics-only, fetch on demand
python scripts/audit_upstream.py

# Force a fresh fetch from the upstream API
python scripts/audit_upstream.py --refresh

# Show "newly addressed" against an older ref
python scripts/audit_upstream.py --diff-against app-v3.0.1
```

Outputs land under `.planning/audit/` (gitignored — local working notes):

| File | Purpose |
|---|---|
| `snapshot.json` | Raw fetched issues, ~5–10 MB |
| `classified.json` | Per-issue enriched index, deterministically sorted |
| `AUDIT_REPORT.md` | Human-readable rollup with per-status × category counts |
| `overrides.json` | Hand-curated `{number: {status, rationale}}` annotations |

## How to keep it accurate

Going forward, the workflow is:

1. **Cite issues in commits and CHANGELOG.** Use the form
   `Closes whisky-app/whisky#NNN` or
   `(Closes whisky-app/whisky#NNN, whisky-app/whisky#MMM)`. The audit's
   citation grep covers `git log --all` and the source tree, so the
   issue moves from `unverified` to `addressed-direct` automatically.
2. **Add a GameDB entry** when fixing a per-game crash with a config
   recipe. Set `referenceURL` to the upstream issue URL and the audit
   picks it up as a direct citation.
3. **Use `overrides.json`** for issues fixed by inherited Wine/MoltenVK
   uplifts where there's no organic citation.

## Limitations

- **Silent fixes** read as `unverified` until cited or overridden. Add a
  `Closes whisky-app/whisky#NNN` line to fix.
- **Wine source patches** (atiadlxx, NtQuerySystemInformation, etc.) are
  marked `wont-fix-out-of-scope` from the app side; they would only
  become tractable via a Wine Libraries pipeline change.
- **Body excerpts capped at 2 KB** in the snapshot. Long bug reports
  lose context; subagent-driven retriage can fetch full bodies on
  demand.
- **Label drift.** Upstream labels were inconsistent; categorization is
  best effort.
- **No upstream-PR correlation.** The tool doesn't trace upstream PRs
  that closed issues before archival — those are upstream-fixed,
  separate from "did this fork address it."

The headline counts are honest about every status's confidence,
including the size of the `unverified` bucket. That's the point.
